"""cctx.py: find sessions by what the owner typed, across Claude Code and Codex transcripts."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "cctx.py"


def write_jsonl(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r) + "\n" for r in records))


def claude_user(text, entrypoint="cli", sidechain=False):
    return {"type": "user", "cwd": "/w/app", "timestamp": "2026-11-22T01:00:00Z", "entrypoint": entrypoint,
            "isSidechain": sidechain, "message": {"role": "user", "content": text}}


class CctxTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        write_jsonl(self.home / ".claude/projects/-w-app/aaaa1111-0000-0000-0000-000000000001.jsonl", [
            claude_user("LP-1369 라이브 배포 확인해줘"),
            claude_user([{"type": "tool_result", "content": "LP-1369 in output"}]),
            claude_user([{"type": "tool_result", "content": "LP-1369 tool"}, {"type": "text", "text": "also LP-1369 typed"}]),
            claude_user("<system-reminder>LP-1369</system-reminder>"),
            claude_user("Base directory for this skill: /x\nLP-1369"),
            claude_user("sidechain LP-1369", sidechain=True),
        ])
        write_jsonl(self.home / ".claude/projects/-w-app/bbbb2222-0000-0000-0000-000000000002.jsonl", [
            claude_user("review LP-1369 diff", entrypoint="sdk-cli")])
        rollout = "rollout-2026-11-22T01-00-00-cccc3333-0000-0000-0000-000000000003.jsonl"
        write_jsonl(self.home / ".codex/sessions/2026/11/22" / rollout, [
            {"type": "session_meta", "payload": {"id": "cccc3333-0000-0000-0000-000000000003", "cwd": "/w/api",
                                                 "source": "cli", "originator": "codex_cli_rs"}},
            {"type": "response_item", "payload": {"role": "user", "content": [
                {"type": "input_text", "text": "# AGENTS.md instructions\nLP-1369"}]}},
            {"type": "response_item", "payload": {"role": "user", "content": [
                {"type": "input_text", "text": "fix the LP-1369 regression in api"}]}},
            {"type": "response_item", "payload": {"role": "user", "content": [
                {"type": "output_text", "text": "not typed LP-1369"}]}},
            {"type": "response_item", "turn_id": "external-import-turn-1", "payload": {"role": "user", "content": [
                {"type": "input_text", "text": "imported copy LP-1369"}]}},
        ])
        self.env = {**os.environ, "HOME": str(self.home)}

    def cctx(self, *args):
        result = subprocess.run(["python3", "-I", str(SCRIPT), *args], text=True, capture_output=True, env=self.env)
        return result

    def test_find_matches_only_typed_prompts_and_gives_the_resume_command(self):
        result = self.cctx("find", "lp-1369", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = {h["id"][:4]: h for h in json.loads(result.stdout)}
        self.assertEqual(sorted(hits), ["aaaa", "cccc"], "program-started session is left out")
        self.assertEqual(hits["aaaa"]["matches"], ["LP-1369 라이브 배포 확인해줘", "also LP-1369 typed"])
        self.assertEqual(hits["cccc"]["matches"], ["fix the LP-1369 regression in api"])
        self.assertEqual(hits["cccc"]["resume"], "codex resume cccc3333-0000-0000-0000-000000000003")
        self.assertTrue(hits["aaaa"]["resume"].startswith("claude --resume aaaa1111"))

    def test_all_includes_program_started_sessions(self):
        ids = [h["id"][:4] for h in json.loads(self.cctx("find", "LP-1369", "--all", "--json").stdout)]
        self.assertIn("bbbb", ids)

    def test_sessions_and_prompts(self):
        rows = json.loads(self.cctx("sessions", "--json").stdout)
        self.assertEqual({r["tool"] for r in rows}, {"claude", "codex"})
        self.assertEqual(self.cctx("sessions", "--cwd", "/w/api", "--json").stdout.count('"id"'), 1)
        prompts = json.loads(self.cctx("prompts", "aaaa", "--json").stdout)["all"]
        self.assertEqual([p["text"] for p in prompts], ["LP-1369 라이브 배포 확인해줘", "also LP-1369 typed"])
        self.assertEqual(self.cctx("prompts", "zzzz").returncode, 1)

    def test_goal_activation_keeps_only_the_typed_goal(self):
        goal = ('A session-scoped Stop hook is now active with condition: "ship LP-77 today". '
                'Briefly acknowledge the goal, then immediately start working.')
        write_jsonl(self.home / ".claude/projects/-w-app/dddd4444-0000-0000-0000-000000000004.jsonl",
                    [claude_user(goal), claude_user("A session-scoped Stop hook is now active, malformed")])
        prompts = json.loads(self.cctx("prompts", "dddd", "--json").stdout)["all"]
        self.assertEqual([p["text"] for p in prompts], ["ship LP-77 today"])
        self.assertEqual(self.cctx("find", "Briefly acknowledge").returncode, 1, "harness prose is not a prompt")

    def test_prompts_opens_an_old_session(self):
        old = self.home / ".claude/projects/-w-app/eeee5555-0000-0000-0000-000000000005.jsonl"
        write_jsonl(old, [claude_user("ancient work")])
        stamp = old.stat().st_mtime - 800 * 86400
        os.utime(old, (stamp, stamp))
        self.assertEqual(self.cctx("prompts", "eeee").returncode, 0)

    def test_find_shows_a_late_match_and_counts_the_rest(self):
        long_prompt = "x " * 200 + "the NEEDLE is here"
        write_jsonl(self.home / ".claude/projects/-w-app/ffff6666-0000-0000-0000-000000000006.jsonl",
                    [claude_user(f"{long_prompt} {i}") for i in range(5)])
        out = self.cctx("find", "needle").stdout
        self.assertIn("NEEDLE is here", out)
        self.assertEqual(out.count("NEEDLE is here"), 5, "every matching prompt is shown")

    def test_nothing_found_exits_one(self):
        self.assertEqual(self.cctx("find", "no-such-thing").returncode, 1)


if __name__ == "__main__":
    unittest.main()
