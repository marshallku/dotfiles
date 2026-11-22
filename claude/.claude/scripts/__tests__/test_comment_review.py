"""comment_review.py against a real git index with a fake claude CLI standing in for the models."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


CLAUDE = Path(__file__).resolve().parents[2]
SCRIPT = CLAUDE / "scripts/comment_review.py"
UV = shutil.which("uv")
UV_CACHE = subprocess.run([UV, "cache", "dir"], capture_output=True, text=True).stdout.strip() if UV else ""

FAKE_CLAUDE = r'''#!/usr/bin/env python3
import json, re, sys
args = sys.argv[1:]
model = args[args.index("--model") + 1]
prompt = sys.stdin.read()
if "FAILMODEL" in prompt:
    sys.exit(1)
if "BADEXIT" in prompt:
    print(json.dumps({"structured_output": {"items": []}}))
    sys.exit(3)
items = []
for block in prompt.split("--- id=")[1:]:
    ident = int(re.match(r"\d+", block).group())
    comment = block.split("COMMENT:\n", 1)[1].split("\nCONTEXT:", 1)[0]
    slop = "SLOP" in comment or ("ONEMODEL" in comment and model == "sonnet")
    items.append({"id": ident, "verdict": "delete" if slop else "keep", "category": "restates" if slop else "why"})
if "PARTIAL" in prompt and model == "haiku":
    items = items[:-1]
if "NOVERDICT" in prompt and model == "haiku":
    del items[0]["verdict"]
print(json.dumps({"structured_output": {"items": items}, "total_cost_usd": 0.001}))
'''


@unittest.skipUnless(UV, "uv is required to resolve tree-sitter")
class CommentReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        self.home.mkdir()
        fake = self.root / "claude"
        fake.write_text(FAKE_CLAUDE)
        fake.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home), "UV_CACHE_DIR": UV_CACHE, "COMMENT_REVIEW_CLAUDE": str(fake)}
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "a.go").write_text("package p\n")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.email=t@e.invalid", "-c", "user.name=T", "-c", "core.hooksPath=/dev/null",
                 "commit", "-qm", "init")

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True, env=self.env)

    def review(self, *args):
        return subprocess.run([UV, "run", "-q", "--script", str(SCRIPT), *args], cwd=self.repo, env=self.env,
                              capture_output=True, text=True)

    def stage(self, body):
        (self.repo / "a.go").write_text("package p\n\n" + body)
        self.git("add", "a.go")

    def test_nothing_staged_is_clean(self):
        out = self.review()
        self.assertEqual((out.returncode, out.stdout.strip()), (0, "comment-review: no added comments"))

    def test_rules_or_both_models_flag_and_one_model_does_not(self):
        self.stage(
            "// Codex round 2 flagged the empty case.\nfunc A() {}\n\n"
            "// A SLOP comment both models reject.\nfunc B() {}\n\n"
            "// An ONEMODEL comment only sonnet rejects.\nfunc C() {}\n\n"
            "// C returns early because the cache may be nil before Start.\nfunc D() {}\n"
        )
        out = self.review("--cached")
        self.assertEqual(out.returncode, 1, out.stderr)
        self.assertIn("4 added comments, 2 findings", out.stdout)
        self.assertIn("`a.go:3` **delete** (process-narration)", out.stdout)
        self.assertIn("`a.go:6` **delete** (restates)", out.stdout)
        self.assertNotIn("ONEMODEL", out.stdout)
        self.assertNotIn("cache may be nil", out.stdout)
        usage = (self.home / ".claude/state/comment-review-usage.jsonl").read_text().splitlines()
        self.assertEqual(sorted(json.loads(l)["model"] for l in usage), ["haiku", "sonnet"])

    def test_unstaged_comments_are_not_reviewed(self):
        self.stage("// Clean why: nil before Start.\nfunc A() {}\n")
        (self.repo / "a.go").write_text((self.repo / "a.go").read_text() + "\n// A SLOP line.\nfunc B() {}\n")
        out = self.review()
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    def test_a_failing_model_is_an_error_not_a_pass(self):
        self.stage("// FAILMODEL comment.\nfunc A() {}\n")
        out = self.review()
        self.assertEqual(out.returncode, 2)
        self.assertIn("could not review", out.stderr)


    def test_incomplete_or_failed_model_output_is_an_error(self):
        for marker in ("PARTIAL", "BADEXIT", "NOVERDICT"):
            with self.subTest(marker=marker):
                self.stage(f"// A {marker} comment.\nfunc A() {{}}\n\n// Another one.\nfunc B() {{}}\n")
                out = self.review()
                self.assertEqual(out.returncode, 2, out.stdout)
                self.assertIn("could not review", out.stderr)

    def test_two_and_three_dot_ranges_read_the_target_revision(self):
        self.stage("// A SLOP comment.\nfunc A() {}\n")
        self.git("-c", "user.email=t@e.invalid", "-c", "user.name=T", "-c", "core.hooksPath=/dev/null",
                 "commit", "-qm", "second")
        for rev_range in ("HEAD~1..HEAD", "HEAD~1...HEAD", "HEAD~1.."):
            with self.subTest(rev_range=rev_range):
                out = self.review(rev_range)
                self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
                self.assertIn("1 added comments, 1 findings", out.stdout)

    def test_quoted_and_non_ascii_paths_are_reviewed(self):
        for name in ("한글 파일.go", 'quo"te.go', '한글"파일.go'):
            (self.repo / name).write_text("package p\n\n// A SLOP comment.\nfunc A() {}\n")
            self.git("add", name)
        out = self.review()
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("`한글 파일.go:3`", out.stdout)
        self.assertIn('`quo"te.go:3`', out.stdout)
        self.assertIn('`한글"파일.go:3`', out.stdout)

    def test_extensionless_script_is_judged_by_its_staged_shebang(self):
        (self.repo / "deploy").write_text("#!/usr/bin/env bash\nset -e\n:\n# A SLOP comment.\ntrue\n")
        self.git("add", "deploy")
        (self.repo / "deploy").unlink()
        out = self.review()
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("`deploy:4`", out.stdout)

    def test_an_added_increment_line_does_not_end_the_file(self):
        (self.repo / "a.ts").write_text("let counter = 0;\n")
        self.git("add", "a.ts")
        self.git("-c", "user.email=t@e.invalid", "-c", "user.name=T", "-c", "core.hooksPath=/dev/null",
                 "commit", "-qm", "ts")
        (self.repo / "a.ts").write_text("let counter = 0;\n++counter;\n\n\n\n\n\n\n// A SLOP comment.\nexport {};\n")
        self.git("add", "a.ts")
        out = self.review()
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("`a.ts:9`", out.stdout)

    def test_a_missing_cli_is_an_error_not_a_finding(self):
        self.stage("// A SLOP comment.\nfunc A() {}\n")
        self.env["COMMENT_REVIEW_CLAUDE"] = str(self.root / "no-such-claude")
        out = self.review()
        self.assertEqual(out.returncode, 2, out.stdout + out.stderr)
        self.assertIn("cannot run", out.stderr)

    def test_an_invalid_range_is_an_error_not_an_empty_review(self):
        out = self.review("nope..HEAD")
        self.assertEqual(out.returncode, 2, out.stdout)
        self.assertIn("could not review", out.stderr)


if __name__ == "__main__":
    unittest.main()
