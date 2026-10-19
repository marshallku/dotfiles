"""Table tests for hooks/_commit_targets.py: which repositories a Bash command commits in."""
import os
from pathlib import Path
import subprocess
import unittest


HELPER = Path(__file__).resolve().parents[2] / "hooks/_commit_targets.py"
S = "save" + ".sh"
CW = "/home/u/dev/aide"
CASES = [
    (f'grep -n "push" ~/{S} | head', "none"),
    (f'sed -n 1,40p /home/u/{S}', "none"),
    (f'cd ~/docs && git add x.md && ~/{S} "docs: add `x` (y)" 2>&1 | tail -3', "FALLBACK"),
    (f'cd "$HOME/bots/Marshall Ku" && ~/{S} "chore: x"', "/home/u/bots/Marshall Ku"),
    (f'cd ~/bots && cd "Marshall Ku" && ~/{S} "x"', "/home/u/bots/Marshall Ku"),
    (f'(cd ~/docs && true); ~/{S} x', "FALLBACK"),
    (f'cd ~/docs && false || ~/{S} x', "FALLBACK"),
    (f'printf "%s" "$(cd ~/docs && ~/{S} x)"', "FALLBACK"),
    (f'env FOO=1 ~/{S} "x"', "FALLBACK"),
    (f'timeout 60 ~/{S} x', "FALLBACK"),
    (f'nohup ~/{S} x', "FALLBACK"),
    (f'FOO=1 ~/{S} x', CW),
    (f'"${{HOME}}/{S}" "Fix bug"', CW),
    (f"bash -c '~/{S} \"x\"'", "FALLBACK"),
    (f'cd ~/docs & wait && ~/{S} x', "FALLBACK"),
    (f'cd ~/docs; ~/{S} x', f"{CW}|/home/u/docs"),
    ('git log | grep ' + 'commit', "none"),
    ('git -C ~/docs ' + 'commit -m x', "/home/u/docs"),
    ('git ' + 'commit-tree abc', "none"),
    (f'cd ~/docs && git status\n~/{S} "x"', f"{CW}|/home/u/docs"),
    (f'cd $D && ~/{S} x', "FALLBACK"),
    (f'python3 - <<EOF\n{S}\nEOF', "FALLBACK"),
    (f'bash ~/{S} "msg"', "FALLBACK"),
    (f"~/{S} 'fix: use $(x) safely'", CW),
    (f'cd ~/docs && ~/{S} "a" && cd ~/dotfiles && ~/{S} "b"', "/home/u/docs|/home/u/dotfiles"),
    (f'cd ~/docs | ~/{S} x', CW),
    (f'cd ~/docs && echo hi; ~/{S} x', f"{CW}|/home/u/docs"),
    (f"S=/tmp/x; cat > $S/b.md <<'EOF'\nrun ~/{S} later\nEOF", "none"),
    (f"cat > b.md <<\"EOF\"\n~/{S} x\nEOF\necho done", "none"),
    (f"cat <<'EOF' | bash\n~/{S} x\nEOF", "FALLBACK"),
    (f"python3 - <<'EOF'\nimport os; os.system('~/{S} x')\nEOF", "FALLBACK"),
    (f"cat <<EOF\n$(~/{S} x)\nEOF", "FALLBACK"),
    (f"cat > f <<'EOF'\n{S}\nEOF\n~/{S} \"x\"", "FALLBACK"),
    (f"cat > f <<'EOF'\n~/{S} x\n", "FALLBACK"),
    (f"cat <<< \"~/{S} x\"", "FALLBACK"),
    # Cross-review round 1 regressions.
    ('bash -c "git ' + 'commit -m x"', "FALLBACK"),
    ('env bash -c "git ' + 'commit -m x"', "FALLBACK"),
    (f"rg --pre ~/{S} pattern README.md", "FALLBACK"),
    (f"rg --pre=~/{S} pattern README.md", "FALLBACK"),
    (f"sed '1e ~/{S}' notes.txt", "FALLBACK"),
    (f"sed -e 'e ~/{S}' notes.txt", "FALLBACK"),
    # sed is not a reader (GNU `e` runs its script, which can hide in any argument); only the
    # line-printing shape `sed -n N[,M]p FILE…` is exempt.
    (f"sed -n 1,40p ~/{S}", "none"),
    (f"sed -n 5p ~/{S} ~/{S}", "none"),
    (f"sed -n 1,40p -e '1e ~/{S}' x", "FALLBACK"),
    (f"sed -n '1e ~/{S}'", "FALLBACK"),
    ('git -C /repos -C app ' + 'commit -m x', "/repos/app"),
    ('git -C "$REPO" ' + 'commit -m x', "FALLBACK"),
    ('git --git-dir=/r/.git ' + 'commit -m x', "FALLBACK"),
    # Cross-review round 2 regressions.
    ("sed -n '1e git " + "commit -m x' README.md", "FALLBACK"),
    (f"cat -n ~/{S}", "none"),
    (f"grep -n {S} README.md", "none"),
    (f"tail -n 5 ~/{S}", "none"),
    # Cross-review round 3 regressions: attached sed scripts.
    ("sed -e'1e git " + "commit -m x' README.md", "FALLBACK"),
    (f"sed -n -e p -e'1e ~/{S}' README.md", "FALLBACK"),
    # A commit message with parentheses, `||` and a cd example is still one quoted word.
    (f'cd ~/dotfiles && ~/{S} "fix: x (y)\n\ncd ~/docs && ~/{S} || & was judged" 2>&1 | tail -2', "/home/u/dotfiles"),
    (f'~/{S} x; (cd ~/docs)', "FALLBACK"),
    # Round 4: the script is the last word when sed reads stdin.
    (f"cat README.md | sed -n '1e ~/{S}'", "FALLBACK"),
]


class CommitTargetsTests(unittest.TestCase):
    def test_table(self):
        env = {"HOME": "/home/u", "PATH": os.environ["PATH"]}
        for cmd, want in CASES:
            with self.subTest(cmd=cmd):
                out = subprocess.run(["python3", str(HELPER), CW], input=cmd, text=True, capture_output=True,
                                     env=env, check=True).stdout.split("\n")
                dirs = [line[4:] for line in out if line.startswith("dir ")]
                if want == "FALLBACK":
                    # Fallback is the pre-helper behaviour: always judged against the cwd repository.
                    self.assertIn(CW, dirs)
                elif want == "none":
                    self.assertEqual(out[0], "none")
                else:
                    self.assertEqual(sorted(dirs), sorted(want.split("|")))


if __name__ == "__main__":
    unittest.main()
