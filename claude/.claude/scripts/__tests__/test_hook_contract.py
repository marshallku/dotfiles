"""Every PreToolUse decision must use the shape Claude Code honours, from the deployed layout.

careful-with-judge, protect-secrets, freeze and plan-ssot-gate printed a top-level
{permissionDecision} that Claude Code ignores, so they blocked nothing (rm -rf / included)
until 2026-11-14. Their own logs said "deny", which is why nobody noticed. These tests run
each hook through ~/.claude/hooks the way Claude Code does and check what it would obey.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


HOOKS = Path(__file__).resolve().parents[2] / "hooks"


class HookContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(HOOKS)
        self.env = {**os.environ, "HOME": str(self.home)}

    def run_hook(self, name, payload, hooks=None):
        hooks = hooks or self.home / ".claude/hooks"
        result = subprocess.run(["bash", str(hooks / name)], input=json.dumps({"session_id": "s", **payload}),
                                text=True, capture_output=True, env=self.env, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout or "{}")

    def decision(self, output):
        self.assertNotIn("permissionDecision", output, "top-level permissionDecision is ignored by Claude Code")
        specific = output.get("hookSpecificOutput", {})
        if "permissionDecision" in specific:
            self.assertEqual(specific["hookEventName"], "PreToolUse")
            self.assertTrue(specific.get("permissionDecisionReason"))
        return specific.get("permissionDecision", "allow")

    def bash(self, command, cwd=None, name="careful-with-judge.sh"):
        payload = {"tool_input": {"command": command}, "cwd": str(cwd or self.root)}
        return self.decision(self.run_hook(name, payload))

    def test_no_hook_prints_the_ignored_top_level_shape(self):
        legacy = re.compile(r"""\{\s*\\?["']?permissionDecision\b""")
        for path in HOOKS.glob("*.sh"):
            code = "\n".join(line for line in path.read_text().splitlines() if not line.lstrip().startswith("#"))
            self.assertIsNone(legacy.search(code), f"{path.name} emits a top-level permissionDecision")

    def flagged_rules(self):
        ledger = self.home / ".claude/state/hook-events.jsonl"
        events = [json.loads(line) for line in ledger.read_text().splitlines()] if ledger.exists() else []
        return [e["rule"] for e in events if e.get("decision") == "flagged"]

    def test_careful_denies_irreversible_and_flags_the_rest_without_stopping(self):
        project = "/opt/proj"  # outside every temp root; the hook only reads the payload cwd
        self.assertEqual(self.bash("rm -rf /"), "deny")
        self.assertEqual(self.bash('rm -rf "$HOME"'), "deny")
        self.assertEqual(self.bash("bash -c 'rm -rf ~/*'"), "deny")
        self.assertEqual(self.bash("rm -rf .", cwd=project), "deny")
        self.assertEqual(self.bash("git push --force origin main"), "deny")  # --force-with-lease exists
        # Unclear but recoverable: let the autonomous loop run, keep a record for review.
        for command in ("rm -rf /opt/proj", "ls | xargs rm -rf", "find /opt/proj -delete",
                        "psql -c 'DROP DATABASE t'", "git reset --hard HEAD~1"):
            self.assertEqual(self.bash(command), "allow", command)
        self.assertEqual(self.flagged_rules(), ["rm recursive"] * 3 + ["sql destructive", "git discard"])

    def test_force_push_is_judged_on_the_command_not_on_text(self):
        for command in ("git push -f origin main", "git -C repo push --force", "git push origin +main",
                        "cd x && git push --force-with-lease --force", "bash -c 'git push -fu origin x'",
                        "git push origin +main --force-if-includes"):  # if-includes alone is no lease
            self.assertEqual(self.bash(command), "deny", command)
        for command in ("git push --force-with-lease origin main", "git push origin main",
                        "claude -p 'run git push --force origin main and report'",
                        "git commit -m 'Explain why git push --force is denied'",
                        "cat <<'EOF'\ngit push --force\nEOF"):
            self.assertEqual(self.bash(command), "allow", command)

    def test_no_hook_ever_asks(self):
        # `ask` waits for a human and stalls long autonomous loops; hooks deny or allow.
        for path in HOOKS.glob("*.sh"):
            self.assertNotRegex(path.read_text(), r"hook_permission\s+\"?ask", path.name)

    def test_careful_allows_scratch_and_artifacts(self):
        for command in ("S=/tmp/claude-1/x/scratchpad; rm -rf $S/repo", 'D=$(mktemp -d); rm -rf "$D"',
                        "rm -rf node_modules dist", "cd /tmp/work && rm -rf .", "git rm -r old",
                        "python3 - <<'EOF'\nos.system('rm -rf /')\nEOF", 'echo "rm -rf /"',
                        "git push --force-with-lease"):
            self.assertEqual(self.bash(command), "allow", command)

    def test_careful_denies_deletes_when_its_classifier_is_missing(self):
        hooks = self.root / "hooks"
        shutil.copytree(HOOKS, hooks, ignore=shutil.ignore_patterns("_rm_policy.py", "__pycache__"))
        output = self.run_hook("careful-with-judge.sh", {"tool_input": {"command": "rm -rf /tmp/x"}, "cwd": "/"},
                               hooks=hooks)
        self.assertEqual(self.decision(output), "deny")
        self.assertIn("_rm_policy.py", output["hookSpecificOutput"]["permissionDecisionReason"])

    def test_protect_secrets_denies_secrets_but_not_templates(self):
        edit = lambda path: self.decision(self.run_hook("protect-secrets.sh", {"tool_input": {"file_path": path}}))
        self.assertEqual(edit("/repo/.env"), "deny")
        self.assertEqual(edit("/repo/.env.local"), "deny")
        self.assertEqual(edit("/home/u/.ssh/config"), "deny")
        self.assertEqual(edit("/repo/.env.example"), "allow")
        self.assertEqual(edit("/repo/app.ts"), "allow")

    def test_freeze_denies_edits_outside_the_frozen_directory(self):
        (self.home / ".claude/freeze-dir.txt").write_text("/work/allowed")
        edit = lambda path: self.decision(self.run_hook("freeze.sh", {"tool_input": {"file_path": path}}))
        self.assertEqual(edit("/work/other/x.py"), "deny")
        self.assertEqual(edit("/work/allowed/x.py"), "allow")

    def test_plan_gate_denies_until_the_ssot_was_consulted(self):
        dn = self.home / "docs/scripts/dn"
        dn.parent.mkdir(parents=True)
        dn.write_text("#!/bin/sh\nexit 0\n")
        dn.chmod(0o755)
        self.assertEqual(self.decision(self.run_hook("plan-ssot-gate.sh", {"tool_input": {}})), "deny")

    def test_gh_merge_policy_fails_closed_without_its_checker(self):
        merge = {"tool_input": {"command": "gh pr merge 12 --squash"}, "cwd": str(self.root)}
        self.assertEqual(self.decision(self.run_hook("commit-policy-gate.sh", merge)), "deny")
        hooks = self.root / "hooks"
        shutil.copytree(HOOKS, hooks, ignore=shutil.ignore_patterns("_gh_merge_policy.py", "__pycache__"))
        self.assertEqual(self.decision(self.run_hook("commit-policy-gate.sh", merge, hooks=hooks)), "deny")
        view = {"tool_input": {"command": "gh pr view 12"}, "cwd": str(self.root)}
        self.assertEqual(self.decision(self.run_hook("commit-policy-gate.sh", view, hooks=hooks)), "allow")


class RmPolicyTests(unittest.TestCase):
    """The classifier alone: operands are resolved the way the shell would."""

    HOME = "/home/u"

    def verdict(self, command, cwd="/home/u/dev/x"):
        result = subprocess.run(["python3", str(HOOKS / "_rm_policy.py"), cwd, self.HOME], input=command,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.split()[0]

    def test_table(self):
        cases = {
            "rm -rf /": "deny", "rm -rf -- /": "deny", "\\rm -rf /": "deny", "rm -rf /*": "deny",
            "rm -rf ~": "deny", "rm -rf ~/*": "deny", "rm -rf ~/.*": "deny", "rm -rf /usr": "deny",
            "rm -rf *": "deny", "sudo rm -rf /etc": "deny",
            "ssh host 'rm -rf ~'": "deny", "ssh host 'bash -s' <<'EOF'\nrm -rf ~\nEOF": "deny",
            "rm -rf ~/dev/proj": "ask", "rm -rf /tmp": "ask", "R=$S/x; rm -rf $R": "ask",
            "find ~ -name x -delete": "ask", "ssh host 'rm -rf ~/dev/trig'": "ask",
            "trap 'rm -rf \"$BASE\"' EXIT": "ask",
            "S=/tmp/a; rm -rf \"${S:?}/x\"": "allow", "rm -rf /tmp/cmc.*": "allow",
            "BASE=$(mktemp -d /tmp/t.XXXX); trap 'rm -rf \"$BASE\"' EXIT": "allow",
            "rm -r \"$TMPDIR\"/dbg*": "allow", "ssh host 'rm -rf ~/dev/a/target'": "allow",
            "find /tmp/x -name '*.o' -delete": "allow", "rm -rf ~/aide-*.log": "allow",
            "rm -f file": "none", "echo 'x; rm -rf /'": "none", "git rm -rq dir": "none",
        }
        for command, expected in cases.items():
            self.assertEqual(self.verdict(command), expected, command)

    def test_review_bypasses_stay_closed(self):
        cases = {
            "S=/tmp/s; rm -rf ${S:+/home/u}": "ask",          # ${:+} substitutes an unchecked word
            'bash -lc "rm -rf /home/u"': "deny",              # combined shell options
            "( cd /tmp/s ) ; rm -rf .": "deny",               # a subshell cd does not leak
            "false && cd /tmp/s; rm -rf .": "deny",           # a skipped cd leaves the old cwd possible
            "cd /tmp/s; rm -rf foo": "ask",                   # cd may fail before `;`
            'D=$(mktemp -d); rm -rf "$D/../.."': "deny",      # traversal out of the temp dir
            'D=$(mktemp -d ~/x.XXX); rm -rf "$D"': "ask",     # template outside temp roots
            'S=/tmp/home/u; rm -rf "${S#/tmp}"': "ask",       # value-changing parameter operation
            'bash -o pipefail -c "rm -rf /home/u"': "deny",   # options that take an argument
            "false && cd /tmp/s && true; rm -rf .": "deny",   # a skipped && chain keeps the old cwd
            'D=$(mktemp -d x.XXXXXX); rm -rf "$D"': "ask",    # bare template lands in the cwd
            'D=$(mktemp -dt x.XXXX); rm -rf "$D"': "allow",   # -t places it in TMPDIR
            'S=; rm -rf "${S:-/home/u}"': "ask",              # `:-` uses the fallback for empty
            'D=$(mktemp -d -p /home/u); rm -rf "$D/../.ssh"': "ask",  # -p directory is honoured
            'D=$(mktemp -d -p /tmp); rm -rf "$D"': "allow",
        }
        for command, expected in cases.items():
            self.assertEqual(self.verdict(command, cwd="/opt/proj"), expected, command)

    def test_relative_operands_follow_cd(self):
        self.assertEqual(self.verdict("cd /tmp/w && rm -rf build out"), "allow")
        self.assertEqual(self.verdict("cd /tmp/w && cd ~/dev && rm -rf out"), "ask")
        self.assertEqual(self.verdict("rm -rf out", cwd=""), "ask")


if __name__ == "__main__":
    unittest.main()
