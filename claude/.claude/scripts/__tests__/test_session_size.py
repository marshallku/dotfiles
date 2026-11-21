"""session-size.sh: tell the user once that a committed, oversized session is better continued
fresh, and the save ledger it relies on (~/save.sh records CLAUDE_CODE_SESSION_ID per commit).
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOKS = Path(__file__).resolve().parents[2] / "hooks"


class SessionSizeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(HOOKS)
        self.env = {**os.environ, "HOME": str(self.home)}

    def run_hook(self, name, payload):
        result = subprocess.run(["bash", str(self.home / ".claude/hooks" / name)],
                                input=json.dumps({"session_id": "s", **payload}),
                                text=True, capture_output=True, env=self.env, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout or "{}")

    def session(self, context):
        path = self.root / "session.jsonl"
        path.write_text(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "x"}],
            "usage": {"input_tokens": 2, "cache_read_input_tokens": context, "cache_creation_input_tokens": 0}}}) + "\n")
        return str(path)

    def saved(self, session="s"):
        with (self.home / ".claude/state/save-ledger.jsonl").open("a") as stream:
            stream.write(json.dumps({"ts": "2026-11-22T00:00:00Z", "session": session, "repo": "/r", "sha": "abc"}) + "\n")

    def nudge(self, transcript):
        return self.run_hook("session-size.sh", {"transcript_path": transcript}).get("systemMessage")

    def test_nudges_once_after_a_commit_in_a_large_session(self):
        self.saved()
        transcript = self.session(400_000)
        self.assertIn("If the current work unit is done", self.nudge(transcript))
        self.assertIsNone(self.nudge(transcript), "nudges only once per session")

    def test_no_nudge_without_this_sessions_commit_or_below_the_threshold(self):
        self.assertIsNone(self.nudge(self.session(400_000)), "no save ledger entry")
        self.saved(session="another-session")
        self.assertIsNone(self.nudge(self.session(400_000)), "another session's commit")
        self.saved()
        self.assertIsNone(self.nudge(self.session(200_000)), "below the threshold")

    def test_nudged_sessions_do_not_expire_with_age(self):
        self.saved()
        transcript = self.session(400_000)
        self.assertIsNotNone(self.nudge(transcript))
        nudged = self.home / ".claude/state/session-size-nudged.list"
        stamp = nudged.stat().st_mtime - 30 * 86400
        os.utime(nudged, (stamp, stamp))
        self.run_hook("session-start.sh", {"source": "startup"})
        self.assertIsNone(self.nudge(transcript), "a month-old session still got a second note")

    def test_save_script_records_the_session_in_the_ledger(self):
        repo = self.root / "repo"
        remote = self.root / "remote.git"
        subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(repo), "config", key, value], check=True)
        subprocess.run(["git", "-C", str(repo), "remote", "add", "origin", str(remote)], check=True)
        (repo / "f.txt").write_text("x")
        subprocess.run(["git", "-C", str(repo), "add", "f.txt"], check=True)
        script = HOOKS.parent.parent / "save.sh"
        env = {**self.env, "CLAUDE_CODE_SESSION_ID": "sess-1"}
        result = subprocess.run(["bash", str(script), "Add f"], cwd=repo, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = [json.loads(line) for line in (self.home / ".claude/state/save-ledger.jsonl").read_text().splitlines()]
        self.assertEqual(rows[-1]["session"], "sess-1")
        head = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True)
        self.assertEqual(rows[-1]["sha"], head.stdout.strip())


if __name__ == "__main__":
    unittest.main()
