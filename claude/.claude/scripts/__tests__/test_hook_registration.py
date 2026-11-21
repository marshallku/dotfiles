"""Hook registration contract, the transcript-based plan gate, handoff dedupe and the
settings trip wire.

See scripts/hook-contract.py for why the event contract exists (track-bash-edit post sat
under UserPromptSubmit on the work Mac for a week).
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


CLAUDE = Path(__file__).resolve().parents[2]
HOOKS = CLAUDE / "hooks"
SETTINGS = CLAUDE / "settings.json"

spec = importlib.util.spec_from_file_location("hook_contract", CLAUDE / "scripts/hook-contract.py")
hook_contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook_contract)


def command(script):
    return {"type": "command", "command": f"bash $HOME/.claude/hooks/{script}"}


class HookContractTests(unittest.TestCase):
    def test_dotfiles_settings_match_every_header(self):
        settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        self.assertEqual(hook_contract.violations(settings, HOOKS), [])

    def test_hook_under_the_wrong_event_is_reported(self):
        settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        for block in settings["hooks"]["PostToolUse"]:
            block["hooks"] = [h for h in block["hooks"] if "track-bash-edit" not in h["command"]]
        settings["hooks"]["UserPromptSubmit"][0]["hooks"].append(command("track-bash-edit.sh post"))
        problems = hook_contract.violations(settings, HOOKS)
        self.assertTrue(any("registered under UserPromptSubmit" in p for p in problems), problems)
        self.assertTrue(any("never registers it there" in p for p in problems), problems)

    def test_hook_without_annotation_is_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            (Path(temp) / "x.sh").write_text("#!/usr/bin/env bash\necho '{}'\n")
            settings = {"hooks": {"Stop": [{"hooks": [command("x.sh")]}]}}
            self.assertEqual(len(hook_contract.violations(settings, Path(temp))), 1)


class HookRunTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(HOOKS)
        (self.home / "docs/scripts").mkdir(parents=True)
        dn = self.home / "docs/scripts/dn"
        dn.write_text("#!/bin/sh\n")
        dn.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home)}

    def run_hook(self, name, payload):
        result = subprocess.run(["bash", str(self.home / ".claude/hooks" / name)],
                                input=json.dumps({"session_id": "s", **payload}),
                                text=True, capture_output=True, env=self.env, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout or "{}")

    def transcript(self, *commands):
        path = self.root / "t.jsonl"
        with path.open("w") as stream:
            for cmd in commands:
                stream.write(json.dumps({"type": "assistant", "message": {"content": [
                    {"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
        return str(path)

    def plan_decision(self, transcript):
        output = self.run_hook("plan-ssot-gate.sh", {"tool_input": {}, "transcript_path": transcript})
        return output.get("hookSpecificOutput", {}).get("permissionDecision", "allow")

    def test_plan_gate_reads_the_transcript(self):
        self.assertEqual(self.plan_decision(self.transcript("ls", "git status")), "deny")
        self.assertEqual(self.plan_decision(self.transcript("ls", "cd ~/docs && dn search 'hook event'")), "allow")
        self.assertEqual(self.plan_decision(self.transcript("echo dn searching")), "deny")

    def test_plan_gate_allows_an_early_consult_in_a_long_transcript(self):
        # grep -q exiting early broke jq's pipe; under pipefail that denied a valid consult.
        commands = ["dn search early"] + [f"echo {'x' * 2000} {i}" for i in range(400)]
        self.assertEqual(self.plan_decision(self.transcript(*commands)), "allow")

    def test_auto_handoff_skips_unchanged_content(self):
        repo = self.root / "repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        self.run_hook("auto-handoff.sh", {"cwd": str(repo)})
        latest = self.home / ".claude/handoffs/latest.md"
        first = latest.stat().st_mtime_ns
        os.utime(latest, ns=(first - 10**9, first - 10**9))
        self.run_hook("auto-handoff.sh", {"cwd": str(repo)})
        self.assertEqual(latest.stat().st_mtime_ns, first - 10**9, "unchanged handoff was rewritten")
        (repo / "f.txt").write_text("x")
        subprocess.run(["git", "-C", str(repo), "add", "f.txt"], check=True)
        self.run_hook("auto-handoff.sh", {"cwd": str(repo)})
        self.assertIn("f.txt", latest.read_text())


class SettingsTripwireTests(unittest.TestCase):
    """Uncommitted settings changes trip; a key reorder (Claude Code rewrites the file) does not."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(os.path.realpath(self.temp.name))
        self.src = root / "src"
        shutil.copytree(HOOKS, self.src / "hooks", ignore=shutil.ignore_patterns("__pycache__"))
        (self.src / "scripts").mkdir()
        for name in ("harness-report.sh", "hook-contract.py"):
            shutil.copy(CLAUDE / "scripts" / name, self.src / "scripts" / name)
        self.settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        self.write(self.settings)
        git = ["git", "-C", str(self.src), "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run([*git[:3], "init", "-q"], check=True)
        subprocess.run([*git, "add", "."], check=True)
        subprocess.run([*git, "commit", "-qm", "init"], check=True)
        self.home = root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(self.src / "hooks")
        (self.home / ".claude/settings.json").symlink_to(self.src / "settings.json")
        self.env = {**os.environ, "HOME": str(self.home)}

    def write(self, settings):
        (self.src / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")

    def tripwire(self):
        result = subprocess.run(["bash", str(self.src / "scripts/harness-report.sh"), "--tripwire"],
                                text=True, capture_output=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_reorder_is_quiet_and_real_change_trips(self):
        self.assertNotIn("uncommitted", self.tripwire())
        reordered = dict(reversed(list(self.settings.items())))
        self.write(reordered)
        self.assertNotIn("uncommitted", self.tripwire())
        self.write({**self.settings, "effortLevel": "low"})
        self.assertIn("uncommitted", self.tripwire())


if __name__ == "__main__":
    unittest.main()
