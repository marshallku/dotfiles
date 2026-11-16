#!/usr/bin/env python3
"""Judge whether a tool call would read a path listed in ~/.claude/agent-deny-paths.

Usage: _read_policy.py <deny-list> <home>   (PreToolUse payload JSON on stdin)
Prints one line: `allow` or `deny <why>`. A missing or empty list, and lines that are not
`~/…` or `/abs` paths, mean nothing is protected (the list is private and optional).
Any other failure exits non-zero; the hook denies.

The list stays out of git, so it cannot feed settings.json `Read(...)` rules; this is the
only layer. It must cover what those rules would: Claude Code's own rule refused Read and
Bash naming the path, but a recursive command rooted above it was not checked —
`grep -r TOKEN proj` printed the denied `proj/sec/a.txt` (reproduced 2026-11-16, claude
2.1.325). Search has no Glob/Grep tools in that version; it all goes through Bash.

So this denies:
  * any path operand, `--opt=path`, `/`-containing substring or shell glob that resolves
    into a denied entry (relative to the cwd, `cd`/`pushd` targets and `-C` dirs);
  * a recursive command (find, rg, grep -r, ls -R, tree, tar, rsync, cp -r, ...) whose
    root is an ancestor of a denied entry, unless the command excludes the entry's name
    (`rg -g '!NAME'`, `grep --exclude-dir=NAME`, `find … -prune`, `fd -E NAME`).
It cannot see paths built at run time (`$VAR`, `$(...)`, a script that walks the tree).
"""
import fnmatch
import glob
import json
import os
import posixpath
import re
import shlex
import sys

GLOB = re.compile(r"[*?\[]")
PATHISH = re.compile(r"""[^\s'"`();|&<>,=]*/[^\s'"`();|&<>,=]*""")
SEPARATORS = {";", "&&", "||", "|", "|&", "&", "(", ")", ";;", "\n"}
WRAPPERS = {"sudo", "env", "nohup", "time", "nice", "command", "exec", "stdbuf", "setsid", "xargs", "timeout",
            "caffeinate", "doas"}
SHELLS = {"bash", "sh", "zsh", "dash"}
ALWAYS_RECURSIVE = {"find", "tree", "rg", "fd", "fdfind", "du", "rsync", "ag", "ack", "tar", "7z", "bsdtar"}
# command -> short-flag letters that make it recursive (long form: --recursive)
FLAG_RECURSIVE = {"grep": "rR", "egrep": "rR", "fgrep": "rR", "ls": "R", "cp": "rRa", "scp": "r", "zip": "r",
                  "chmod": "R", "chown": "R"}
# Options whose value is a name pattern, not a path to open; judged by `excludes`/the walk root.
PATTERN_OPTS = {"--exclude", "--exclude-dir", "--ignore", "--ignore-dir", "-I", "-E", "-g", "--glob", "--iglob", "--include", "-name", "-iname", "-path", "-ipath",
                               "-wholename", "-regex"}
DIR_OPTS = {"-C", "--directory"}


