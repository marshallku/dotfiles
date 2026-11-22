"""reap-disk.sh: regenerable clutter goes to the trash, everything else is only listed.

Runs against a temp HOME with every root overridden and the trash redirected
(REAP_DISK_TRASH_DIR), so the real trash and real Chrome clones are never touched.
"""
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
DAY = 86400


def age(path, days):
    stamp = time.time() - days * DAY
    for root, dirs, files in os.walk(path):
        for name in dirs + files:
            os.utime(os.path.join(root, name), (stamp, stamp))
    os.utime(path, (stamp, stamp))


class ReapDiskTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        self.scratch = self.root / "scratch"
        self.trash = self.root / "trash"
        self.chrome = self.root / "chrome"
        self.config = self.root / "config"
        self.config.mkdir()
        (self.config / "worktree-roots").write_text(f"{self.root / 'dev'}\n")
        self.env = {**os.environ, "HOME": str(self.home), "REAP_DISK_SCRATCH_ROOT": str(self.scratch),
                    "REAP_DISK_TRASH_DIR": str(self.trash), "REAP_DISK_CHROME_ROOT": str(self.chrome),
                    "REAP_DISK_CONFIG": str(self.config)}

    def reap(self, *args):
        result = subprocess.run(["bash", str(SCRIPTS / "reap-disk.sh"), "--quiet", *args],
                                text=True, capture_output=True, env=self.env, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads((self.home / ".claude/state/reap-disk.json").read_text())

    def session(self, name, days):
        path = self.scratch / "-proj" / name
        (path / "scratchpad").mkdir(parents=True)
        (path / "scratchpad/notes.md").write_text("x" * 4096)
        age(path, days)
        return path

    def test_dry_run_changes_nothing_and_apply_trashes_only_idle_scratch(self):
        old, fresh = self.session("old", 5), self.session("fresh", 0)
        state = self.reap()
        self.assertEqual(state["mode"], "dry-run")
        self.assertEqual([i["path"] for i in state["items"]], [str(old)])
        self.assertTrue(old.exists())
        state = self.reap("--apply")
        self.assertFalse(old.exists())
        self.assertTrue(fresh.exists())
        self.assertEqual(state["items"][0]["result"], "trashed")
        self.assertEqual(len(list(self.trash.iterdir())), 1, "moved to the trash, not deleted")

    def test_a_recent_file_keeps_an_old_session(self):
        old = self.session("busy", 5)
        (old / "scratchpad/notes.md").touch()
        self.assertEqual(self.reap()["items"], [])

    @unittest.skipIf(os.geteuid() == 0, "root reads everything")
    def test_an_unreadable_subdirectory_counts_as_busy(self):
        old = self.session("locked", 5)
        hidden = old / "scratchpad/hidden"
        hidden.mkdir()
        (hidden / "recent.txt").write_text("x")
        age(old, 5)
        hidden.chmod(0)
        self.addCleanup(hidden.chmod, 0o755)
        self.assertEqual(self.reap("--apply")["items"], [])
        self.assertTrue(old.exists())

    def test_same_basenames_never_overwrite_in_the_trash(self):
        agent = self.root / "agents"
        for parent in ("a", "b"):
            (agent / parent / "out").mkdir(parents=True)
            (agent / parent / "out/marker").write_text(parent)
            age(agent / parent, 5)
        (self.config / "targets").write_text(f"{agent}/*/out 3\n")
        state = self.reap("--apply")
        self.assertEqual([i["result"] for i in state["items"]], ["trashed", "trashed"])
        markers = sorted((p / "marker").read_text() for p in self.trash.iterdir())
        self.assertEqual(markers, ["a", "b"])

    def test_private_config_targets(self):
        agent = self.root / "agent-tmp"
        for name, days in (("herald-1", 5), ("herald-2", 1)):
            (agent / name).mkdir(parents=True)
            age(agent / name, days)
        (self.config / "targets").write_text(f"# company agents\n{agent}/herald-* 3\nbad-line x\n")
        paths = [i["path"] for i in self.reap()["items"]]
        self.assertEqual(paths, [str(agent / "herald-1")])

    def test_merged_clean_worktree_is_listed_not_moved(self):
        dev = self.root / "dev"
        remote, repo, wt = self.root / "remote.git", dev / "app", self.root / "wt-feature"
        run = lambda *a, cwd=None: subprocess.run(a, cwd=cwd, check=True, capture_output=True, env=self.env)
        run("git", "init", "-q", "--bare", "-b", "main", str(remote))
        run("git", "clone", "-q", str(remote), str(repo))
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            run("git", "-C", str(repo), "config", key, value)
        run("git", "-C", str(repo), "commit", "-q", "--allow-empty", "-m", "base")
        run("git", "-C", str(repo), "push", "-q", "origin", "HEAD:main")
        run("git", "-C", str(repo), "worktree", "add", "-q", "-b", "feature", str(wt))
        run("git", "-C", str(wt), "commit", "-q", "--allow-empty", "-m", "feature")
        run("git", "-C", str(wt), "push", "-q", "origin", "feature:main")
        run("git", "-C", str(repo), "fetch", "-q", "origin")
        run("git", "-C", str(repo), "remote", "set-head", "origin", "main")
        state = self.reap("--apply")
        listed = [i for i in state["items"] if i["target"] == "worktree"]
        self.assertEqual([(i["path"], i["result"]) for i in listed], [(str(wt), "list")])
        self.assertTrue(wt.exists())
        (wt / "dirty.txt").write_text("x")
        self.assertEqual([i for i in self.reap()["items"] if i["target"] == "worktree"], [], "dirty stays off")

    @unittest.skipUnless(platform.system() == "Darwin", "Chrome code_sign_clone is macOS only")
    def test_chrome_clone_with_an_open_file_is_kept(self):
        idle, busy = self.chrome / "code_sign_clone.idle1", self.chrome / "code_sign_clone.busy1"
        for clone in (idle, busy):
            (clone / "Contents").mkdir(parents=True)
            (clone / "Contents/bin").write_text("x")
            age(clone, 1)
        holder = subprocess.Popen(["tail", "-f", str(busy / "Contents/bin")])
        self.addCleanup(holder.kill)
        time.sleep(0.5)
        paths = [i["path"] for i in self.reap()["items"] if i["target"] == "chrome-clone"]
        self.assertEqual(paths, [str(idle)])

    @unittest.skipUnless(platform.system() == "Darwin", "Chrome code_sign_clone is macOS only")
    def test_a_failing_lsof_skips_chrome_clones(self):
        clone = self.chrome / "code_sign_clone.any1"
        (clone / "Contents").mkdir(parents=True)
        age(clone, 1)
        fake = self.root / "bin"
        fake.mkdir()
        (fake / "lsof").write_text("#!/bin/sh\necho n/partial\nexit 1\n")
        (fake / "lsof").chmod(0o755)
        self.env["PATH"] = f"{fake}:{self.env['PATH']}"
        self.assertEqual([i for i in self.reap()["items"] if i["target"] == "chrome-clone"], [])


class InstallerTests(unittest.TestCase):
    def test_print_names_the_script_and_a_bash4(self):
        result = subprocess.run(["bash", str(SCRIPTS / "reap-disk-install.sh"), "--print"],
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(".claude/scripts/reap-disk.sh", result.stdout)
        self.assertIn("--apply", result.stdout)
        marker = "<string>" if platform.system() == "Darwin" else "ExecStart="
        self.assertIn(marker, result.stdout)


if __name__ == "__main__":
    unittest.main()
