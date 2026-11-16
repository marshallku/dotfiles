"""protect-read.sh keeps agents out of the paths in ~/.claude/agent-deny-paths.

The list is private (not in git) and optional, so it cannot feed settings.json `Read(...)`
rules and the hook is the only layer: it must stop direct reads, and recursive walks from
a parent (`grep -r TOKEN proj` printed a file Claude Code's own rule denied, 2026-11-16).
These run the deployed hook against a fake $HOME.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


CLAUDE = Path(__file__).resolve().parents[2]
HOOKS = CLAUDE / "hooks"


class ProtectReadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(os.path.realpath(self.temp.name)) / "home"
        (self.home / ".claude/state").mkdir(parents=True)
        (self.home / ".claude/hooks").symlink_to(HOOKS)
        self.repo = self.home / "dev/proj"
        (self.repo / "vault/a").mkdir(parents=True)
        (self.repo / "vault/a/caption.txt").write_text("SECRET\n")
        (self.repo / "src").mkdir()
        (self.repo / "src/run.py").write_text("print(1)\n")
        self.deny_list = self.home / ".claude/agent-deny-paths"
        self.deny_list.write_text("# private list\n\n~/dev/proj/vault\n")
        self.env = {**os.environ, "HOME": str(self.home)}

    def run_hook(self, tool, tool_input, cwd=None, hooks=None):
        payload = {"session_id": "s", "tool_name": tool, "tool_input": tool_input, "cwd": str(cwd or self.repo)}
        result = subprocess.run(["bash", str((hooks or self.home / ".claude/hooks") / "protect-read.sh")],
                                input=json.dumps(payload), text=True, capture_output=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        out = json.loads(result.stdout or "{}")
        self.assertNotIn("permissionDecision", out)
        return out.get("hookSpecificOutput", {}).get("permissionDecision", "allow")

    def bash(self, command, cwd=None):
        return self.run_hook("Bash", {"command": command}, cwd)

    def test_list_is_private_and_optional(self):
        self.assertFalse((HOOKS / "agent-deny-paths").exists())
        read = ("Read", {"file_path": str(self.repo / "vault/a/caption.txt")})
        self.assertEqual(self.run_hook(*read), "deny")
        for content in (None, "", "# only comments\n\n", "relative/path\n", "\xff\xfe garbage\n"):
            if content is None:
                self.deny_list.unlink()
            else:
                self.deny_list.write_text(content, errors="surrogateescape")
            self.assertEqual(self.run_hook(*read), "allow", content)
            self.assertEqual(self.run_hook("Bash", {"command": "grep -r SECRET ."}), "allow", content)
        self.deny_list.write_text("relative/path\n~/dev/proj/vault\n")
        self.assertEqual(self.run_hook(*read), "deny")

    def test_hook_is_registered_for_reading_tools(self):
        hooks = json.loads((CLAUDE / "settings.json").read_text())["hooks"]["PreToolUse"]
        matchers = [h["matcher"] for h in hooks if any("protect-read.sh" in c["command"] for c in h["hooks"])]
        self.assertEqual(len(matchers), 1)
        for tool in ("Bash", "Read", "Glob", "Grep", "Edit", "Write"):
            self.assertIn(tool, matchers[0].split("|"))

    def test_direct_references_are_denied(self):
        for command in ("cat vault/a/caption.txt", "ls vault", "ls ./vault/", "cat ~/dev/proj/vault/x",
                        'cat "$HOME/dev/proj/vault/a/caption.txt"', "cd vault && cat a/caption.txt",
                        "cd ~/dev/proj && ls vault", "head vau*/a/*", "cat src/../vault/a",
                        "python3 -c \"print(open('vault/a/caption.txt').read())\"",
                        "bash -c 'ls -la vault'", "python3 -c \"open('vault/a/caption.txt'); print('!')\"", "rg --files --glob=x vault", "git -C ~/dev/proj/vault log",
                        "cp -t /tmp vault/a/caption.txt", "tar --file=vault/a.tar -x", "ls ~/dev/*/vault"):
            self.assertEqual(self.bash(command), "deny", command)
        self.assertEqual(self.bash("ls proj/vault", cwd=self.home / "dev"), "deny")

    def test_recursive_walks_above_the_path_are_denied_unless_they_exclude_it(self):
        for command in ("grep -r SECRET .", "grep -rn SECRET", "rg SECRET", "rg SECRET ~/dev", "find . -name '*.txt'",
                        "ls -R", "tree", "tar czf /tmp/x.tgz .", "cp -r . /tmp/copy", "du -a ~/dev", "ls ~/dev/**/*.txt",
                        "fd txt", "rsync -a ./ /tmp/x", "zip -r /tmp/x.zip ."):
            self.assertEqual(self.bash(command), "deny", command)
        for command in ("rg SECRET -g '!vault'", "rg SECRET --glob '!vault/**'", "grep -r --exclude-dir=vault SECRET .",
                        "grep -r SECRET --exclude-dir vault .", "find . -path '*/vault' -prune -o -name '*.py' -print",
                        "fd -E vault py", "tar --exclude=vault -czf /tmp/x.tgz .", "rg SECRET -g '*.py' -g '!vault'",
                        "rsync -a --exclude=vault/ ./ /tmp/x", "find -L . -name vault -prune -o -print", "tree -I 'node_modules|vault'"):
            self.assertEqual(self.bash(command), "allow", command)
        # Exclusions that still walk into the directory (cross-review C1).
        for command in ("grep -r --exclude=vault SECRET .", "rg SECRET -g '!vault-backup'", "rg SECRET -g vault",
                        "find . -not -name vault -type f -print", "find . -name vault -print",
                        "fd -E vault-old txt",
                        # cross-review round 2: patterns the command never matches, and later overrides
                        "grep -r --exclude-dir='vault/**' SECRET .", "find . -path vault -prune -o -type f -print",
                        "rg SECRET -g '!vault' -g '*'", "rsync -a --include='vault/**' --exclude=vault ./ /tmp/x",
                        # round 3: prune that never runs, children-first walks, wildcard semantics
                        "find . -depth -name vault -prune -o -type f -print",
                        "find . -false -name vault -prune -o -type f -print",
                        "tar -cf /tmp/out.tar --no-wildcards --exclude=peo?le .", "grep -r --exclude-dir='vau*' SECRET .",
                        "tar --anchored --exclude=vault -cf /tmp/o.tar .",
                        # round 4: -path patterns that miss ./vault, attached rsync filter rules
                        "find . -path '*x/vault' -prune -o -type f -print", "rsync -a '-f+ *' --exclude=vault ./ /tmp/x",
                        "rsync -avf '+ *' --exclude=vault ./ /tmp/x"):
            self.assertEqual(self.bash(command), "deny", command)

    def policy(self, entries, payload):
        deny_list = self.home / "list"
        deny_list.write_text("\n".join(entries) + "\n")
        result = subprocess.run(["python3", str(HOOKS / "_read_policy.py"), str(deny_list), str(self.home)],
                                input=json.dumps(payload), text=True, capture_output=True, check=True)
        return result.stdout.split()[0]

    def test_glob_entries_are_reached_by_walks_from_their_prefix(self):
        (self.home / "w/a/vault").mkdir(parents=True)
        for cwd in ("w", "w/a", "w/a/vault"):
            payload = {"tool_name": "Bash", "tool_input": {"command": "rg SECRET"}, "cwd": str(self.home / cwd)}
            self.assertEqual(self.policy(["~/w/*/vault"], payload), "deny", cwd)
        payload = {"tool_name": "Bash", "tool_input": {"command": "rg SECRET"}, "cwd": str(self.home / "w/a")}
        self.assertEqual(self.policy(["~/w/b*/vault"], payload), "allow")
        self.assertEqual(self.policy(["~/**/.secrets"], payload), "deny")
        payload["tool_input"]["command"] = "cat x/.secrets/k"
        self.assertEqual(self.policy(["~/**/.secrets"], payload), "deny")
        # `**` matches zero directories too (cross-review: /tmp/**/.secrets missed /tmp/.secrets/key).
        read = {"tool_name": "Read", "tool_input": {"file_path": str(self.home / ".secrets/key")}, "cwd": str(self.home)}
        self.assertEqual(self.policy(["~/**/.secrets"], read), "deny")
        self.assertEqual(self.policy(["~/w/**"], {**read, "tool_input": {"file_path": str(self.home / "w")}}), "deny")
        # A glob in the last segment has no exclusion that provably covers it.
        (self.home / "w/vault2").mkdir()
        payload = {"tool_name": "Bash", "tool_input": {"command": "rg SECRET --glob=!vault"}, "cwd": str(self.home / "w")}
        self.assertEqual(self.policy(["~/w/vault*"], payload), "deny")
        payload["tool_input"]["command"] = "rg SECRET -g '!.secrets'"
        self.assertEqual(self.policy(["~/**/.secrets"], payload), "allow")

    def test_directory_only_exclusions_do_not_cover_files(self):
        (self.home / "w/a").mkdir(parents=True)
        (self.home / "w/a/caption.txt").write_text("SECRET\n")
        walk = {"tool_name": "Bash", "cwd": str(self.home / "w")}
        for entry in ("~/w/*/caption.txt", "~/w/a/caption.txt"):
            for command in ("grep -r --exclude-dir=caption.txt SECRET .", "ag --ignore-dir caption.txt SECRET"):
                self.assertEqual(self.policy([entry], {**walk, "tool_input": {"command": command}}), "deny", (entry, command))
            for command in ("rg SECRET -g '!caption.txt'", "find . -name caption.txt -prune -o -print"):
                self.assertEqual(self.policy([entry], {**walk, "tool_input": {"command": command}}), "allow", (entry, command))

    def test_newline_starts_a_new_command(self):
        self.assertEqual(self.bash("true\nrg SECRET"), "deny")
        self.assertEqual(self.bash("cd src\nrg SECRET"), "deny")  # cd may fail; the walk can still start here
        self.assertEqual(self.bash("python3 -c 'a = 1\nprint(a)'"), "allow")

    def test_globs_inside_quoted_text_are_not_expanded(self):
        self.assertEqual(self.bash("python3 -c \"print('/**')\"", cwd=self.home / "dotfiles"), "allow")

    def test_unrelated_commands_run(self):
        for command in ("ls", "ls -la", "cat src/run.py", "rg SECRET src", "grep -r x src", "find src",
                        "git status", "git commit -m 'update vault runner'", "ls -lr ~/dev"):
            self.assertEqual(self.bash(command), "allow", command)
        self.assertEqual(self.bash("rg SECRET", cwd=self.home / "dotfiles"), "allow")
        # Conservative: a bare word that names the denied dir from its parent counts as a path.
        self.assertEqual(self.bash("echo vault"), "deny")

    def test_file_tools(self):
        target = str(self.repo / "vault/a/caption.txt")
        for tool in ("Read", "Edit", "Write"):
            self.assertEqual(self.run_hook(tool, {"file_path": target}), "deny", tool)
        self.assertEqual(self.run_hook("Read", {"file_path": "vault/a/caption.txt"}), "deny")
        self.assertEqual(self.run_hook("Read", {"file_path": str(self.repo / "src/run.py")}), "allow")
        self.assertEqual(self.run_hook("Glob", {"pattern": "**/*.txt"}), "deny")
        self.assertEqual(self.run_hook("Glob", {"pattern": "*.py"}), "allow")
        self.assertEqual(self.run_hook("Glob", {"pattern": "vault/*"}), "deny")
        self.assertEqual(self.run_hook("Grep", {"pattern": "SECRET"}), "deny")
        self.assertEqual(self.run_hook("Grep", {"pattern": "SECRET", "path": "src"}), "allow")

    def test_symlinked_alias_is_denied(self):
        (self.home / "alias").symlink_to(self.repo / "vault")
        self.assertEqual(self.bash("cat ~/alias/a/caption.txt"), "deny")
        self.assertEqual(self.run_hook("Read", {"file_path": str(self.home / "alias/a/caption.txt")}), "deny")

    def test_missing_helper_denies_while_a_list_exists(self):
        broken = self.home / "broken-hooks"
        shutil.copytree(HOOKS, broken, ignore=shutil.ignore_patterns("__pycache__"))
        (broken / "_read_policy.py").unlink()
        self.assertEqual(self.run_hook("Bash", {"command": "ls"}, hooks=broken), "deny")
        self.deny_list.unlink()
        self.assertEqual(self.run_hook("Bash", {"command": "ls"}, hooks=broken), "allow")


if __name__ == "__main__":
    unittest.main()
