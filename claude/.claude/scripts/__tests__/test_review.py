"""Integration tests run real Git and hooks with an isolated HOME and a fake Codex CLI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.home = self.root / "home"
        (self.home / ".claude").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(ROOT / "hooks")
        (self.home / ".claude/state").mkdir()
        (self.home / ".claude/state/notify-codex-disabled").touch()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        cli = self.bin / "codex"
        cli.write_text('''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys, time
prompt = sys.stdin.read()
pathlib.Path(os.environ["PROMPT_CAPTURE"]).write_text(prompt)
if os.environ.get("FAKE_CODEX_SLEEP"):
    time.sleep(1)
if os.environ.get("FAKE_DELEGATE_START"):
    scope = hashlib.md5(str(pathlib.Path.cwd()).encode()).hexdigest()[:12]
    state = pathlib.Path.home() / ".claude/state"
    (state / ("codex-delegate-active-" + scope)).mkdir()
    (state / ("codex-delegate-pending-" + scope)).touch()
args = sys.argv[1:]
pathlib.Path(os.environ["PROMPT_CAPTURE"] + ".codex-args").write_text(json.dumps(args))
if os.environ.get("FAKE_FAIL"):
    print("simulated CLI failure", file=sys.stderr)
    sys.exit(1)
if os.environ.get("FAKE_MUTATE"):
    pathlib.Path("code.py").write_text("changed_during_review = True\\n")
    if os.environ["FAKE_MUTATE"] == "stage":
        import subprocess; subprocess.run(["git", "add", "code.py"], check=True)
verdict = os.environ.get("FAKE_VERDICT", "APPROVED")
finding = os.environ.get("FAKE_FINDING", "")
critical = ("## CRITICAL\\n\\n- [C1] " + finding + "\\n\\n") if finding else ""
pathlib.Path(args[args.index("-o") + 1]).write_text(critical + "## Summary\\nDone.\\nVERDICT: " + verdict + "\\n")
print(json.dumps({"type":"thread.started", "thread_id":"test-thread"}))
print(json.dumps({"type":"turn.completed", "usage":{"input_tokens":100,"output_tokens":10,"cached_input_tokens":50}}))
''')
        cli.chmod(0o755)
        (self.home / ".codex").mkdir()
        (self.home / ".codex/AGENTS.md").symlink_to(ROOT.parent / ".codex/AGENTS.md")
        claude = self.bin / "claude"
        claude.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
prompt = sys.stdin.read()
pathlib.Path(os.environ["PROMPT_CAPTURE"]).write_text(prompt)
pathlib.Path(os.environ["PROMPT_CAPTURE"] + ".claude-args").write_text(json.dumps(args))
if os.environ.get("FAKE_NO_CLAUDE_SESSION") and "--resume" in args:
    print("No conversation found", file=sys.stderr)
    sys.exit(1)
if os.environ.get("FAKE_FAIL"):
    print("simulated Claude failure", file=sys.stderr)
    sys.exit(1)
if os.environ.get("FAKE_SLEEP"):
    time.sleep(3)
if os.environ.get("FAKE_MUTATE"):
    pathlib.Path("code.py").write_text("changed_during_review = True\\n")
    if os.environ["FAKE_MUTATE"] == "stage":
        import subprocess; subprocess.run(["git", "add", "code.py"], check=True)
verdict = os.environ.get("FAKE_VERDICT", "APPROVED")
session = "11111111-2222-3333-4444-555555555555"
print(json.dumps({"type":"system", "subtype":"init", "session_id":session}))
print(json.dumps({"type":"result", "subtype":"success", "session_id":session,
    "is_error": bool(os.environ.get("FAKE_CLAUDE_RESULT_ERROR")),
    "result":"## Summary\\nDone.\\nVERDICT: " + verdict + "\\n",
    "usage":{"input_tokens":100,"output_tokens":10},
    "modelUsage":{"fake-claude":{"inputTokens":100}},"total_cost_usd":0}))
''')
        claude.chmod(0o755)
        coctl = self.bin / "coctl"
        coctl.write_text("#!/bin/sh\nexit 0\n")
        coctl.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}",
                        PROMPT_CAPTURE=str(self.root / "prompt"))
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        (self.repo / "code.py").write_text("initial = True\n")
        self.git("add", ".")
        self.git("commit", "-qm", "initial")

    def run_cmd(self, args, **kwargs):
        return subprocess.run(args, cwd=self.repo, env=self.env, text=True, capture_output=True, **kwargs)

    def git(self, *args):
        result = self.run_cmd(["git", *args])
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def shell(self, command):
        result = self.run_cmd(["bash", "-c", f'. "{ROOT}/hooks/_lib.sh"; {command}'])
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def review(self, *args, status=0):
        result = self.run_cmd(["bash", str(ROOT / "scripts/codex-review.sh"), *args])
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        return result

    def gate(self):
        payload = json.dumps({"session_id":"s1", "cwd":str(self.repo),
                              "tool_input":{"command":"git commit -m test"}})
        result = self.run_cmd(["bash", str(ROOT / "hooks/pre-commit-gate.sh")], input=payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def write(self, name, text, session="s1", stage=True, repo=None):
        """Write as an Edit/Write call of `session` would (logged), optionally staging it."""
        repo = repo or self.repo
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        self.log_edit(session, path)
        if stage:
            subprocess.run(["git", "-C", str(repo), "add", "--", name], check=True, env=self.env)
        return path

    def test_review_covers_only_the_staged_diff(self):
        self.write("code.py", "staged = True\n")
        self.write("other.py", "unstaged = True\n", stage=False)
        self.write("theirs.py", "other_session = True\n", session="s2", stage=False)
        self.review("--session", "s1")
        prompt = (self.root / "prompt").read_text()
        self.assertIn("+staged = True", prompt)
        self.assertNotIn("unstaged", prompt)
        self.assertNotIn("other_session", prompt)
        self.assertEqual(self.gate(), {})

    def test_approval_survives_unstaged_edits_but_not_index_changes(self):
        p = self.write("code.py", "changed = True\n")
        index_before = self.git("diff", "--cached")
        self.review("--session", "s1")
        self.assertEqual(self.git("diff", "--cached"), index_before)
        self.assertEqual(self.gate(), {})
        # Unstaged edits, this session's or another's, are not part of the commit.
        p.write_text("shell_edit = True\n")
        (self.repo / "theirs.py").write_text("by_other_session = True\n")
        self.assertEqual(self.gate(), {})
        self.git("add", "code.py")
        self.assertTrue(self.denied(self.gate()))
        p.write_text("changed = True\n")
        self.git("add", "code.py")
        self.assertEqual(self.gate(), {})
        self.git("commit", "-qm", "reviewed")
        self.assertEqual(self.gate(), {})

    def test_any_session_may_commit_a_reviewed_staged_tree(self):
        self.write("code.py", "changed = True\n", session="s2")
        self.review("--session", "s2")
        self.assertEqual(self.gate(), {})   # gate() runs as s1

    def test_partial_staging_rejected(self):
        p = self.write("code.py", "reviewed = True\n")
        self.review("--session", "s1")
        p.write_text("intermediate = True\n")
        self.git("add", ".")
        p.write_text("reviewed = True\n")
        self.assertTrue(self.denied(self.gate()))

    def test_narrow_focus_does_not_approve_repository(self):
        self.write("code.py", "changed = True\n")
        self.review("--session", "s1", "--focus", "security")
        self.assertTrue(self.denied(self.gate()))

    def test_resume_sends_delta_and_records_usage(self):
        p = self.write("code.py", "feature = True\n" + "unchanged_context = True\n" * 20 + "bug = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--session", "s1", status=1)
        self.write("code.py", p.read_text().replace("bug = True", "bug = False"))
        response = self.root / "response"
        response.write_text("C1 accepted; corrected bug; regression test passed.")
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.review("--session", "s1", "--resume", "--response-file", str(response))
        prompt = (self.root / "prompt").read_text()
        self.assertIn("+bug = False", prompt)
        self.assertNotIn("+feature = True", prompt)
        self.assertIn("C1 accepted", prompt)
        rows = [json.loads(line) for line in (self.home / ".claude/state/codex-usage.jsonl").read_text().splitlines()]
        self.assertEqual(rows[-1]["round"], 2)
        self.assertTrue(rows[-1]["resumed"])
        self.assertEqual(rows[-1]["verdict"], "APPROVED")

    def codex_args(self):
        return json.loads((self.root / "prompt.codex-args").read_text())

    def revise_rounds(self, count, response_text="C1 refuted: see test."):
        self.write("code.py", "feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        response = self.root / "response"
        response.write_text(response_text)
        for round_number in range(1, count + 1):
            self.env["FAKE_FINDING"] = f"code.py:{round_number} — issue from round {round_number}"
            extra = () if round_number == 1 else ("--resume", "--response-file", str(response))
            result = self.review("--session", "s1", *extra, status=1)
        return result

    def test_round_three_starts_a_new_thread_with_a_findings_summary(self):
        self.revise_rounds(2)
        self.assertIn("resume", self.codex_args(), "round 2 still resumes")
        self.env["FAKE_FINDING"] = "code.py:3 — issue from round 3"
        result = self.review("--session", "s1", "--resume", "--response-file", str(self.root / "response"), status=1)
        self.assertNotIn("resume", self.codex_args())
        prompt = (self.root / "prompt").read_text()
        self.assertIn("+feature = True", prompt, "a new thread needs the full diff")
        self.assertIn("EARLIER ROUNDS", prompt)
        self.assertIn("issue from round 1", prompt)
        self.assertIn("C1 refuted", prompt)
        self.assertIn("new thread with a findings summary", result.stderr)
        rows = [json.loads(line) for line in (self.home / ".claude/state/codex-usage.jsonl").read_text().splitlines()]
        self.assertEqual(rows[-1]["round"], 3)
        self.assertFalse(rows[-1]["resumed"])

    def test_restart_round_zero_keeps_resuming(self):
        self.env["CODEX_REVIEW_RESTART_ROUND"] = "0"
        self.revise_rounds(3)
        self.assertIn("resume", self.codex_args())

    def test_repeated_finding_warns_without_blocking(self):
        self.write("code.py", "feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.env["FAKE_FINDING"] = "code.py:7 — same issue"
        self.review("--session", "s1", status=1)
        result = self.review("--session", "s1", "--resume", status=1)
        self.assertIn("finding repeated at code.py:7", result.stderr)

    def test_live_status_and_events_survive_the_run(self):
        (self.home / ".codex/config.toml").write_text('model = "gpt-test"\nmodel_reasoning_effort = "high"\n[x]\nmodel = "no"\n')
        self.write("code.py", "feature = True\n")
        self.review("--session", "s1")
        live = self.home / ".claude/state/codex-live"
        statuses = sorted(live.glob("*.status.json"))
        self.assertEqual(len(statuses), 1)
        status = json.loads(statuses[0].read_text())
        self.assertEqual((status["state"], status["exit"], status["verdict"], status["round"]), ("done", 0, "APPROVED", 1))
        self.assertIn("thread.started", Path(status["events"]).read_text())
        rows = [json.loads(line) for line in (self.home / ".claude/state/codex-usage.jsonl").read_text().splitlines()]
        self.assertEqual((rows[-1]["effective_model"], rows[-1]["effective_effort"]), ("gpt-test", "high"))
        tail = self.run_cmd(["bash", str(ROOT / "scripts/codex-tail.sh"), "review"], timeout=20)
        self.assertEqual(tail.returncode, 0, tail.stderr)
        self.assertIn("🧵 thread test-thread", tail.stdout)
        self.assertIn("verdict APPROVED", tail.stdout)
        # Events carry diffs and model text: private like the mktemp file they replaced.
        self.assertEqual(live.stat().st_mode & 0o777, 0o700)
        self.assertEqual(Path(status["events"]).stat().st_mode & 0o077, 0)
        self.assertEqual(statuses[0].stat().st_mode & 0o077, 0)

    def test_codex_tail_picks_the_newest_start_not_the_latest_write(self):
        live = self.home / ".claude/state/codex-live"
        live.mkdir(parents=True)
        for name, started in (("review-new-1", "2026-11-22T10:00:00Z"), ("review-old-1", "2026-11-22T09:00:00Z")):
            (live / f"{name}.jsonl").write_text(json.dumps({"type": "thread.started", "thread_id": name}) + "\n")
            (live / f"{name}.status.json").write_text(json.dumps({
                "state": "done", "started_at": started, "thread_key": name, "exit": 0,
                "events": str(live / f"{name}.jsonl")}))
        # The older run finished last, so its status file has the newest mtime.
        tail = self.run_cmd(["bash", str(ROOT / "scripts/codex-tail.sh"), "review"], timeout=20)
        self.assertIn("thread review-new-1", tail.stdout)

    def test_new_work_unit_reviews_only_new_changes(self):
        self.write("first.py", "first = True\n")
        self.review("--session", "s1")
        self.git("commit", "-qm", "first")
        self.write("second.py", "second = True\n")
        self.review("--session", "s1")
        prompt = (self.root / "prompt").read_text()
        self.assertIn("+second = True", prompt)
        self.assertNotIn("+first = True", prompt)

    def test_lock_only_still_calls_reviewer(self):
        self.write("Cargo.lock", "version = 4\n")
        self.review("--session", "s1")
        self.assertIn("Dependency/lock-file changes", (self.root / "prompt").read_text())

    def test_staged_review_needs_no_baseline_and_refuses_an_empty_index(self):
        self.write("code.py", "changed = True\n", stage=False)
        result = self.review("--session", "missing", status=2)
        self.assertIn("Nothing staged", result.stderr)
        self.git("add", "code.py")
        self.review("--session", "missing", "--base", "HEAD", status=2)
        self.review("--session", "missing")
        self.assertEqual(self.gate(), {})

    def gate_cmd(self, command, cwd=None):
        payload = json.dumps({"session_id":"s1", "cwd":str(cwd or self.repo), "tool_input":{"command":command}})
        result = self.run_cmd(["bash", str(ROOT / "hooks/pre-commit-gate.sh")], input=payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def denied(self, out):
        return out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny"

    def published_repo(self, name):
        """A second repository with origin/main, which this session has no baseline for."""
        bare = self.root / f"{name}.git"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True, env=self.env)
        other = self.root / name
        subprocess.run(["git", "clone", "-q", str(bare), str(other)], check=True, env=self.env, capture_output=True)
        for args in (["config", "user.email", "t@example.invalid"], ["config", "user.name", "T"],
                     ["checkout", "-q", "-b", "main"]):
            subprocess.run(["git", "-C", str(other), *args], check=True, env=self.env)
        (other / "app.py").write_text("x = 1\n")
        subprocess.run(["git", "-C", str(other), "add", "."], check=True, env=self.env)
        subprocess.run(["git", "-C", str(other), "commit", "-qm", "init"], check=True, env=self.env)
        subprocess.run(["git", "-C", str(other), "push", "-q", "origin", "main"], check=True, env=self.env,
                       capture_output=True)
        return other

    def test_gate_ignores_commands_that_only_mention_save_sh(self):
        self.write("code.py", "changed = True\n")
        self.assertEqual(self.gate_cmd("grep -n push ~/save.sh | head"), {})
        self.assertEqual(self.gate_cmd("head -40 ~/save.sh"), {})
        self.assertTrue(self.denied(self.gate_cmd('~/save.sh "fix: x"')))
        self.assertTrue(self.denied(self.gate_cmd('env A=1 ~/save.sh "fix: x"')))
        self.assertTrue(self.denied(self.gate_cmd("""bash -c '~/save.sh "fix: x"'""")))

    def test_gate_refuses_staging_in_the_same_command_as_the_commit(self):
        (self.repo / "code.py").write_text("unreviewed = True\n")
        for command in ('git add code.py && ~/save.sh "Fix code"', 'git -C . add -A; ~/save.sh "Fix code"',
                        'git restore --staged code.py && ~/save.sh "Fix code"'):
            self.assertTrue(self.denied(self.gate_cmd(command)), command)
        # A message that merely names the commands is data, not a second command.
        self.assertEqual(self.gate_cmd('~/save.sh "doc: explain git add && git reset"'), {})
        self.assertTrue(self.denied(self.gate_cmd('~/save.sh "doc: x" && git add code.py')))
        self.assertEqual(self.gate_cmd(f'cd "{self.repo}" && ~/save.sh "doc: explain git add"'), {})
        self.assertTrue(self.denied(self.gate_cmd('bash -c "git add code.py" && ~/save.sh "Fix code"')))

    def test_gate_judges_the_cd_target_repository(self):
        other = self.published_repo("other docs")
        self.write("notes.md", "doc only\n", repo=other)
        self.write("code.py", "changed = True\n")
        self.assertEqual(self.gate_cmd(f'cd "{other}" && ~/save.sh "doc: notes"'), {})
        # `;` keeps the cwd repository in play, and it has unreviewed staged code.
        self.assertTrue(self.denied(self.gate_cmd(f'cd "{other}"; ~/save.sh "doc: notes"')))
        self.write("app.py", "x = 2\n", repo=other)
        self.assertTrue(self.denied(self.gate_cmd(f'cd "{other}" && ~/save.sh "fix: x"')))

    def test_gate_judges_staged_content_without_origin_or_baseline(self):
        other = self.root / "local-only"
        other.mkdir()
        for args in (["init", "-q", "-b", "main"], ["config", "user.email", "t@example.invalid"],
                     ["config", "user.name", "T"], ["commit", "-q", "--allow-empty", "-m", "init"]):
            subprocess.run(["git", "-C", str(other), *args], check=True, env=self.env)
        self.write("notes.md", "doc only\n", repo=other)
        self.write("dirty.py", "unstaged = True\n", repo=other, stage=False)
        self.assertEqual(self.gate_cmd(f'cd "{other}" && ~/save.sh "doc: notes"'), {})
        self.write("app.py", "x = 1\n", repo=other)
        self.assertTrue(self.denied(self.gate_cmd(f'cd "{other}" && ~/save.sh "fix: x"')))

    def test_reviewignore_covers_data_but_not_itself_or_protected_paths(self):
        (self.repo / ".reviewignore").write_text("# bot data\nmemory/*.json\n.claude/*\n")
        self.git("add", ".reviewignore")
        self.git("commit", "-qm", "ignore")
        self.write("memory/state.json", "{}\n")
        self.assertEqual(self.gate(), {})
        self.write(".claude/settings.json", "{}\n")
        self.assertTrue(self.denied(self.gate()))
        self.git("rm", "-q", "--cached", ".claude/settings.json")
        self.write(".reviewignore", "*\n")
        self.assertTrue(self.denied(self.gate()))

    def test_documentation_skips_but_single_line_code_does_not(self):
        self.write("README.md", "Documentation\n")
        self.write("code.py", "unstaged = True\n", stage=False)
        self.assertEqual(self.gate(), {})
        self.git("add", "code.py")
        self.assertTrue(self.denied(self.gate()))

    def hook(self, name, **fields):
        payload = {"session_id":"s1", "cwd":str(self.repo), **fields}
        result = self.run_cmd(["bash", str(ROOT / "hooks" / name)], input=json.dumps(payload))
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def log_edit(self, session, path):
        with open(self.home / f".claude/state/dirty-{session}.log", "a") as log:
            log.write(f"{path}\n")

    def test_gate_judges_staged_paths_whoever_wrote_them(self):
        self.write("other.py", "by_other_session = True\n", session="s2", stage=False)
        (self.repo / "bash_edit.py").write_text("unlogged = True\n")
        self.assertEqual(self.gate(), {})
        # Bash edits leave no log, so the staged index is the only thing judged.
        self.git("add", "bash_edit.py")
        self.assertTrue(self.denied(self.gate()))

    def test_session_start_does_not_inject_the_handoff(self):
        self.hook("auto-handoff.sh")
        self.assertTrue((self.home / ".claude/handoffs/latest.md").exists())
        self.assertEqual(self.hook("session-start.sh", source="startup"), {})
        self.assertEqual(self.hook("session-start.sh", source="resume"), {})

    def test_portable_timeout_kills_a_command_that_ignores_term(self):
        self.env["PORTABLE_TIMEOUT_KILL_AFTER"] = "1"
        start = time.monotonic()
        result = self.run_cmd(["bash", "-c", f'. "{ROOT}/hooks/_lib.sh"; '
                               'portable_timeout 1 bash -c "trap \\"\\" TERM; sleep 20"; echo "rc=$?"'])
        self.assertLess(time.monotonic() - start, 10)
        self.assertIn("rc=124", result.stdout)

    def test_codex_ask_does_not_wait_on_a_stdin_that_never_closes(self):
        ask = ["bash", str(ROOT / "scripts/codex-ask.sh"), "Which option?"]
        r, w = os.pipe()   # write end held open: no data, no EOF
        try:
            start = time.monotonic()
            result = subprocess.run(ask, cwd=self.repo, env=self.env, stdin=r, text=True, capture_output=True,
                                    timeout=30)
            self.assertLess(time.monotonic() - start, 15)
        finally:
            os.close(r)
            os.close(w)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Question: Which option?", (self.root / "prompt").read_text())

    def test_codex_ask_drops_a_partial_line_on_timeout(self):
        r, w = os.pipe()
        os.write(w, b"partial-without-newline")
        try:
            result = subprocess.run(["bash", str(ROOT / "scripts/codex-ask.sh"), "Which option?"], cwd=self.repo,
                                    env=self.env, stdin=r, text=True, capture_output=True, timeout=30)
        finally:
            os.close(r)
            os.close(w)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("partial-without-newline", (self.root / "prompt").read_text())

    def test_codex_ask_still_reads_piped_context(self):
        ask = ["bash", str(ROOT / "scripts/codex-ask.sh"), "Which option?"]
        for piped in ("line one\nline two\n", "no trailing newline"):
            result = self.run_cmd(ask, input=piped)
            self.assertEqual(result.returncode, 0, result.stderr)
            prompt = (self.root / "prompt").read_text()
            for line in piped.strip().splitlines():
                self.assertIn(line, prompt)

    def verify_gate(self, command, session):
        transcript = self.root / f"{session}.jsonl"
        transcript.write_text(json.dumps({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "t", "name": "Bash", "input": {"command": command}}]}}) + "\n")
        (self.home / f".claude/state/dirty-{session}.log").write_text("/r/a.py\n/r/b.py\n")
        return self.hook("verification-gate.sh", session_id=session, transcript_path=str(transcript))

    def test_verify_gate_counts_python_test_runners_behind_timeout(self):
        for i, command in enumerate(("cd ~/x && timeout 400 python3 -m unittest __tests__.test_review",
                                     "timeout -k 5 60 python -m pytest -q", "python3 -m pytest")):
            self.assertEqual(self.verify_gate(command, f"v{i}"), {}, command)
        self.assertEqual(self.verify_gate("python3 -m http.server", "v9")["decision"], "block")

    def test_verify_gate_counts_package_manager_runners_browsers_and_test_scripts(self):
        commands = ("yarn vitest run src", "pnpm exec playwright test", "bunx vitest", "yarn dlx jest",
                    "tabd navigate http://localhost:3000", "flutter test", "swift test",
                    "xcodebuild -scheme App test", "bash scripts/e2e-native.sh", "./scripts/test.sh")
        for i, command in enumerate(commands):
            self.assertEqual(self.verify_gate(command, f"r{i}"), {}, command)
        for i, command in enumerate(("tabd daemon start", "cat vitest.config.ts", "bash scripts/build.sh")):
            self.assertEqual(self.verify_gate(command, f"n{i}")["decision"], "block", command)

    def test_verify_gate_ignores_scratchpad_notes_and_speaks_to_the_user(self):
        transcript = self.root / "scratch.jsonl"
        transcript.write_text("")
        scratch = "/tmp/claude-1000/-home-u/0a1b/scratchpad"
        (self.home / ".claude/state/dirty-sc.log").write_text(f"{scratch}/a.md\n{scratch}/b.md\n")
        self.assertEqual(self.hook("verification-gate.sh", session_id="sc", transcript_path=str(transcript)), {})
        block = self.verify_gate("ls", "lang")
        self.assertIn("language of their last message", block["reason"])

    def test_round_guard_cannot_reset_by_omitting_resume(self):
        self.write("code.py", "feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        for _ in range(10):
            self.review("--session", "s1", status=1)
        result = self.review("--session", "s1", status=2)
        self.assertIn("10 rounds exhausted", result.stderr)

    def test_round_guard_is_configurable(self):
        self.write("code.py", "feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.env["CODEX_REVIEW_MAX_ROUNDS"] = "2"
        for _ in range(2):
            self.review("--session", "s1", status=1)
        result = self.review("--session", "s1", status=2)
        self.assertIn("2 rounds exhausted", result.stderr)

    def test_concurrent_index_change_cannot_publish_approval(self):
        self.write("code.py", "feature = True\n")
        # A working-tree edit during review (any session's) does not touch the commit.
        self.env["FAKE_MUTATE"] = "1"
        self.review("--session", "s1")
        self.assertEqual(self.gate(), {})
        self.write("more.py", "more = True\n")
        self.env["FAKE_MUTATE"] = "stage"
        self.review("--session", "s1", status=2)
        self.assertTrue(self.denied(self.gate()))

    def test_failed_cli_records_unknown_usage(self):
        self.write("code.py", "feature = True\n")
        self.env["FAKE_FAIL"] = "1"
        self.review("--session", "s1", status=2)
        rows = [json.loads(line) for line in (self.home / ".claude/state/codex-usage.jsonl").read_text().splitlines()]
        self.assertFalse(rows[-1]["usage_reported"])
        self.assertNotEqual(rows[-1]["status"], 0)

    def test_resume_missing_thread_sends_full_diff(self):
        self.write("code.py", "feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--session", "s1", status=1)
        for path in (self.home / ".claude/state/codex-threads").iterdir():
            path.unlink()
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.review("--session", "s1", "--resume")
        self.assertIn("+feature = True", (self.root / "prompt").read_text())

    def test_legacy_marker_does_not_approve(self):
        self.write("code.py", "feature = True\n")
        self.shell('touch "$HOME/.claude/state/reviewed-$(repo_hash "$PWD")"')
        self.assertTrue(self.denied(self.gate()))
        self.shell('touch "$(review_marker_path "$PWD" "$(review_index_tree "$PWD")")"')
        self.assertTrue(self.denied(self.gate()))

    def test_forced_ignored_addition_is_in_snapshot(self):
        (self.repo / ".gitignore").write_text("ignored.py\n")
        (self.repo / "ignored.py").write_text("forced = True\n")
        self.git("add", "-f", "ignored.py")
        self.review("--session", "s1")
        self.assertIn("+forced = True", (self.root / "prompt").read_text())

    def test_intent_lookup_uses_shared_repo_hash(self):
        intent = self.root / "intent.md"
        intent.write_text("---\ngoal: Implement feature\nacceptance_criteria:\n  - feature enabled\nout_of_scope:\n  - unrelated changes\n---\n")
        self.shell(f'printf "%s\\n" "{intent}" > "$HOME/.claude/state/intent-active-s1-$(repo_hash "$PWD").path"')
        path = self.shell('REPO_HASH=$(repo_hash "$(git rev-parse --show-toplevel)"); cat "$HOME/.claude/state/intent-active-s1-${REPO_HASH}.path"')
        self.assertEqual(path, str(intent))
        self.write("code.py", "feature = True\n")
        self.review("--session", "s1", "--intent-file", path)
        self.assertIn("Goal: Implement feature", (self.root / "prompt").read_text())

    def test_requirements_file_is_not_treated_as_documentation(self):
        self.write("requirements.txt", "dependency==1.0\n")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_unborn_repository(self):
        unborn = self.root / "unborn"
        unborn.mkdir()
        self.repo = unborn
        self.git("init", "-q", "-b", "main")
        self.write("new.py", "new = True\n")
        self.review("--session", "s1")
        self.assertIn("+new = True", (self.root / "prompt").read_text())

    def test_relative_files_from_subdirectory(self):
        nested = self.repo / "nested"
        nested.mkdir()
        (nested / "code.py").write_text("nested = True\n")
        result = subprocess.run(["bash", str(ROOT / "scripts/codex-review.sh"), "--files", "code.py"],
                                cwd=nested, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("+nested = True", (self.root / "prompt").read_text())
        self.git("add", "nested")
        self.assertTrue(self.denied(self.gate()))

    def test_claude_review_uses_read_only_tools_and_provider_bound_approval(self):
        self.write("code.py", "changed = True\n")
        self.review("--reviewer", "claude", "--session", "s1")
        args = json.loads((self.root / "prompt.claude-args").read_text())
        self.assertEqual(args[args.index("--tools") + 1], "Read,Glob,Grep")
        for flag in ("--safe-mode", "--restricted", "--strict-mcp-config", "--disable-slash-commands"):
            self.assertIn(flag, args)
        self.env["HARNESS_REQUIRED_REVIEWER"] = "claude"
        self.assertEqual(self.gate(), {})
        self.env["HARNESS_REQUIRED_REVIEWER"] = "codex"
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_codex_approval_cannot_satisfy_codex_authored_work(self):
        self.write("code.py", "changed = True\n")
        self.review("--session", "s1")
        self.env["HARNESS_REQUIRED_REVIEWER"] = "claude"
        self.assertTrue(self.denied(self.gate()))
        # The other reviewer joins the same staged tree's approval; no --base dance.
        self.review("--reviewer", "claude", "--session", "s1")
        self.assertIn("+changed = True", (self.root / "prompt").read_text())
        self.assertEqual(self.gate(), {})

    def test_claude_resume_is_separate_from_codex_and_sends_delta(self):
        self.write("code.py", "feature = True\nbug = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--session", "s1", status=1)
        self.review("--reviewer", "claude", "--session", "s1", "--resume", status=1)
        args = json.loads((self.root / "prompt.claude-args").read_text())
        self.assertNotIn("--resume", args)
        self.write("code.py", "feature = True\nbug = False\n")
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.review("--reviewer", "claude", "--session", "s1", "--resume")
        args = json.loads((self.root / "prompt.claude-args").read_text())
        self.assertEqual(args[args.index("--resume") + 1], "11111111-2222-3333-4444-555555555555")
        self.assertIn("+bug = False", (self.root / "prompt").read_text())
        self.assertNotIn("+feature = True", (self.root / "prompt").read_text())
        ledger = self.home / ".claude/state/claude-review-usage.jsonl"
        usage = json.loads(ledger.read_text().splitlines()[-1])
        self.assertEqual(usage["provider"], "claude")
        self.assertEqual(usage["round"], 2)
        self.assertTrue(usage["resumed"])

    def test_claude_failure_and_error_result_do_not_approve(self):
        self.write("code.py", "changed = True\n")
        for flag in ("FAKE_FAIL", "FAKE_CLAUDE_RESULT_ERROR"):
            self.env[flag] = "1"
            self.review("--reviewer", "claude", "--session", "s1", status=2)
            self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))
            self.assertFalse((self.home / ".claude/state/codex-usage.jsonl").exists())
            del self.env[flag]

    def test_claude_missing_resume_rebuilds_full_prompt(self):
        self.write("code.py", "changed = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--reviewer", "claude", "--session", "s1", status=1)
        self.env["FAKE_NO_CLAUDE_SESSION"] = "1"
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.review("--reviewer", "claude", "--session", "s1", "--resume")
        self.assertIn("--- DIFF ---", (self.root / "prompt").read_text())

    def test_claude_timeout_does_not_approve(self):
        self.write("code.py", "changed = True\n")
        self.env.update(FAKE_SLEEP="1", CLAUDE_REVIEW_TIMEOUT="1")
        self.review("--reviewer", "claude", "--session", "s1", status=2)
        self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))

    def test_claude_round_cap_and_concurrent_mutation(self):
        self.write("code.py", "changed = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.env["CODEX_REVIEW_MAX_ROUNDS"] = "3"
        for _ in range(3):
            self.review("--reviewer", "claude", "--session", "s1", status=1)
        self.review("--reviewer", "claude", "--session", "s1", status=2)
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.env["FAKE_MUTATE"] = "stage"
        self.review("--reviewer", "claude", "--session", "s2", status=2)
        self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))

    def test_codex_delegation_requires_claude_even_with_claude_parent(self):
        self.write("code.py", "claude_before = True\ndelegated = True\n")
        self.shell('touch "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$PWD")"')
        self.review("--reviewer", "claude", "--session", "s1")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")
        self.review("--reviewer", "codex", "--session", "s1")
        self.assertIn("+claude_before = True", (self.root / "prompt").read_text())
        self.assertIn("+delegated = True", (self.root / "prompt").read_text())
        self.assertEqual(self.gate(), {})

    def test_delegate_start_during_review_blocks_publication(self):
        self.write("code.py", "changed = True\n")
        self.env["FAKE_DELEGATE_START"] = "1"
        self.review("--reviewer", "codex", "--session", "s1", status=2)
        self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))
        self.assertTrue(list((self.home / ".claude/state").glob("codex-delegate-pending-*")))

    def test_mixed_approval_requires_both_reviewers_on_identical_content(self):
        self.write("code.py", "mixed = True\n")
        self.shell('touch "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$PWD")"')
        self.review("--reviewer", "claude", "--session", "s1")
        self.write("code.py", "mixed = False\n")
        self.review("--reviewer", "codex", "--session", "s1")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")
        self.review("--reviewer", "claude", "--session", "s1")
        self.assertEqual(self.gate(), {})

    def test_background_delegate_blocks_reviews_until_completion(self):
        self.write("code.py", "claude_before = True\n")
        self.env["FAKE_CODEX_SLEEP"] = "1"
        result = self.run_cmd(["bash", str(ROOT / "scripts/codex-delegate.sh"), "--background", "Inspect task"])
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.home / ".claude/state"
        self.assertTrue(list(state.glob("codex-delegate-active-*")))
        self.review("--reviewer", "claude", "--session", "s1", status=2)
        deadline = time.monotonic() + 5
        while list(state.glob("codex-delegate-active-*")) and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertFalse(list(state.glob("codex-delegate-active-*")))
        self.assertTrue(list(state.glob("codex-delegate-pending-*")))
        self.review("--reviewer", "codex", "--session", "s1")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")
        self.review("--reviewer", "claude", "--session", "s1")
        self.assertEqual(self.gate(), {})
        self.assertFalse(list((self.home / ".claude/state").glob("codex-delegate-pending-*")))
        self.git("add", ".")
        self.git("commit", "-qm", "delegated")
        self.assertEqual(self.gate(), {})
        self.write("code.py", "claude_followup = True\n")
        self.assertTrue(self.denied(self.gate()))
        self.review("--reviewer", "codex", "--session", "s1")
        self.assertIn("+claude_followup = True", (self.root / "prompt").read_text())
        self.assertNotIn("+claude_before = True", (self.root / "prompt").read_text())
        self.assertEqual(self.gate(), {})

    def test_background_delegate_launch_timeout_reaps_job_and_releases_lock(self):
        (self.repo / "code.py").write_text("claude_before = True\n")
        self.env["CODEX_DELEGATE_START_TIMEOUT"] = "1"
        self.env["CODEX_DELEGATE_TEST_START_DELAY"] = "3"
        result = self.run_cmd(["bash", str(ROOT / "scripts/codex-delegate.sh"), "--background", "Inspect task"])
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("failed to start", result.stderr)
        state = self.home / ".claude/state"
        self.assertFalse(list(state.glob("codex-delegate-active-*")))
        time.sleep(3)
        # The stalled job was reaped: it never confirmed, never ran codex, never touched the repo.
        meta = next(state.glob("codex-jobs/*/*.meta")).read_text()
        self.assertNotIn("started=1", meta)
        self.assertIn("exit_status=launch_failed", meta)
        self.assertEqual((self.repo / "code.py").read_text(), "claude_before = True\n")

    def test_background_delegate_records_own_process_group(self):
        self.env["FAKE_CODEX_SLEEP"] = "1"
        result = self.run_cmd(["bash", str(ROOT / "scripts/codex-delegate.sh"), "--background", "Inspect task"])
        self.assertEqual(result.returncode, 0, result.stderr)
        meta_path = next((self.home / ".claude/state").glob("codex-jobs/*/*.meta"))
        # The job outlives this call (fake codex sleeps 1 s). Let it finish before the temp dir is
        # removed: under load it was still writing and rmtree failed with "Directory not empty".
        # Cleanups run last-in-first-out, so this runs before setUp's temp-dir cleanup.
        def wait_for_job():
            deadline = time.monotonic() + 30
            while "exit_status=" not in meta_path.read_text() and time.monotonic() < deadline:
                time.sleep(0.1)
        self.addCleanup(wait_for_job)
        fields = dict(line.split("=", 1) for line in meta_path.read_text().splitlines() if "=" in line)
        self.assertEqual(fields["pgid"], fields["pid"])
        self.assertNotEqual(fields["pgid"], str(os.getpgid(0)))

    def policy(self, hook, command):
        payload = json.dumps({"session_id": "s1", "cwd": str(self.repo), "tool_input": {"command": command}})
        result = self.run_cmd(["bash", str(ROOT / "hooks" / hook)], input=payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.denied(json.loads(result.stdout))

    def test_commit_policy_denies_any_co_author_or_attribution(self):
        trailer = "Co-Authored-By"
        for message in (f"Fix x\n\n{trailer}: Jane <j@example.invalid>",
                        f"Fix x\n\n{trailer.lower()}: Claude <noreply@anthropic.com>",
                        "Fix x\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)"):
            self.assertTrue(self.policy("commit-policy-gate.sh", f'~/save.sh "{message}"'), message)
            self.assertTrue(self.policy("commit-policy-gate.sh", f'git commit -m "{message}"'), message)
        self.assertTrue(self.policy("commit-policy-gate.sh", f'git commit --trailer "{trailer}=Bot"'))
        self.assertTrue(self.policy("commit-policy-gate.sh", f'git commit -m fix -m "{trailer}: X <x@y>"'))
        # Text that only mentions the convention mid-line (docs, a heredoc writing them) is not a trailer.
        self.assertFalse(self.policy("commit-policy-gate.sh", f'~/save.sh "doc: block `{trailer}:` trailers"'))
        self.assertFalse(self.policy("commit-policy-gate.sh", '~/save.sh "Add y"'))
        self.assertFalse(self.policy("commit-policy-gate.sh", f"grep -n {trailer}: ~/save.sh"))

    def test_commit_policy_guards_github_side_merge_messages(self):
        trailer = "Co-Authored-By"
        gate = "commit-policy-gate.sh"
        # GitHub's default squash message appends co-author trailers, so a body is required.
        self.assertTrue(self.policy(gate, "gh pr merge 7 --squash --delete-branch 2>&1 | tail -2"))
        self.assertTrue(self.policy(gate, "cd x && gh pr merge 7 -sd"))
        self.assertTrue(self.policy(gate, "gh pr merge --merge"))
        self.assertFalse(self.policy(gate, 'gh pr merge 7 --squash -d --body ""'))
        self.assertFalse(self.policy(gate, "gh pr merge 7 -sdb 'Summary of the change'"))
        self.assertFalse(self.policy(gate, "gh pr merge 7 --rebase"))
        self.assertTrue(self.policy(gate, f'gh pr merge 7 --squash --body "Fix x\n\n{trailer}: Jane <j@x>"'))
        body = self.repo / "body.md"
        body.write_text("Summary\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n")
        self.assertTrue(self.policy(gate, "gh pr merge 7 --squash --body-file body.md"))
        self.assertTrue(self.policy(gate, "gh pr create --title t -F body.md"))
        self.assertTrue(self.policy(gate, f'gh pr create --title t --body "x\n\n{trailer}: Bot <b@x>"'))
        self.assertFalse(self.policy(gate, 'gh pr create --title t --body "Adds y"'))
        # Direct API merges follow the same rule.
        self.assertTrue(self.policy(gate, "gh api -X PUT repos/o/r/pulls/7/merge -f merge_method=squash"))
        self.assertFalse(self.policy(gate, "gh api -X PUT repos/o/r/pulls/7/merge -f merge_method=squash -f commit_message=Summary"))
        self.assertFalse(self.policy(gate, "gh api -X PUT repos/o/r/pulls/7/merge -f merge_method=rebase"))
        # Review round 1: separate lines, leading global flags, unreadable files, `@file` fields.
        self.assertTrue(self.policy(gate, "gh pr merge 7 --squash\necho --body clean"))
        self.assertFalse(self.policy(gate, "gh pr merge 7 \\\n  --squash --body 'Summary'"))
        self.assertTrue(self.policy(gate, "gh -R o/r pr merge 7 --squash"))
        self.assertTrue(self.policy(gate, "printf x | gh pr merge 7 --squash --body-file -"))
        (self.repo / "sub").mkdir()
        (self.repo / "sub/body.md").write_text(f"x\n\n{trailer}: Bot <b@x>\n")
        self.assertTrue(self.policy(gate, "cd sub && gh pr merge 7 --squash -F body.md"))
        self.assertTrue(self.policy(gate, "gh pr merge 7 --squash -F missing.md"))
        self.assertTrue(self.policy(gate, "gh api -X PUT repos/o/r/pulls/7/merge -F commit_message=@sub/body.md"))
        # Review round 2: quoted empty/operator args, joined continuations, subshell `cd`.
        self.assertTrue(self.policy(gate, f'gh pr merge 7 --squash --body "" --subject "{trailer}: Bot <b@x>"'))
        self.assertTrue(self.policy(gate, f'gh pr merge 7 --squash --body ";" --subject "{trailer}: Bot <b@x>"'))
        self.assertTrue(self.policy(gate, "gh pr mer\\\nge 7 --squash"))
        (self.repo / "clean.md").write_text("Summary\n")
        (self.repo / "sub/clean.md").write_text("Summary\n")
        self.assertTrue(self.policy(gate, "(cd sub); gh pr merge 7 --squash -F body.md"))
        self.assertTrue(self.policy(gate, "cd sub | gh pr merge 7 --squash -F body.md"))
        self.assertFalse(self.policy(gate, "(cd sub && gh pr merge 7 --squash -F clean.md)"))
        # Review round 3: ANSI-C quoting expands escapes before GitHub sees the text.
        self.assertTrue(self.policy(gate, f"gh pr merge 7 --squash --body $'Summary\\n\\n{trailer}: Bot <b@x>'"))
        self.assertFalse(self.policy(gate, "gh pr merge 7 --squash --body $'Summary\\nmore'"))
        # Review round 4: bash's variable-width escapes; undecodable gh text fails closed.
        self.assertTrue(self.policy(gate, f"gh pr merge 7 --squash --body $'Summary\\xA\\n{trailer}: Bot <b@x>'"))
        self.assertTrue(self.policy(gate, f"gh pr merge 7 --squash --body $'Summary\\012{trailer}: Bot <b@x>'"))
        self.assertTrue(self.policy(gate, "gh pr merge 7 --squash --body $'x\\U7FFFFFFF'"))
        self.assertTrue(self.policy(gate, "gh pr merge 7 --squash --body 'unterminated"))
        self.assertFalse(self.policy(gate, "echo 'unterminated"))
        # Reading PRs is not a merge.
        self.assertFalse(self.policy(gate, "gh pr view 7 --json body"))
        self.assertFalse(self.policy(gate, "gh pr list"))

    def test_raw_git_commit_is_denied_in_the_hook_output_format(self):
        self.assertTrue(self.policy("block-raw-git.sh", "cd /tmp && git commit -m x"))
        self.assertFalse(self.policy("block-raw-git.sh", '~/save.sh "Fix git commit wording"'))
        # The bash fast path (no save.sh, no git…commit → skip python) must still see split forms.
        self.assertTrue(self.policy("block-raw-git.sh", "git \\\n  commit -m x"))
        self.assertTrue(self.policy("block-raw-git.sh", "echo start\ngit -C /tmp commit -m x"))
        # The shared parser: reads that only mention a raw commit are not blocked.
        self.assertFalse(self.policy("block-raw-git.sh", 'grep -rn "git commit" hooks/ | head'))
        self.assertFalse(self.policy("block-raw-git.sh", "rg -n 'git commit -m' hooks/ | head -3"))
        self.assertTrue(self.policy("block-raw-git.sh", "git -c user.name=x commit -m y"))
        self.assertTrue(self.policy("block-raw-git.sh", 'bash -c "git commit -m x"'))
        self.assertTrue(self.policy("block-raw-git.sh", "python3 -c \"import os; os.system('git commit -m x')\""))


if __name__ == "__main__":
    unittest.main()
