"""statusline.sh: runs on every refresh, so it must stay at one process and never scan whole transcripts.

Each test renders the status line from a fixture input with TMPDIR pointed at a scratch dir, so the
transcript cache is isolated; a PATH shim records every external command the script executes.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "statusline.sh"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
SHIMMED = ("jq", "git", "grep", "wc", "tail", "head", "date", "stat", "cut", "tr", "sed", "awk", "mkdir", "cat")


def record(kind, **fields):
    return json.dumps({"type": kind, **fields}, separators=(",", ":")) + "\n"


def bash_version(path):
    try:
        out = subprocess.run([path, "-c", 'echo "${BASH_VERSINFO[0]} ${BASH_VERSINFO[1]}"'],
                             capture_output=True, text=True, timeout=5).stdout.split()
    except OSError:
        return (0, 0)
    return tuple(int(x) for x in out) if len(out) == 2 and all(x.isdigit() for x in out) else (0, 0)


def clock_execs(path):
    """bash before 4.2 has no builtin clock, so the script runs date once per refresh."""
    return [] if bash_version(path) >= (4, 2) else ["date"]


class StatuslineTest(unittest.TestCase):
    BASH = "bash"
    CLOCK = clock_execs("bash")

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.state = self.tmp / "state"
        self.state.mkdir()
        self.shim = self.tmp / "shim"
        self.shim.mkdir()
        self.exec_log = self.tmp / "exec.log"
        for name in SHIMMED:
            real = shutil.which(name)
            if real is None:
                continue
            path = self.shim / name
            path.write_text(f'#!/bin/sh\necho {name} >> "{self.exec_log}"\nexec "{real}" "$@"\n')
            path.chmod(0o755)
        self.transcript = self.tmp / "session-1.jsonl"
        self.transcript.write_text("")

    def payload(self, cwd, **overrides):
        data = {
            "model": {"display_name": "Opus"},
            "workspace": {"current_dir": str(cwd)},
            "transcript_path": str(self.transcript),
            "context_window": {"used_percentage": 42.7},
            "cost": {"total_cost_usd": 1.234, "total_duration_ms": 3723000,
                     "total_lines_added": 5, "total_lines_removed": 2},
            "rate_limits": {"five_hour": {"used_percentage": 55.5}, "seven_day": {"used_percentage": 12}},
        }
        data.update(overrides)
        return json.dumps(data)

    def render(self, stdin):
        self.exec_log.write_text("")
        env = {**os.environ, "TMPDIR": str(self.state), "PATH": f"{self.shim}:{os.environ['PATH']}"}
        proc = subprocess.run([self.BASH, str(SCRIPT)], input=stdin, capture_output=True, text=True,
                              env=env, timeout=10)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stderr, "")
        return ANSI.sub("", proc.stdout).splitlines(), self.exec_log.read_text().split()

    def git(self, *args, cwd):
        subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)

    def make_repo(self):
        repo = self.tmp / "repo"
        repo.mkdir()
        self.git("init", "-q", "-b", "main", cwd=repo)
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "i", cwd=repo)
        return repo

    def cache_path(self):
        return self.state / f"claude-statusline-{os.getuid()}" / self.transcript.name

    def expire_cache(self):
        cache = self.cache_path()
        lines = cache.read_text().split("\n")
        offset = lines[0].split()[1]
        lines[0] = f"0 {offset}"
        cache.write_text("\n".join(lines))

    def test_renders_fields_with_only_jq_executed(self):
        repo = self.make_repo()
        (repo / "sub").mkdir()
        self.render(self.payload(repo / "sub"))
        lines, execs = self.render(self.payload(repo / "sub"))
        self.assertEqual(lines[0], "Opus sub main | +5-2")
        self.assertEqual(lines[1], "━━━━━━╌╌╌╌╌╌╌╌╌ 42% | $1.23 | 1h2m | 5h56% 7d12%")
        self.assertEqual(len(lines), 2)
        self.assertEqual(execs, ["jq", *self.CLOCK])

    def test_linked_worktree_and_detached_head(self):
        repo = self.make_repo()
        wt = self.tmp / "wt"
        self.git("worktree", "add", "-q", "-b", "feature/x", str(wt), cwd=repo)
        lines, execs = self.render(self.payload(wt))
        self.assertEqual(lines[0], "Opus wt feature/x (worktree) | +5-2")
        self.assertNotIn("git", execs)

        self.git("checkout", "-q", "--detach", cwd=repo)
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True).stdout
        lines, _ = self.render(self.payload(repo))
        self.assertEqual(lines[0], f"Opus repo {sha[:7]} | +5-2")

    def test_gitfile_outside_worktrees_is_not_labelled_worktree(self):
        sub = self.tmp / "module"
        gitdir = self.tmp / "super.git" / "modules" / "module"
        gitdir.mkdir(parents=True)
        (gitdir / "HEAD").write_text("ref: refs/heads/dev\n")
        (sub).mkdir()
        (sub / ".git").write_text("gitdir: ../super.git/modules/module\n")
        lines, _ = self.render(self.payload(sub))
        self.assertEqual(lines[0], "Opus module dev | +5-2")

    def test_non_repo_relative_and_missing_cwd(self):
        for cwd in (self.tmp, "relative/dir", ""):
            lines, _ = self.render(self.payload(cwd))
            self.assertNotIn("main", lines[0])

    def test_title_and_recap_are_cached_then_rescanned_incrementally(self):
        self.transcript.write_text(
            record("ai-title", aiTitle="First")
            + record("system", subtype="away_summary", content="Did a\nthing (disable recaps in /config)")
            + record("user", message="x" * 1000)
        )
        lines, execs = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], "◆ First — Did a thing")
        self.assertEqual(sorted(execs), sorted(["grep", "jq", "jq", "mkdir", "tail", "wc", *self.CLOCK]))

        with self.transcript.open("a") as f:
            f.write(record("ai-title", aiTitle="Second"))
        lines, execs = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], "◆ First — Did a thing")
        self.assertEqual(execs, ["jq", *self.CLOCK])

        self.expire_cache()
        lines, _ = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], "◆ Second — Did a thing")

    def test_record_split_across_scans_is_read_whole(self):
        full = record("ai-title", aiTitle="Split")
        self.transcript.write_text(record("user", message="a") + full[:10])
        self.render(self.payload(self.tmp))
        with self.transcript.open("a") as f:
            f.write(full[10:])
        self.expire_cache()
        lines, _ = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], "◆ Split")

    def test_first_scan_reads_only_the_tail_window(self):
        old = record("ai-title", aiTitle="Old")
        filler = record("user", message="y" * 1_000_000) * 9
        self.transcript.write_text(old + filler + record("ai-title", aiTitle="New"))
        lines, _ = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], "◆ New")

        self.transcript.write_text(old + filler)
        self.expire_cache()
        lines, _ = self.render(self.payload(self.tmp))
        self.assertEqual(len(lines), 2)

    def test_growth_beyond_window_after_first_scan_is_read_in_full(self):
        self.transcript.write_text(record("ai-title", aiTitle="Start"))
        self.render(self.payload(self.tmp))
        with self.transcript.open("a") as f:
            f.write(record("ai-title", aiTitle="Mid") + record("user", message="z" * 1_000_000) * 9)
        self.expire_cache()
        lines, _ = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], "◆ Mid")

    def test_rate_limits_round_like_printf(self):
        limits = {"five_hour": {"used_percentage": 48.5}, "seven_day": {"used_percentage": 80.6}}
        lines, _ = self.render(self.payload(self.tmp, rate_limits=limits))
        self.assertTrue(lines[1].endswith("| 5h48% 7d81%"), lines[1])

    def test_cache_symlink_is_neither_read_nor_written(self):
        victim = self.tmp / "victim"
        victim.write_text("0 0\nPlanted\n\n")
        self.cache_path().parent.mkdir(mode=0o700)
        self.cache_path().symlink_to(victim)
        self.transcript.write_text(record("ai-title", aiTitle="Real"))
        lines, _ = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], "◆ Real")
        self.assertEqual(victim.read_text(), "0 0\nPlanted\n\n")

    def test_title_is_printed_literally(self):
        self.transcript.write_text(record("ai-title", aiTitle=r"a\nb \c 100%s"))
        lines, _ = self.render(self.payload(self.tmp))
        self.assertEqual(lines[2], r"◆ a\nb \c 100%s")

    def test_invalid_input_falls_back_to_defaults(self):
        lines, _ = self.render("not json")
        self.assertEqual(lines[1], "╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ 0% | $0.00 | 0s")


@unittest.skipUnless(bash_version("/bin/bash")[0] == 3, "needs bash 3.2 at /bin/bash (macOS)")
class StatuslineBash32Test(StatuslineTest):
    """macOS /bin/bash 3.2 runs the script when Homebrew bash is not on Claude Code's PATH."""
    BASH = "/bin/bash"
    CLOCK = clock_execs("/bin/bash")


if __name__ == "__main__":
    unittest.main()