class Entry:
    def __init__(self, raw, home):
        path = home + raw[1:] if raw == "~" or raw.startswith("~/") else raw
        if not path.startswith("/"):
            raise ValueError(f"deny-list entry must be absolute or ~/: {raw}")
        path = posixpath.normpath(path)
        parts = path.split("/")
        literal = []
        for part in parts[1:]:
            if GLOB.search(part):
                break
            literal.append(part)
        self.raw = raw
        self.prefix = "/" + "/".join(literal)
        self.name = parts[-1]  # excluding this name at any depth covers the entry; a glob has no safe form
        # Directory-only exclusions (grep --exclude-dir) cover the entry only when it is a real directory.
        self.is_dir = not GLOB.search(path) and os.path.isdir(path)
        real = os.path.realpath(self.prefix)
        variants = {path, posixpath.normpath(real + path[len(self.prefix):])}
        self.regexes = [self._regex(v) for v in variants]
        self.segments = [v.split("/")[1:] for v in variants]

    @staticmethod
    def _regex(path):
        out, i = [], 0
        while i < len(path):
            if path.startswith("/**/", i):
                out.append("(?:/.*)?/")
                i += 4
            elif path.startswith("/**", i) and i + 3 == len(path):
                out.append("(?:/.*)?")
                i += 3
            elif path.startswith("**", i):
                out.append(".*")
                i += 2
            elif path[i] == "*":
                out.append("[^/]*")
                i += 1
            elif path[i] == "?":
                out.append("[^/]")
                i += 1
            else:
                out.append(re.escape(path[i]))
                i += 1
        return re.compile("".join(out))

    def covers(self, path):
        while True:
            if any(r.fullmatch(path) for r in self.regexes):
                return True
            if path == "/":
                return False
            path = posixpath.dirname(path)

    def below(self, root):
        """True when a recursive walk from `root` can reach a path this entry covers.

        Matched segment by segment, so a glob entry (`/tmp/*/NAME`) is reached from its
        literal prefix (`/tmp`) and from any directory a glob segment matches (`/tmp/a`)."""
        root_segs = [s for s in root.split("/") if s]
        return any(_reaches(segs, root_segs) for segs in self.segments)


def _reaches(entry, root):
    if not root or not entry:
        return True  # root is above the entry (walks into it) or inside it
    if entry[0] == "**":
        return _reaches(entry[1:], root) or _reaches(entry, root[1:])
    return fnmatch.fnmatchcase(root[0], entry[0]) and _reaches(entry[1:], root[1:])


class Policy:
    def __init__(self, entries, home, cwd):
        self.entries, self.home, self.cwd = entries, home, cwd

    def expand(self, word):
        if word == "~" or word.startswith("~/"):
            word = self.home + word[1:]
        return word.replace("${HOME}", self.home).replace("$HOME", self.home)

    def resolve(self, word, bases):
        word = self.expand(word)
        if not word:
            return []
        raw = [word] if word.startswith("/") else [posixpath.join(b, word) for b in bases]
        out = []
        for path in raw:
            path = posixpath.normpath(path)
            out.append(path)
            real = os.path.realpath(path)
            if real != path:
                out.append(real)
        return out

    def hit(self, path):
        return next((e for e in self.entries if e.covers(path)), None)

    def hit_glob(self, pattern):
        """A glob operand: the shell expands it, so judge what it can match."""
        if "**" in pattern:  # zsh (the Bash tool's shell) recurses on **
            literal = pattern.split("**", 1)[0]
            root = posixpath.dirname(literal) if not literal.endswith("/") else literal
            for e in self.entries:
                if e.below(root or "/") or e.covers(root or "/"):
                    return e
        for match in glob.glob(pattern):
            e = self.hit(posixpath.normpath(match)) or self.hit(os.path.realpath(match))
            if e:
                return e
        return None

    def judge_path(self, word, bases, expand_globs=True):
        for path in self.resolve(word, bases):
            e = self.hit_glob(path) if expand_globs and GLOB.search(path) else self.hit(path)
            if e:
                return e
        return None


def tokenize(command):
    try:
        lex = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
        lex.whitespace_split = True
        lex.commenters = ""
        return list(lex)
    except ValueError:
        return command.split()


def simple_commands(tokens):
    cmd = []
    for tok in tokens:
        if tok in SEPARATORS:
            if cmd:
                yield cmd
            cmd = []
        else:
            cmd.append(tok)
    if cmd:
        yield cmd


def command_word(cmd):
    i = 0
    while i < len(cmd):
        word = posixpath.basename(cmd[i])
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", cmd[i]) or word in WRAPPERS or cmd[i].startswith("-") \
                or re.fullmatch(r"\d+[smhd]?", cmd[i]):
            i += 1
            continue
        return word, cmd[i + 1:]
    return "", []


def is_recursive(word, args):
    if word in ALWAYS_RECURSIVE:
        return True
    letters = FLAG_RECURSIVE.get(word)
    if not letters:
        return False
    for arg in args:
        if arg == "--recursive" or arg.startswith("--dereference-recursive"):
            return True
        if re.fullmatch(r"-[A-Za-z]+", arg) and any(c in arg for c in letters):
            return True
    return False


