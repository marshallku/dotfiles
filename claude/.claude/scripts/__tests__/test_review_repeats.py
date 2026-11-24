import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "review_repeats", Path(__file__).resolve().parents[1] / "review_repeats.py"
)
review_repeats = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review_repeats)

WORDING = "directory sync failure still applies the sidebar order"


class ReviewRepeatsTests(unittest.TestCase):
    def test_same_file_with_moved_line_repeats(self):
        found = review_repeats.repeats(f"- [C3] linux/src/ui/shell.rs:1956 — {WORDING}",
                                       f"- [C1] linux/src/ui/shell.rs:1963 — {WORDING}")
        self.assertEqual(found, [("C1", "C3", ["linux/src/ui/shell.rs"])])

    def test_bare_name_matches_its_full_path(self):
        found = review_repeats.repeats(f"- [C1] [shell.rs](/home/u/linux/src/ui/shell.rs:10) — {WORDING}",
                                       f"- [C2] `linux/src/ui/shell.rs:12` — {WORDING}")
        self.assertEqual([(c, p) for c, p, _ in found], [("C2", "C1")])

    def test_same_basename_in_different_directories_does_not_repeat(self):
        found = review_repeats.repeats(f"- [C1] client/index.ts:5 — {WORDING}",
                                       f"- [C1] admin/index.ts:5 — {WORDING}")
        self.assertEqual(found, [])

    def test_different_wording_in_the_same_file_does_not_repeat(self):
        found = review_repeats.repeats(f"- [C1] shell.rs:5 — {WORDING}",
                                       "- [C1] shell.rs:5 — keyboard observer cancels launch in another window")
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
