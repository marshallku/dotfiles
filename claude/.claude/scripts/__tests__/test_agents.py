"""Every agent definition must load and pin its model.

The four agents in ~/.claude/agents had `model: sonnet` but no `name:`, so Claude Code never
listed them and 224 of 247 subagent runs fell back to the parent's Opus (work Mac, 2026-10-20 →
11-19). A definition without `name` is skipped silently, which is why nobody noticed.
"""
from pathlib import Path
import re
import unittest


AGENTS = Path(__file__).resolve().parents[2] / "agents"
REQUIRED_KEYS = ("name", "description", "model")


def frontmatter(path):
    text = path.read_text(encoding="utf-8")
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        return {}
    return dict(re.findall(r"^([A-Za-z]+):\s*(.*)$", match.group(1), re.M))


class AgentDefinitionTests(unittest.TestCase):
    def test_every_agent_has_name_description_and_model(self):
        files = sorted(AGENTS.glob("*.md"))
        self.assertTrue(files, "no agent definitions found")
        for path in files:
            with self.subTest(agent=path.name):
                meta = frontmatter(path)
                for key in REQUIRED_KEYS:
                    self.assertTrue(meta.get(key), f"{path.name} lacks `{key}:`")
                self.assertEqual(meta["name"], path.stem, "name must match the file name")


if __name__ == "__main__":
    unittest.main()