# Options that remove a whole directory from the walk, per command, judged with that
# command's own matching. grep's --exclude matches file names only and an rg glob without
# `!` includes, so neither counts; anything not understood here keeps the walk denied.
DIR_EXCLUDES = {
    "rg": ("-g", "--glob", "--iglob"), "grep": ("--exclude-dir",), "egrep": ("--exclude-dir",),
    "fgrep": ("--exclude-dir",), "fd": ("-E", "--exclude"), "fdfind": ("-E", "--exclude"),
    "tar": ("--exclude",), "bsdtar": ("--exclude",), "rsync": ("--exclude",),
    "ag": ("--ignore-dir", "--ignore"), "tree": ("-I",),
}
# rsync applies the first matching rule, so an include given anywhere may win; tar
# --anchored matches only from the member name's start.
OVERRIDES = {"rsync": ("--include", "--include-from", "--filter", "-f", "--files-from"),
             "tar": ("--anchored",), "bsdtar": ("--anchored",)}


# These skip directories only; a file (or a glob entry that may match files) is still read.
DIR_ONLY = {"--exclude-dir", "--ignore-dir"}


def _option_values(args, opts):
    for i, arg in enumerate(args):
        for opt in opts:
            if arg == opt and i + 1 < len(args):
                yield args[i + 1]
            elif arg.startswith(opt + "=") or (len(opt) == 2 and arg.startswith(opt) and len(arg) > 2):
                yield arg[len(opt) + 1:] if arg.startswith(opt + "=") else arg[2:]


def _basename_pattern(value, name):
    """The literal directory name (grep, fd, tar, rsync, ag, tree). Wildcards are not
    accepted: options such as tar --no-wildcards change how they match."""
    return value.rstrip("/") == name


def _rg_excludes(args, name):
    """rg: the last glob that matches wins, so the final glob must be the exclusion."""
    globs = list(_option_values(args, DIR_EXCLUDES["rg"]))
    if not globs or not globs[-1].startswith("!"):
        return False
    value = globs[-1][1:]
    for head in ("**/",):
        while value.startswith(head):
            value = value[len(head):]
    for tail in ("/**", "/"):
        while value.endswith(tail):
            value = value[: -len(tail)]
    return value == name


def _find_excludes(args, name):
    """Only the canonical `find ROOT... -name NAME -prune -o ...` (or `-path '*/NAME'`) form:
    the prune must be the first test so it always runs, and -depth (children first) breaks it."""
    if "-depth" in args or "-d" in args:
        return False
    i = 0
    while i < len(args) and args[i] in ("-H", "-L", "-P"):
        i += 1
    while i < len(args) and not args[i].startswith("-") and args[i] not in ("!", "(", ")"):
        i += 1
    expr = args[i:i + 4]
    if len(expr) < 4 or expr[2] != "-prune" or expr[3] not in ("-o", "-or"):
        return False
    if expr[0] == "-name":
        return expr[1] == name
    if expr[0] in ("-path", "-wholename"):
        return expr[1] in ("*/" + name, "**/" + name)
    return False


def _overrides(word, arg):
    opts = OVERRIDES.get(word, ())
    if arg.split("=")[0] in opts:
        return True
    # rsync -f takes its rule attached (`-f"+ *"`) or as the last flag of a cluster (`-avf`).
    return word == "rsync" and re.match(r"^-[A-Za-z]*f", arg) is not None


def excludes(word, args, entry):
    name = entry.name
    if not name or GLOB.search(name):
        return False
    if word == "find":
        return _find_excludes(args, name)
    if word == "rg":
        return _rg_excludes(args, name)
    if any(_overrides(word, a) for a in args):
        return False
    opts = tuple(o for o in DIR_EXCLUDES.get(word, ()) if entry.is_dir or o not in DIR_ONLY)
    for value in _option_values(args, opts):
        parts = value.split("|") if word == "tree" else [value]
        if any(_basename_pattern(part, name) for part in parts):
            return True
    return False


