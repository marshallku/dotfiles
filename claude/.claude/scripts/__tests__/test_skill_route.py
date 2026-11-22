"""skill-route.sh: a short natural-language lifecycle prompt names the skill it stands for.

On the work Mac "PR 올려줘" reached the ship-pr skill 17 of 40 times; the rest improvised the
steps and skipped the skill's evidence step.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOKS = Path(__file__).resolve().parents[2] / "hooks"


class SkillRouteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(HOOKS)
        for skill in ("ship-pr", "ticket"):
            (self.home / f".claude/skills/{skill}").mkdir(parents=True)
            (self.home / f".claude/skills/{skill}/SKILL.md").write_text("---\nname: x\n---\n")
        (self.home / ".claude/skill-routes").write_text(
            "# private routes\n"
            "(^|[[:space:]])PR[[:space:]]*(올려|만들어)\tship-pr\n"
            "티켓[[:space:]]*(따|만들)\tticket\n"
            "정리해\tcleanup\n")
        self.env = {**os.environ, "HOME": str(self.home)}

    def route(self, prompt):
        result = subprocess.run(["bash", str(self.home / ".claude/hooks/skill-route.sh")],
                                input=json.dumps({"session_id": "s", "prompt": prompt, "cwd": str(self.root)}),
                                text=True, capture_output=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        context = json.loads(result.stdout or "{}").get("hookSpecificOutput", {}).get("additionalContext", "")
        return context

    def test_short_prompts_name_their_skill(self):
        self.assertIn("`ship-pr`", self.route("PR 올려줘"))
        self.assertIn("`ship-pr`", self.route("  pr 만들어 "))
        self.assertIn("`ticket`", self.route("티켓 따고 시작하자"))

    def test_long_prompts_slash_commands_and_unknown_skills_are_left_alone(self):
        self.assertEqual(self.route("어제 만든 컴포넌트 리팩터링하고 테스트 붙인 다음에 PR 올려줘, 스크린샷도"), "")
        self.assertEqual(self.route("/ship-pr"), "")
        self.assertEqual(self.route("정리해"), "", "cleanup is not installed here")
        self.assertEqual(self.route("오늘 날씨 어때"), "")

    def test_plugin_cache_and_path_names_do_not_count_as_installed(self):
        cached = self.home / ".claude/plugins/cache/other/skills/cleanup"
        cached.mkdir(parents=True)
        (cached / "SKILL.md").write_text("x")
        self.assertEqual(self.route("정리해"), "")
        (self.home / ".claude/skill-routes").write_text("정리해\tplugin-a:cleanup\n정리해\t../skills/ship-pr\n")
        self.assertEqual(self.route("정리해"), "")

    def test_each_runtime_sees_only_its_own_skills(self):
        (self.home / ".agents/skills/cleanup").mkdir(parents=True)
        (self.home / ".agents/skills/cleanup/SKILL.md").write_text("x")
        self.assertEqual(self.route("정리해"), "", "a Codex-only skill is not routed in Claude Code")
        self.env["HARNESS_REQUIRED_REVIEWER"] = "claude"   # set by the Codex bridge
        note = self.route("정리해")
        self.assertIn("$cleanup", note)
        self.assertNotIn("Skill tool", note)
        self.assertEqual(self.route("PR 올려줘"), "", "a Claude-only skill is not routed in Codex")

    def test_a_last_route_without_a_newline_still_counts(self):
        (self.home / ".claude/skill-routes").write_text("정리해\tticket")
        self.assertIn("`ticket`", self.route("정리해"))

    def test_an_uninstalled_first_match_falls_through_to_a_later_route(self):
        (self.home / ".claude/skill-routes").write_text("정리해\tcleanup\n정리해\tticket\n")
        self.assertIn("`ticket`", self.route("정리해"))

    def test_project_skills_count_and_no_routes_file_is_quiet(self):
        (self.root / ".claude/skills/cleanup").mkdir(parents=True)
        (self.root / ".claude/skills/cleanup/SKILL.md").write_text("x")
        self.assertIn("`cleanup`", self.route("정리해"))
        (self.home / ".claude/skill-routes").unlink()
        self.assertEqual(self.route("PR 올려줘"), "")


if __name__ == "__main__":
    unittest.main()
