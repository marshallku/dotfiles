"""Exercise real shared hooks in an isolated HOME and real Git repository."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HARNESS = Path(__file__).resolve().parents[1]
CLAUDE = HARNESS.parents[1]


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(CLAUDE / "hooks")
        # Avoid optional desktop integrations in real shared hooks.
        (self.home / "bin").mkdir()
        coctl = self.home / "bin/coctl"
        coctl.write_text("#!/bin/sh\nexit 0\n")
        coctl.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home),
                    "PATH": f"{self.home / 'bin'}:{os.environ['PATH']}"}
        self.env.pop("HARNESS_READ_ONLY_CHILD", None)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        (self.repo / "code.py").write_text("before = True\n")
        self.git("add", ".")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "initial")

    def git(self, *args):
        result = subprocess.run(["git", *args], cwd=self.repo, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def hook(self, event, **fields):
        payload = {"session_id": "test-session", "cwd": str(self.repo), "hook_event_name": event, **fields}
        result = subprocess.run(["python3", str(HARNESS / "bridge.py")], input=json.dumps(payload),
                                cwd=self.repo, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def patch(self, patch, event="PreToolUse"):
        return self.hook(event, tool_name="apply_patch", tool_input={"command": patch})

    def test_multi_file_patch_protects_move_destination_and_delete(self):
        for operation in ("*** Delete File: .env", "*** Update File: code.py\n*** Move to: .ssh/key"):
            result = self.patch(f"*** Begin Patch\n*** Add File: ok.py\n+ok\n{operation}\n*** End Patch")
            self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_freeze_checks_relative_paths_and_symlinks(self):
        (self.home / ".claude/freeze-dir.txt").write_text(str(self.repo))
        (self.repo / "outside").symlink_to(self.home, target_is_directory=True)
        for path in ("../outside.py", "outside/file.py", "outside/../file.py"):
            result = self.patch(f"*** Begin Patch\n*** Add File: {path}\n+text\n*** End Patch")
            self.assertIn("freeze", result["hookSpecificOutput"]["permissionDecisionReason"])

    def test_sensitive_symlink_name_is_not_lost(self):
        (self.repo / ".env").symlink_to(self.repo / "code.py")
        result = self.patch("*** Begin Patch\n*** Update File: .env\n@@\n-x\n+y\n*** End Patch")
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_legacy_ask_is_denied_instead_of_ignored(self):
        result = self.hook("PreToolUse", tool_name="Bash", tool_input={"command": "git reset --hard"})
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn("cannot implement", result["hookSpecificOutput"]["permissionDecisionReason"])

    def test_baseline_review_gate_and_child_recursion(self):
        start = self.hook("SessionStart", source="startup")
        self.assertIn("test-session", start["hookSpecificOutput"]["additionalContext"])
        (self.repo / "code.py").write_text("after = True\n")
        result = self.hook("Stop", stop_hook_active=False)
        self.assertEqual(result["decision"], "block")
        self.assertIn("cross-review", result["reason"])
        commit = self.hook("PreToolUse", tool_name="Bash", tool_input={"command": "~/save.sh 'Fix test'"})
        self.assertEqual(commit["hookSpecificOutput"]["permissionDecision"], "deny")
        handoff = self.home / ".claude/handoffs/latest.md"
        handoff.write_text("parent handoff")
        self.env["HARNESS_READ_ONLY_CHILD"] = "1"
        self.assertEqual(self.hook("Stop", stop_hook_active=False), {})
        self.assertEqual(self.hook("SessionStart", source="startup"), {})
        self.assertEqual(handoff.read_text(), "parent handoff")
        result = self.hook("PreToolUse", tool_name="Bash", tool_input={"command": "rm -rf /"})
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_command_evidence_prevents_false_verification_reminder(self):
        self.hook("SessionStart", source="startup")
        self.patch("*** Begin Patch\n*** Add File: one.py\n+x\n*** Add File: two.py\n+x\n*** End Patch",
                   event="PostToolUse")
        dirty = self.home / ".claude/state/dirty-test-session.log"
        self.assertEqual(len(dirty.read_text().splitlines()), 2)
        self.hook("PostToolUse", tool_name="Bash", tool_input={"command": "pytest tests"})
        result = self.hook("Stop", stop_hook_active=False)
        self.assertNotIn("verify-gate", result.get("reason", ""))
        self.assertFalse((self.home / ".claude/state/verify-blocked-test-session").exists())

    def test_plan_requires_recall_then_accepts_it(self):
        dn = self.home / "docs/scripts/dn"
        dn.parent.mkdir(parents=True)
        dn.write_text("#!/bin/sh\nexit 0\n")
        dn.chmod(0o755)
        result = self.hook("PreToolUse", tool_name="update_plan", tool_input={})
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")
        self.hook("PostToolUse", tool_name="Bash", tool_input={"command": "dn search harness"})
        self.assertEqual(self.hook("PreToolUse", tool_name="update_plan", tool_input={}), {})

    def test_installer_is_idempotent_and_preserves_conflicts(self):
        command = ["python3", str(HARNESS / "install.py")]
        for _ in range(2):
            result = subprocess.run(command, env=self.env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        skill = self.home / ".agents/skills/iterate"
        self.assertEqual(skill.resolve(), CLAUDE / "skills/iterate")
        skill.unlink()
        skill.mkdir()
        (skill / "SKILL.md").write_text("local version")
        result = subprocess.run(command, env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((skill / "SKILL.md").read_text(), "local version")


if __name__ == "__main__":
    unittest.main()
