"""wait-for.sh: one call instead of hand-written polling loops (958 sleeps / 8.4 h a month).

Fake gh/curl return a scripted sequence of replies, one per call, so each test checks the
transition the agent waits for: pending → passed, pending → failed, timeout.
"""
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "wait-for.sh"
FAKE = '''#!/usr/bin/env python3
import json, os, pathlib, sys
state = pathlib.Path(os.environ["FAKE_STATE"])
replies = json.loads(state.read_text())
calls = pathlib.Path(str(state) + ".calls")
n = int(calls.read_text()) if calls.exists() else 0
calls.write_text(str(n + 1))
args = sys.argv[1:]
pathlib.Path(str(state) + ".args").open("a").write(json.dumps(args) + "\\n")
if args[:2] == ["run", "view"]:
    print("step 3: error: tests failed")
    sys.exit(0)
reply = replies[min(n, len(replies) - 1)]
print(reply if isinstance(reply, str) else json.dumps(reply), end="")
'''


def pr(state="OPEN", checks=(), merged=None, decision=None):
    return {"state": state, "mergedAt": merged, "reviewDecision": decision, "url": "https://gh/pr/7",
            "statusCheckRollup": list(checks)}


def check(name, status="COMPLETED", conclusion="SUCCESS"):
    return {"name": name, "status": status, "conclusion": conclusion}


class WaitForTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("gh", "curl"):
            path = self.bin / name
            path.write_text(FAKE)
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
        self.state = self.root / "state.json"
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "FAKE_STATE": str(self.state)}

    def wait(self, *args, replies, timeout="20"):
        self.state.write_text(json.dumps(replies))
        # Options go before the arguments: after `cmd --` every word belongs to the command.
        return subprocess.run(["bash", str(SCRIPT), args[0], "--interval", "0", "--timeout", timeout, *args[1:]],
                              text=True, capture_output=True, env=self.env, timeout=60)

    def test_pr_checks_pass_after_pending(self):
        result = self.wait("pr", "7", "--checks", replies=[
            pr(checks=[check("build", "IN_PROGRESS", None)]),
            pr(checks=[check("build"), check("lint", conclusion="SKIPPED")])])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("all 2 checks passed", result.stdout)
        self.assertEqual(len(result.stdout.strip().splitlines()), 1, "one final line")

    def test_pr_checks_fail_names_the_failures(self):
        result = self.wait("pr", "7", "--checks", replies=[pr(checks=[check("build"), check("e2e", conclusion="FAILURE")])])
        self.assertEqual(result.returncode, 1)
        self.assertIn("checks failed: e2e", result.stdout)

    def test_finished_pr_without_checks_does_not_wait(self):
        self.assertEqual(self.wait("pr", "7", "--checks", replies=[pr(state="MERGED")]).returncode, 0)
        self.assertEqual(self.wait("pr", "7", "--checks", replies=[pr()], timeout="1").returncode, 124)

    def test_pr_merged_and_closed(self):
        self.assertEqual(self.wait("pr", "7", "--merged", replies=[pr(), pr(state="MERGED", merged="2026-11-22T00:00:00Z")]).returncode, 0)
        self.assertEqual(self.wait("pr", "7", "--merged", replies=[pr(state="CLOSED")]).returncode, 1)

    def test_pr_approved_and_changes_requested(self):
        self.assertEqual(self.wait("pr", "7", "--approved", replies=[pr(), pr(decision="APPROVED")]).returncode, 0)
        self.assertEqual(self.wait("pr", "7", "--approved", replies=[pr(decision="CHANGES_REQUESTED")]).returncode, 1)

    def test_run_failure_prints_the_failed_log_tail(self):
        result = self.wait("run", "--branch", "main", replies=[
            [{"databaseId": 9, "status": "in_progress", "conclusion": None, "workflowName": "CI",
              "url": "https://gh/o/r/actions/runs/9", "headSha": "a"}],
            [{"databaseId": 9, "status": "completed", "conclusion": "failure", "workflowName": "CI",
              "url": "https://gh/o/r/actions/runs/9", "headSha": "a"}]])
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("CI failure", result.stdout)
        self.assertIn("tests failed", result.stdout)
        list_args = json.loads((self.root / "state.json.args").read_text().splitlines()[0])
        self.assertIn("--branch", list_args)

    def test_url_waits_for_status_and_times_out(self):
        self.assertEqual(self.wait("url", "http://localhost:3000", replies=["000", "502", "200"]).returncode, 0)
        result = self.wait("url", "http://localhost:3000", replies=["502"], timeout="1")
        self.assertEqual(result.returncode, 124)
        self.assertIn("timed out", result.stdout)

    def test_cmd_until_success_and_timeout_shows_output(self):
        flag = self.root / "flag"
        ok = self.wait("cmd", "--", "bash", "-c", f'[ -e "{flag}" ] || {{ touch "{flag}"; echo not yet; exit 1; }}',
                       replies=[""])
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        # 3 s, not 1: on a loaded machine a 1 s probe can be killed at the deadline before it prints.
        stuck = self.wait("cmd", "--", "bash", "-c", "echo still broken; exit 1", replies=[""], timeout="3")
        self.assertEqual(stuck.returncode, 124)
        self.assertIn("still broken", stuck.stdout)

    def test_last_probe_runs_at_the_deadline(self):
        # Backoff 5 s with --timeout 3 used to give up right after the first probe.
        flag = self.root / "late"
        self.state.write_text("[]")
        subprocess.Popen(["bash", "-c", f'sleep 2; touch "{flag}"'])
        result = subprocess.run(["bash", str(SCRIPT), "cmd", "--timeout", "3", "--", "test", "-e", str(flag)],
                                text=True, capture_output=True, env=self.env, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_hung_probe_cannot_outlive_the_timeout(self):
        marker = self.root / "child.pid"
        started = time.monotonic()
        result = subprocess.run(["bash", str(SCRIPT), "cmd", "--timeout", "2", "--", "bash", "-c",
                                 f'echo $$ > "{marker}"; exec sleep 100'],
                                text=True, capture_output=True, env=self.env, timeout=30)
        self.assertEqual(result.returncode, 124)
        self.assertLess(time.monotonic() - started, 10)
        pid = int(marker.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_usage_errors(self):
        self.assertEqual(self.wait("pr", "7", replies=[pr()]).returncode, 2)
        self.assertEqual(self.wait("nope", replies=[""]).returncode, 2)


if __name__ == "__main__":
    unittest.main()
