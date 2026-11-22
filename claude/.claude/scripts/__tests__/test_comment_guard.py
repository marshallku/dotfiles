"""comment-guard: the rules per language, the Edit/Write hook and the Bash path through
track-bash-edit, run against real git repositories from an isolated HOME.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


CLAUDE = Path(__file__).resolve().parents[2]
SCRIPT = CLAUDE / "scripts/comment_guard.py"
UV = shutil.which("uv")


def real_uv_cache():
    if not UV:
        return ""
    return subprocess.run([UV, "cache", "dir"], capture_output=True, text=True).stdout.strip()


UV_CACHE = real_uv_cache()


@unittest.skipUnless(UV, "uv is required to resolve tree-sitter")
class CommentGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name))
        self.home = self.root / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(CLAUDE / "hooks")
        (self.home / ".claude/scripts").symlink_to(CLAUDE / "scripts")
        self.env = {**os.environ, "HOME": str(self.home), "UV_CACHE_DIR": UV_CACHE}
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "a.go").write_text("package p\n\n// Old explains nothing new.\nfunc Old() {}\n")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.email=t@e.invalid", "-c", "user.name=T", "-c", "core.hooksPath=/dev/null",
                 "commit", "-qm", "init")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True, text=True, env=self.env)

    def guard(self, *args):
        out = subprocess.run([UV, "run", "-q", "--script", str(SCRIPT), *args], cwd=self.repo, env=self.env,
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout

    def hook(self, name, payload, *args):
        out = subprocess.run(["bash", str(self.home / ".claude/hooks" / name), *args],
                             input=json.dumps({"session_id": "s", "cwd": str(self.repo), **payload}),
                             text=True, capture_output=True, env=self.env, cwd=self.repo)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout or "{}")

    def events(self):
        ledger = self.home / ".claude/state/hook-events.jsonl"
        lines = ledger.read_text().splitlines() if ledger.exists() else []
        return [e for e in map(json.loads, lines) if e["component"] == "comment-guard"]

    def test_go_rules_on_a_tracked_file(self):
        (self.repo / "a.go").write_text(
            "package p\n\n// Old explains nothing new.\nfunc Old() {}\n\n"
            "// Reserve holds qty units; ErrShort when stock is short.\nfunc Reserve() {}\n\n"
            "func g() {\n\t// Previously this used a sync.Map\n\tx := 1\n\t_ = x\n"
            "\tpanic(\"not implemented\") // TODO\n}\n"
        )
        records = [json.loads(l) for l in self.guard("diff").splitlines()]
        found = {r["text"].split("\n")[0]: (r["kind"], r["hits"]) for r in records}
        self.assertNotIn("// Old explains nothing new.", found)
        self.assertEqual(found["// Reserve holds qty units; ErrShort when stock is short."], ("doc", []))
        self.assertEqual(found["// Previously this used a sync.Map"], ("plain", ["change-history"]))
        self.assertEqual(found["// TODO"], ("plain", ["escape-hatch", "stub-code"]))

    def test_rust_ts_bash_rules_on_new_files(self):
        rust = ("/// Parses a frame; errors on a short header.\n/// Second contract line.\npub fn parse() {}\n"
                "fn f() {\n    // Codex round 2 flagged this, so check len\n    let x = 1;\n"
                "    // let y = compute(x);\n    // SAFETY: ptr is non-null by construction\n}\n")
        ts = ("/** Returns the entry, or undefined once its TTL passed. */\nexport function get(): void {}\n"
              "// For now, just return null\nconst a = null;\n// eslint-disable-next-line no-console\n"
              "// Where the todo came from opens\nconst b = 1;\n")
        sh = ("#!/usr/bin/env bash\n# shellcheck disable=SC2086\n# Deploys the site.\nset -e\n"
              "# Step 1: build\nmake\n# Regression for review finding #3\nx=1\n"
              "# rm -rf \"$TMP\"\ntrue\n# grep reads the file: `printf | grep -q` under pipefail\ntrue\n")
        for name, src in (("a.rs", rust), ("a.ts", ts), ("deploy.sh", sh)):
            (self.repo / name).write_text(src)
        out = self.guard("hook", "--session", "r", "a.rs", "a.ts", "deploy.sh")
        self.assertIn("a.rs:5 `// Codex round 2 flagged this", out)
        self.assertIn("a.rs:7 `// let y = compute(x);` — is commented-out code", out)
        self.assertNotIn("SAFETY", out)
        self.assertNotIn("Parses a frame", out)
        self.assertIn("a.ts:3 `// For now, just return null`", out)
        self.assertNotIn("eslint", out)
        self.assertNotIn("Where the todo", out)
        self.assertIn("deploy.sh:5 `# Step 1: build` — narrates", out)
        self.assertIn("deploy.sh:7 `# Regression for review finding #3`", out)
        self.assertNotIn("Deploys the site", out)
        self.assertIn("deploy.sh:9 `# rm -rf \"$TMP\"` — is commented-out code", out)
        self.assertNotIn("grep reads the file", out)

    def test_diff_cached_reads_the_index_not_the_tree(self):
        target = self.repo / "a.go"
        target.write_text(target.read_text() + "\n// Codex round 3 asked for this guard.\nfunc B() {}\n")
        self.git("add", "a.go")
        target.write_text(target.read_text() + "\n// For now, unused.\nfunc C() {}\n")
        staged = [json.loads(l)["text"] for l in self.guard("diff", "--cached").splitlines()]
        self.assertEqual(staged, ["// Codex round 3 asked for this guard."])
        unstaged = [json.loads(l)["text"] for l in self.guard("diff").splitlines()]
        self.assertEqual(unstaged, ["// For now, unused."])

    def test_edit_hook_reports_new_comments_once(self):
        target = self.repo / "a.go"
        target.write_text(target.read_text() + "\n// B fixes codex round 2 finding: reject qty <= 0.\nfunc B() {}\n")
        payload = {"tool_name": "Edit", "tool_input": {"file_path": str(target)}}
        first = self.hook("comment-guard.sh", payload)
        context = first["hookSpecificOutput"]["additionalContext"]
        self.assertIn("a.go:6 `// B fixes codex round 2 finding", context)
        self.assertNotIn("Old explains", context)
        self.assertEqual(self.hook("comment-guard.sh", payload), {})
        self.assertEqual([e["event"] for e in self.events()][-2:], ["checked", "checked"])
        self.assertEqual(self.git("diff", "--cached", "--name-only").stdout, "")

    def test_clean_edits_and_unsupported_files_stay_quiet(self):
        target = self.repo / "a.go"
        target.write_text(target.read_text() + "\n// B rejects qty <= 0 because Available would grow.\nfunc B() {}\n")
        self.assertEqual(self.hook("comment-guard.sh", {"tool_input": {"file_path": str(target)}}), {})
        (self.repo / "notes.md").write_text("# for now\n")
        self.assertEqual(self.hook("comment-guard.sh", {"tool_input": {"file_path": str(self.repo / "notes.md")}}), {})
        self.assertEqual([e["event"] for e in self.events()], ["heartbeat", "checked"])

    def test_disabled_marker_and_missing_uv_skip_without_blocking(self):
        (self.repo / "a.go").write_text("package p\n\n// TODO later\nfunc A() {}\n")
        payload = {"tool_input": {"file_path": str(self.repo / "a.go")}}
        marker = self.home / ".claude/state/comment-guard-disabled"
        marker.touch()
        self.assertEqual(self.hook("comment-guard.sh", payload), {})
        marker.unlink()
        no_uv = {**self.env, "PATH": "/usr/bin:/bin", "HOME": str(self.root / "nouv-home")}
        (self.root / "nouv-home/.claude/state").mkdir(parents=True)
        out = subprocess.run(["bash", str(CLAUDE / "hooks/comment-guard.sh")], input=json.dumps(payload),
                             text=True, capture_output=True, env=no_uv)
        self.assertEqual((out.returncode, out.stdout.strip()), (0, "{}"))
        if not Path("/usr/bin/uv").exists():
            ledger = (self.root / "nouv-home/.claude/state/hook-events.jsonl").read_text()
            self.assertIn('"reason":"no_uv"', ledger)
        self.assertEqual(self.events()[-1]["reason"], "disabled_marker")

    def test_bash_edit_reaches_comment_guard(self):
        payload = {"tool_input": {"command": "python3 - <<'PY'\n...\nPY"}}
        self.hook("track-bash-edit.sh", payload, "pre")
        (self.repo / "new.ts").write_text("// Regression: Codex round 2 [P2] rejects ttlMs <= 0.\nexport const x = 1;\n")
        out = self.hook("track-bash-edit.sh", payload, "post")
        context = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn("[track-bash-edit] Comment policy", context)
        self.assertIn("new.ts:1 `// Regression: Codex round 2 [P2]", context)


if __name__ == "__main__":
    unittest.main()
