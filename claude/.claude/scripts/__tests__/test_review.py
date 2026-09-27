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

    def test_mixed_committed_and_uncommitted_changes(self):
        p = self.repo / "code.py"
        p.write_text("initial = True\ncommitted = True\n")
        self.git("commit", "-qam", "feature")
        p.write_text(p.read_text() + "uncommitted = True\n")
        self.review("--session", "s1")
        prompt = (self.root / "prompt").read_text()
        self.assertIn("+committed = True", prompt)
        self.assertIn("+uncommitted = True", prompt)

    def test_approval_reused_after_staging_and_commit_but_not_shell_edit(self):
        p = self.repo / "code.py"
        p.write_text("changed = True\n")
        index_before = self.git("diff", "--cached")
        self.review("--session", "s1")
        self.assertEqual(self.git("diff", "--cached"), index_before)
        self.git("add", ".")
        self.assertEqual(self.gate(), {})
        self.git("commit", "-qm", "reviewed")
        self.assertEqual(self.gate(), {})
        p.write_text("shell_edit = True\n")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_partial_staging_rejected(self):
        p = self.repo / "code.py"
        p.write_text("reviewed = True\n")
        self.review("--session", "s1")
        p.write_text("intermediate = True\n")
        self.git("add", ".")
        p.write_text("reviewed = True\n")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_narrow_focus_does_not_approve_repository(self):
        (self.repo / "code.py").write_text("changed = True\n")
        self.review("--session", "s1", "--focus", "security")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_resume_sends_delta_and_records_usage(self):
        p = self.repo / "code.py"
        p.write_text("feature = True\n" + "unchanged_context = True\n" * 20 + "bug = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--session", "s1", status=1)
        p.write_text(p.read_text().replace("bug = True", "bug = False"))
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
        (self.repo / "first.py").write_text("first = True\n")
        self.review("--session", "s1")
        (self.repo / "second.py").write_text("second = True\n")
        self.review("--session", "s1")
        prompt = (self.root / "prompt").read_text()
        self.assertIn("+second = True", prompt)
        self.assertNotIn("+first = True", prompt)

    def test_lock_only_still_calls_reviewer(self):
        (self.repo / "Cargo.lock").write_text("version = 4\n")
        self.review("--session", "s1")
        self.assertIn("Dependency/lock-file changes", (self.root / "prompt").read_text())

    def test_missing_baseline_requires_explicit_base(self):
        (self.repo / "code.py").write_text("changed = True\n")
        self.review("--session", "missing", status=2)
        self.review("--session", "missing", "--base", "HEAD")

    def test_documentation_skips_but_single_line_code_does_not(self):
        (self.repo / "README.md").write_text("Documentation\n")
        self.assertEqual(self.gate(), {})
        (self.repo / "code.py").write_text("initial = False\n")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def hook(self, name, **fields):
        payload = {"session_id":"s1", "cwd":str(self.repo), **fields}
        result = self.run_cmd(["bash", str(ROOT / "hooks" / name)], input=json.dumps(payload))
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_stop_rearms_for_new_work_unit_and_avoids_recursion(self):
        p = self.repo / "code.py"
        p.write_text("first = True\n")
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        self.assertEqual(self.hook("auto-cross-review.sh", stop_hook_active=True), {})
        self.review("--session", "s1")
        self.assertEqual(self.hook("auto-cross-review.sh"), {})
        p.write_text("second = True\n")
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")

    def test_reminder_deduplicates_snapshot(self):
        p = self.repo / "code.py"
        p.write_text("first = True\n")
        self.assertIn("hookSpecificOutput", self.hook("remind-cross-review.sh"))
        self.assertEqual(self.hook("remind-cross-review.sh"), {})
        p.write_text("second = True\n")
        self.assertIn("hookSpecificOutput", self.hook("remind-cross-review.sh"))

    def test_three_round_cap_cannot_reset_by_omitting_resume(self):
        (self.repo / "code.py").write_text("feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        for _ in range(3):
            self.review("--session", "s1", status=1)
        result = self.review("--session", "s1", status=2)
        self.assertIn("Three rounds exhausted", result.stderr)

    def test_concurrent_change_cannot_publish_approval(self):
        (self.repo / "code.py").write_text("feature = True\n")
        self.env["FAKE_MUTATE"] = "1"
        self.review("--session", "s1", status=2)
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_failed_cli_records_unknown_usage(self):
        (self.repo / "code.py").write_text("feature = True\n")
        self.env["FAKE_FAIL"] = "1"
        self.review("--session", "s1", status=2)
        rows = [json.loads(line) for line in (self.home / ".claude/state/codex-usage.jsonl").read_text().splitlines()]
        self.assertFalse(rows[-1]["usage_reported"])
        self.assertNotEqual(rows[-1]["status"], 0)

    def test_resume_missing_thread_sends_full_diff(self):
        (self.repo / "code.py").write_text("feature = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--session", "s1", status=1)
        for path in (self.home / ".claude/state/codex-threads").iterdir():
            path.unlink()
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.review("--session", "s1", "--resume")
        self.assertIn("+feature = True", (self.root / "prompt").read_text())

    def test_legacy_marker_does_not_approve(self):
        (self.repo / "code.py").write_text("feature = True\n")
        self.shell('touch "$HOME/.claude/state/reviewed-$(repo_hash "$PWD")"')
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

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
        (self.repo / "code.py").write_text("feature = True\n")
        self.review("--session", "s1", "--intent-file", path)
        self.assertIn("Goal: Implement feature", (self.root / "prompt").read_text())

    def test_requirements_file_is_not_treated_as_documentation(self):
        (self.repo / "requirements.txt").write_text("dependency==1.0\n")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_clean_legacy_session_requires_explicit_baseline(self):
        self.shell('rm "$(review_state_path "$PWD" s1)"')
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_unborn_repository(self):
        unborn = self.root / "unborn"
        unborn.mkdir()
        self.repo = unborn
        self.git("init", "-q", "-b", "main")
        self.shell('review_init_baseline "$PWD" s1')
        (self.repo / "new.py").write_text("new = True\n")
        self.review("--session", "s1")
        self.assertIn("+new = True", (self.root / "prompt").read_text())

    def test_session_start_does_not_reset_baseline_on_resume(self):
        (self.repo / "code.py").write_text("committed = True\n")
        self.git("commit", "-qam", "feature")
        self.hook("session-start.sh", source="resume")
        self.review("--session", "s1")
        self.assertIn("+committed = True", (self.root / "prompt").read_text())

    def test_relative_files_from_subdirectory(self):
        nested = self.repo / "nested"
        nested.mkdir()
        (nested / "code.py").write_text("nested = True\n")
        result = subprocess.run(["bash", str(ROOT / "scripts/codex-review.sh"), "--files", "code.py"],
                                cwd=nested, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("+nested = True", (self.root / "prompt").read_text())
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_legacy_resume_does_not_invent_baseline(self):
        self.shell('rm "$(review_state_path "$PWD" s1)"')
        self.hook("session-start.sh", source="resume")
        self.review("--session", "s1", status=2)

    def test_stop_does_not_review_while_waiting_for_clarification(self):
        (self.repo / "code.py").write_text("in_progress = True\n")
        self.assertEqual(self.hook("auto-cross-review.sh", last_assistant_message="Which behavior do you want?"), {})

    def test_claude_review_uses_read_only_tools_and_provider_bound_approval(self):
        (self.repo / "code.py").write_text("changed = True\n")
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
        (self.repo / "code.py").write_text("changed = True\n")
        self.review("--session", "s1")
        self.env["HARNESS_REQUIRED_REVIEWER"] = "claude"
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertEqual(self.hook("auto-cross-review.sh")["decision"], "block")
        self.review("--reviewer", "claude", "--session", "s1", status=2)
        self.review("--reviewer", "claude", "--session", "s1", "--base", "HEAD")
        self.assertIn("+changed = True", (self.root / "prompt").read_text())
        self.assertEqual(self.gate(), {})

    def test_claude_resume_is_separate_from_codex_and_sends_delta(self):
        code = self.repo / "code.py"
        code.write_text("feature = True\nbug = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--session", "s1", status=1)
        self.review("--reviewer", "claude", "--session", "s1", "--resume", status=1)
        args = json.loads((self.root / "prompt.claude-args").read_text())
        self.assertNotIn("--resume", args)
        code.write_text("feature = True\nbug = False\n")
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
        (self.repo / "code.py").write_text("changed = True\n")
        for flag in ("FAKE_FAIL", "FAKE_CLAUDE_RESULT_ERROR"):
            self.env[flag] = "1"
            self.review("--reviewer", "claude", "--session", "s1", status=2)
            self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))
            self.assertFalse((self.home / ".claude/state/codex-usage.jsonl").exists())
            del self.env[flag]

    def test_claude_missing_resume_rebuilds_full_prompt(self):
        (self.repo / "code.py").write_text("changed = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        self.review("--reviewer", "claude", "--session", "s1", status=1)
        self.env["FAKE_NO_CLAUDE_SESSION"] = "1"
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.review("--reviewer", "claude", "--session", "s1", "--resume")
        self.assertIn("--- DIFF ---", (self.root / "prompt").read_text())

    def test_claude_timeout_does_not_approve(self):
        (self.repo / "code.py").write_text("changed = True\n")
        self.env.update(FAKE_SLEEP="1", CLAUDE_REVIEW_TIMEOUT="1")
        self.review("--reviewer", "claude", "--session", "s1", status=2)
        self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))

    def test_claude_round_cap_and_concurrent_mutation(self):
        (self.repo / "code.py").write_text("changed = True\n")
        self.env["FAKE_VERDICT"] = "REVISE"
        for _ in range(3):
            self.review("--reviewer", "claude", "--session", "s1", status=1)
        self.review("--reviewer", "claude", "--session", "s1", status=2)
        self.env["FAKE_VERDICT"] = "APPROVED"
        self.env["FAKE_MUTATE"] = "1"
        self.review("--reviewer", "claude", "--session", "s2", "--base", "HEAD", status=2)
        self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))

    def test_codex_delegation_requires_claude_even_with_claude_parent(self):
        (self.repo / "code.py").write_text("claude_before = True\ndelegated = True\n")
        self.shell('touch "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$PWD")"')
        self.review("--reviewer", "claude", "--session", "s1")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")
        self.review("--reviewer", "codex", "--session", "s1")
        self.assertIn("+claude_before = True", (self.root / "prompt").read_text())
        self.assertIn("+delegated = True", (self.root / "prompt").read_text())
        self.assertEqual(self.gate(), {})

    def test_delegate_start_during_review_blocks_publication(self):
        (self.repo / "code.py").write_text("changed = True\n")
        self.env["FAKE_DELEGATE_START"] = "1"
        self.review("--reviewer", "codex", "--session", "s1", status=2)
        self.assertFalse(list((self.home / ".claude/state").glob("reviewed-*")))
        self.assertTrue(list((self.home / ".claude/state").glob("codex-delegate-pending-*")))

    def test_mixed_approval_requires_both_reviewers_on_identical_content(self):
        code = self.repo / "code.py"
        code.write_text("mixed = True\n")
        self.shell('touch "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$PWD")"')
        self.review("--reviewer", "claude", "--session", "s1")
        code.write_text("mixed = False\n")
        self.review("--reviewer", "codex", "--session", "s1")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")
        self.review("--reviewer", "claude", "--session", "s1")
        self.assertEqual(self.gate(), {})

    def test_background_delegate_blocks_reviews_until_completion(self):
        (self.repo / "code.py").write_text("claude_before = True\n")
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
        (self.repo / "code.py").write_text("claude_followup = True\n")
        self.assertEqual(self.gate()["hookSpecificOutput"]["permissionDecision"], "deny")
        self.review("--reviewer", "codex", "--session", "s1")
        self.assertIn("+claude_followup = True", (self.root / "prompt").read_text())
        self.assertNotIn("+claude_before = True", (self.root / "prompt").read_text())
        self.assertEqual(self.gate(), {})


if __name__ == "__main__":
    unittest.main()
