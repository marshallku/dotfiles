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
if os.environ.get("FAKE_FAIL"):
    print("simulated CLI failure", file=sys.stderr)
    sys.exit(1)
if os.environ.get("FAKE_MUTATE"):
    pathlib.Path("code.py").write_text("changed_during_review = True\\n")
    if os.environ["FAKE_MUTATE"] == "stage":
        import subprocess; subprocess.run(["git", "add", "code.py"], check=True)
verdict = os.environ.get("FAKE_VERDICT", "APPROVED")
pathlib.Path(args[args.index("-o") + 1]).write_text("## Summary\\nDone.\\nVERDICT: " + verdict + "\\n")
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
        self.shell('review_init_baseline "$PWD" s1')

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

    def test_stop_rearms_for_new_work_unit_and_avoids_recursion(self):
        self.write("code.py", "first = True\n", stage=False)
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        self.assertEqual(self.hook("auto-cross-review.sh", stop_hook_active=True), {})
        self.git("add", "code.py")
        self.review("--session", "s1")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})
        self.write("code.py", "second = True\n", stage=False)
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")

    def test_stop_reminds_once_per_snapshot_and_respects_cooldown(self):
        self.write("code.py", "first = True\n", stage=False)
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        # Waiting on subagents: the same snapshot never re-blocks.
        self.assertEqual(self.hook("auto-cross-review.sh"), {})
        # New changes inside the cooldown are not re-blocked either; commit stays the hard gate.
        self.write("code.py", "second = True\n")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})
        self.assertTrue(self.denied(self.gate()))
        # Past the cooldown, a new snapshot is reminded again.
        self.env["AUTO_REVIEW_STOP_COOLDOWN"] = "0"
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})

    def test_stop_reminder_right_after_an_approval_still_deduplicates(self):
        self.write("code.py", "first = True\n")
        self.review("--session", "s1")
        self.write("code.py", "second = True\n", stage=False)
        # Same second as the approval: the reminder must still count as made after it.
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})

    def log_edit(self, session, path):
        with open(self.home / f".claude/state/dirty-{session}.log", "a") as log:
            log.write(f"{path}\n")

    def test_changes_uncommitted_before_session_start_are_not_its_work(self):
        (self.repo / "code.py").write_text("dirty_before_start = True\n")
        self.shell('rm "$(review_state_path "$PWD" s1)"')
        self.hook("session-start.sh", source="startup")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})
        self.assertEqual(self.gate(), {})
        self.write("code.py", "session_edit = True\n", stage=False)
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")

    def test_reminders_ignore_files_only_another_session_edited(self):
        other = self.write("other.py", "by_other_session = True\n", session="s2", stage=False)
        (self.repo / "bash_edit.py").write_text("unlogged = True\n")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})
        self.assertEqual(self.hook("remind-cross-review.sh"), {})
        self.assertEqual(self.gate(), {})
        # Commit stays strict on what is staged, whoever wrote it: Bash edits leave no log.
        self.git("add", "other.py")
        self.assertTrue(self.denied(self.gate()))
        # A file both sessions edited is this session's work too.
        self.log_edit("s1", other)
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")

    def test_reminders_follow_the_repository_the_session_edited(self):
        other = self.published_repo("other")
        (self.repo / "code.py").write_text("by_other_session = True\n")
        self.log_edit("s2", self.repo / "code.py")
        (other / "untouched.py").write_text("dirty_but_not_ours = True\n")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})
        (other / "app.py").write_text("x = 2\n")
        self.log_edit("s1", other / "app.py")
        out = self.hook("auto-cross-review.sh")
        self.assertEqual(out["decision"], "block")
        self.assertIn(f"in {other.resolve()}", out["reason"])
        self.assertIn(str(other.resolve()), self.hook("remind-cross-review.sh")
                      ["hookSpecificOutput"]["additionalContext"])

    def test_a_repository_already_reminded_does_not_hide_the_next(self):
        other = self.published_repo("other")
        self.write("code.py", "first = True\n", stage=False)
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        self.assertIn("hookSpecificOutput", self.hook("remind-cross-review.sh"))
        (other / "app.py").write_text("x = 2\n")
        self.log_edit("s1", other / "app.py")
        self.assertIn(str(other.resolve()), self.hook("auto-cross-review.sh")["reason"])
        self.assertIn(str(other.resolve()), self.hook("remind-cross-review.sh")
                      ["hookSpecificOutput"]["additionalContext"])

    def test_portable_realpath_resolves_symlinks_and_missing_tails(self):
        link = self.root / "link"
        link.symlink_to(self.repo)
        (self.repo / "target.py").write_text("t = 1\n")
        (self.root / "file-link.py").symlink_to(self.repo / "target.py")
        real = str(self.repo.resolve())
        self.assertEqual(self.shell(f'_review_realpath "{link}/gone/new.py"'), f"{real}/gone/new.py")
        self.assertEqual(self.shell(f'_review_realpath "{self.root}/file-link.py"'), f"{real}/target.py")

    def test_stop_suppression_grace_ignores_a_reminder_from_this_stop(self):
        self.write("code.py", "first = True\n", stage=False)
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        fresh = self.run_cmd(["bash", "-c", f'. "{ROOT}/hooks/_lib.sh"; '
                              'review_stop_suppressed "$PWD" s1 "$(review_session_fingerprint "$PWD" s1)" 10'])
        self.assertNotEqual(fresh.returncode, 0)
        aged = self.run_cmd(["bash", "-c", f'. "{ROOT}/hooks/_lib.sh"; '
                             'review_stop_suppressed "$PWD" s1 "$(review_session_fingerprint "$PWD" s1)" 0'])
        self.assertEqual(aged.returncode, 0)

    def test_session_start_injects_only_its_own_repositorys_handoff(self):
        other = self.published_repo("other")
        self.hook("auto-handoff.sh")
        start = {"source": "resume", "session_id": "s2"}
        own = self.hook("session-start.sh", **start)
        self.assertIn(f"**Directory:** {self.repo}", own["hookSpecificOutput"]["additionalContext"])
        # latest.md now describes self.repo; a session in another repository must not receive it.
        self.assertEqual(self.hook("session-start.sh", cwd=str(other), **start), {})
        # A hand-written narrative in latest.md for this repository still wins when it is newer.
        time.sleep(1.1)
        (self.home / ".claude/handoffs/latest.md").write_text(f"# Narrative\n\n- **Directory:** {self.repo}\n")
        own = self.hook("session-start.sh", **start)
        self.assertIn("# Narrative", own["hookSpecificOutput"]["additionalContext"])

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

    def test_reminder_deduplicates_snapshot(self):
        self.write("code.py", "first = True\n", stage=False)
        self.assertIn("hookSpecificOutput", self.hook("remind-cross-review.sh"))
        self.assertEqual(self.hook("remind-cross-review.sh"), {})
        # Another session editing the same repository must not re-arm this session's reminder.
        self.write("theirs.py", "by_other_session = True\n", session="s2", stage=False)
        self.assertEqual(self.hook("remind-cross-review.sh"), {})
        self.write("code.py", "second = True\n", stage=False)
        self.assertIn("hookSpecificOutput", self.hook("remind-cross-review.sh"))

    def test_three_round_cap_cannot_reset_by_omitting_resume(self):
        self.write("code.py", "feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        for _ in range(3):
            self.review("--session", "s1", status=1)
        result = self.review("--session", "s1", status=2)
        self.assertIn("3 rounds exhausted", result.stderr)

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

    def test_gate_needs_no_session_baseline(self):
        self.shell('rm "$(review_state_path "$PWD" s1)"')
        self.assertEqual(self.gate(), {})
        self.write("code.py", "changed = True\n")
        self.assertTrue(self.denied(self.gate()))

    def test_unborn_repository(self):
        unborn = self.root / "unborn"
        unborn.mkdir()
        self.repo = unborn
        self.git("init", "-q", "-b", "main")
        self.shell('review_init_baseline "$PWD" s1')
        self.write("new.py", "new = True\n")
        self.review("--session", "s1")
        self.assertIn("+new = True", (self.root / "prompt").read_text())

    def test_session_start_does_not_reset_baseline_on_resume(self):
        before = self.shell('cat "$(review_state_path "$PWD" s1)"')
        (self.repo / "code.py").write_text("committed = True\n")
        self.git("commit", "-qam", "feature")
        self.hook("session-start.sh", source="resume")
        self.assertEqual(self.shell('cat "$(review_state_path "$PWD" s1)"'), before)

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

    def test_legacy_resume_does_not_invent_baseline(self):
        self.shell('rm "$(review_state_path "$PWD" s1)"')
        self.hook("session-start.sh", source="resume")
        self.assertNotEqual(self.run_cmd(["bash", "-c", f'. "{ROOT}/hooks/_lib.sh"; '
                                          'test -e "$(review_state_path "$PWD" s1)"']).returncode, 0)

    def test_stop_does_not_review_while_waiting_for_clarification(self):
        self.write("code.py", "in_progress = True\n", stage=False)
        self.assertEqual(self.hook("auto-cross-review.sh", last_assistant_message="Which behavior do you want?"), {})

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


if __name__ == "__main__":
    unittest.main()
