"""Sensors reach every edit path and the trip wires tell silence from death.

Runs the real hooks from an isolated HOME with fake type checkers on PATH.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


CLAUDE = Path(__file__).resolve().parents[2]
TS_ERROR = "src/a.ts(1,7): error TS2322: Type 'string' is not assignable to type 'number'."


class SensorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(CLAUDE / "hooks")
        (self.home / ".claude/settings.json").symlink_to(CLAUDE / "settings.json")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {**os.environ, "HOME": str(self.home), "PATH": f"{self.bin}:{os.environ['PATH']}",
                    "XDG_CACHE_HOME": str(self.root / "cache")}
        self.repo = self.root / "repo"
        (self.repo / "src").mkdir(parents=True)
        (self.repo / "tsconfig.json").write_text("{}")
        (self.repo / "src/a.ts").write_text("const a: number = 1;\n")
        (self.repo / ".gitignore").write_text("node_modules/\n")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.email=t@e.invalid", "-c", "user.name=T", "-c", "core.hooksPath=/dev/null",
                 "commit", "-qm", "init")

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True, env=self.env)

    def script(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def hook(self, name, payload, *args):
        result = subprocess.run(["bash", str(self.home / ".claude/hooks" / name), *args],
                                input=json.dumps({"session_id": "s", "cwd": str(self.repo), **payload}),
                                text=True, capture_output=True, env=self.env, cwd=self.repo)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout or "{}")

    def events(self, component):
        ledger = self.home / ".claude/state/hook-events.jsonl"
        lines = ledger.read_text().splitlines() if ledger.exists() else []
        return [e for e in map(json.loads, lines) if e["component"] == component]

    def bash_edit(self, command, write, **extra):
        payload = {"tool_input": {"command": command}, **extra}
        self.hook("track-bash-edit.sh", payload, "pre")
        write()
        return self.hook("track-bash-edit.sh", payload, "post")

    def test_bash_edit_reaches_dirty_log_and_typecheck(self):
        self.script(self.repo / "node_modules/.bin/tsc", f'echo "{TS_ERROR}"; exit 2\n')
        out = self.bash_edit("python3 - <<'PY'\n...\nPY",
                             lambda: (self.repo / "src/a.ts").write_text("const a: number = 'x';\n"))
        self.assertIn("error TS2322", out["hookSpecificOutput"]["additionalContext"])
        dirty = (self.home / ".claude/state/dirty-s.log").read_text()
        self.assertIn(str(self.repo / "src/a.ts"), dirty)
        self.assertNotIn("node_modules", dirty)  # ignored files are not candidates

    def test_non_ascii_paths_are_tracked(self):
        target = self.repo / "src/한글 file.ts"
        self.bash_edit("cat > x", lambda: target.write_text("x\n"))
        self.assertIn(str(target), (self.home / ".claude/state/dirty-s.log").read_text())

    def test_files_untouched_by_the_command_are_not_tracked(self):
        (self.repo / "src/a.ts").write_text("// edited before\n")
        old = time.time() - 120
        os.utime(self.repo / "src/a.ts", (old, old))
        self.assertEqual(self.bash_edit("ls", lambda: None), {})
        self.assertFalse((self.home / ".claude/state/dirty-s.log").exists())

    def test_git_moves_and_subagents_are_not_session_edits(self):
        touch = lambda: (self.repo / "src/b.ts").write_text("x\n")
        self.bash_edit("git pull --rebase 2>&1 | tail -3", touch)
        self.bash_edit("sed -i s/a/b/ src/a.ts", touch, agent_id="agent-1")
        self.assertFalse((self.home / ".claude/state/dirty-s.log").exists())

    def test_yarn_pnp_project_is_checked_not_skipped(self):
        (self.repo / ".pnp.cjs").write_text("")
        args = self.root / "yarn-args"
        self.script(self.bin / "yarn", f'''echo "$@" >> "{args}"
[ "$1" = bin ] && exit 0
echo "{TS_ERROR}"; exit 2
''')
        out = self.hook("post-typecheck.sh", {"tool_input": {"file_path": str(self.repo / "src/a.ts")}})
        self.assertIn("error TS2322", out["hookSpecificOutput"]["additionalContext"])
        call = args.read_text().splitlines()[-1]
        self.assertIn("--incremental", call)
        self.assertNotIn(str(self.repo), call.split("--tsBuildInfoFile", 1)[1])  # build info stays out

    def test_pnp_without_typescript_still_skips(self):
        (self.repo / ".pnp.cjs").write_text("")
        self.script(self.bin / "yarn", "exit 1\n")  # `yarn bin tsc` fails: no typescript dependency
        self.assertEqual(self.hook("post-typecheck.sh", {"tool_input": {"file_path": str(self.repo / "src/a.ts")}}), {})
        self.assertEqual(self.events("post-typecheck")[-1]["reason"], "no_local_tsc")

    def test_unchecked_edits_leave_one_heartbeat_a_day(self):
        for _ in range(3):
            self.hook("post-typecheck.sh", {"tool_input": {"file_path": str(self.repo / "README.md")}})
        self.assertEqual([e["event"] for e in self.events("post-typecheck")], ["heartbeat"])

    def test_perl_timeout_fallback_kills_the_whole_group(self):
        only = self.root / "only-perl"
        only.mkdir()
        for name in ("perl", "sh", "sleep"):
            (only / name).symlink_to(subprocess.run(["sh", "-c", f"command -v {name}"], text=True,
                                                    capture_output=True).stdout.strip())
        script = f'''. "{CLAUDE / "hooks/_lib.sh"}"; PATH="{only}"
PORTABLE_TIMEOUT_KILL_AFTER=1 portable_timeout 1 sh -c 'sh -c "trap \\"\\" TERM; sleep 4; echo LEAKED" & wait'
echo "rc=$?"'''
        start = time.time()
        result = subprocess.run(["bash", "-c", script], text=True, capture_output=True, env=self.env)
        self.assertIn("rc=124", result.stdout)
        self.assertNotIn("LEAKED", result.stdout)
        self.assertLess(time.time() - start, 3.5)

    def tripwire(self):
        result = subprocess.run(["bash", str(CLAUDE / "scripts/harness-report.sh"), "--tripwire"],
                                text=True, capture_output=True, env=self.env)
        return result.stdout

    def test_silent_typecheck_without_edits_is_not_a_trip(self):
        ledger = self.home / ".claude/state/hook-events.jsonl"
        ledger.write_text(json.dumps({"ts": "2026-01-01T00:00:00Z", "component": "post-typecheck",
                                      "event": "pass"}) + "\n")
        self.assertNotIn("post-typecheck", self.tripwire())
        (self.home / ".claude/state/dirty-s.log").write_text("x\n")  # this machine edited files
        self.assertIn("post-typecheck", self.tripwire())

    def test_install_drift_trips(self):
        hooks = self.root / "perfile-hooks"
        hooks.mkdir()
        for f in (CLAUDE / "hooks").iterdir():
            if f.name != "_gh_merge_policy.py":
                (hooks / f.name).symlink_to(f)
        (self.home / ".claude/hooks").unlink()
        (self.home / ".claude/hooks").symlink_to(hooks)
        self.assertIn("hooks/_gh_merge_policy.py missing", self.tripwire())


if __name__ == "__main__":
    unittest.main()