def judge_bash(policy, command, cwd, depth=0):
    tokens = tokenize(command)
    bases = [cwd]
    for i, tok in enumerate(tokens[:-1]):
        if tok in ("cd", "pushd") or tok in DIR_OPTS:
            for path in policy.resolve(tokens[i + 1], [cwd]):
                if path not in bases:
                    bases.append(path)
    for i, tok in enumerate(tokens):
        if tok in SEPARATORS or tok.startswith("!") or (i and tokens[i - 1] in PATTERN_OPTS) \
                or any(tok.startswith(o + "=") for o in PATTERN_OPTS):
            continue
        words = {tok: True}
        for part in [*tok.split("=")[1:], *PATHISH.findall(tok)]:
            words.setdefault(part, False)
        for word, operand in words.items():
            e = policy.judge_path(word, bases, expand_globs=operand)
            if e:
                return f"deny `{word}` is inside {e.raw}"
    for cmd in simple_commands(tokens):
        word, args = command_word(cmd)
        if word in SHELLS and "-c" in args and depth < 3:
            idx = args.index("-c")
            if idx + 1 < len(args):
                verdict = judge_bash(policy, args[idx + 1], cwd, depth + 1)
                if verdict != "allow":
                    return verdict
            continue
        if not is_recursive(word, args):
            continue
        roots = []
        for arg in args:
            if arg.startswith("-"):
                continue
            roots += [p for p in policy.resolve(arg, bases) if os.path.isdir(p)]
        roots = roots or bases
        for entry in policy.entries:
            if any(entry.below(r) for r in roots) and not excludes(word, args, entry):
                return (f"deny `{word}` walks a tree that contains {entry.raw}; narrow the root or exclude it "
                        f"(rg -g '!{entry.name}', grep --exclude-dir={entry.name}, "
                        f"find … -path '*/{entry.name}' -prune -o …, fd -E {entry.name})")
    return "allow"


def judge(payload, entries, home):
    cwd = payload.get("cwd") or os.getcwd()
    policy = Policy(entries, home, cwd)
    tool = payload.get("tool_name", "")
    inp = payload.get("tool_input") or {}
    if tool == "Bash":
        return judge_bash(policy, inp.get("command", ""), cwd)
    if tool in ("Glob", "Grep"):
        root = inp.get("path") or cwd
        e = policy.judge_path(root, [cwd])
        if e:
            return f"deny {tool} path is inside {e.raw}"
        pattern = inp.get("pattern", "") if tool == "Glob" else ""
        target = posixpath.join(root, policy.expand(pattern)) if pattern else root
        e = policy.judge_path(target, [cwd]) if pattern else None
        if e:
            return f"deny {tool} pattern reaches {e.raw}"
        for path in policy.resolve(root, [cwd]):
            for entry in entries:
                if entry.below(path) and (tool == "Grep" or "**" in pattern):
                    return f"deny {tool} under {path} would reach {entry.raw}; search a narrower path"
        return "allow"
    for key in ("file_path", "notebook_path", "path"):
        if isinstance(inp.get(key), str):
            e = policy.judge_path(inp[key], [cwd])
            if e:
                return f"deny {tool} target is inside {e.raw}"
    return "allow"


def load(path, home):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = [ln.strip() for ln in f]
    except FileNotFoundError:
        return []
    entries = []
    for line in lines:
        if not line or line.startswith("#"):
            continue
        try:
            entries.append(Entry(line, home))
        except ValueError:
            print(f"skipped deny-list entry (not ~/ or absolute): {line}", file=sys.stderr)
    return entries


def main():
    deny_list, home = sys.argv[1], sys.argv[2].rstrip("/") or "/"
    entries = load(deny_list, home)
    if not entries:
        print("allow")
        return
    payload = json.load(sys.stdin)
    print(judge(payload, entries, home))


if __name__ == "__main__":
    main()
