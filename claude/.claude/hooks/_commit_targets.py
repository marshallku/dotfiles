#!/usr/bin/env python3
"""Decide which repositories a Bash command would commit in, for pre-commit-gate.sh.

Usage: _commit_targets.py <cwd>  (command on stdin)
Prints `none` when the command creates no commit, otherwise one `dir <path>` line
per directory whose repository must pass the gate.

The precise path only accepts a flat list of simple commands joined by `&&`, `;`,
`|` or newlines. Anything it does not fully understand (subshells, command or
process substitution, `||`, `&`, heredocs, shell runners, unknown programs that
carry `save.sh` as an argument, non-literal `cd`) takes the fallback: the hook cwd
plus every literal `cd` target, judged as before this helper existed. So the
helper can only narrow a false positive, never let a commit skip the gate.
"""
import os
import re
import shlex
import sys

GIT_COMMIT_RE = re.compile(r"\bgit\b.*\bcommit\b", re.S)
# block-raw-git.sh's shape: `git`, option tokens (with optional values), then the `commit` subcommand.
GIT_INVOCATION_RE = re.compile(
    r"\bgit\b(\s+-\S+(\s+(\"[^\"]*\"|'[^']*'|[^-\s]\S*))?)*\s+commit([\s;&|\"']|$)")
SEPARATORS = {"&&", ";", "|", "|&"}
FALLBACK_TOKENS = {"||", "&", "(", ")", ";;"}
GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
# Programs that only read their arguments: `save.sh` among them is a file name, not a call.
READERS = {
    "grep", "egrep", "fgrep", "rg", "ag", "cat", "head", "tail", "less", "more", "wc", "ls", "stat",
    "file", "diff", "cmp", "echo", "printf", "jq", "bat", "nl", "sort", "uniq", "cut", "tr", "test", "[",
    "true", "false", "which", "type", "readlink", "realpath", "basename", "dirname", "shasum", "md5", "md5sum",
}


# Reader options whose value is a program the reader runs.
EXEC_OPTIONS = {"--pre", "--compress-program", "--use-compress-program", "--diff-program", "--external-diff"}
HEREDOC = " __heredoc__ "
# Besides readers, the only programs a heredoc-carrying command may run: they store or
# route text, they never execute it.
HEREDOC_SINKS = {"cd", "tee", "mkdir"}


class Fallback(Exception):
    pass


def expand(word, home):
    if word == "~" or word.startswith("~/"):
        word = home + word[1:]
    for var in ("${HOME}", "$HOME"):
        if word.startswith(var):
            word = home + word[len(var):]
    return word


def cut_heredoc(cmd, i):
    """Replace a quoted-delimiter heredoc at cmd[i] (`<<'EOF'` … `EOF`) with a placeholder word.

    A quoted delimiter means no expansion, so the body is inert text for whatever reads it;
    precise() then requires every program in the command to be a pure reader. An unquoted
    delimiter (the body expands `$(…)`), a here-string or an unterminated body falls back.
    """
    m = re.compile(r"<<(-?)[ \t]*(?:'([^'\n]+)'|\"([^\"\n]+)\")").match(cmd, i)
    if not m:
        raise Fallback
    strip_tabs, delim = m.group(1) == "-", m.group(2) or m.group(3)
    line_end = cmd.find("\n", m.end())
    if line_end < 0:
        raise Fallback
    pos = line_end + 1
    while pos <= len(cmd):
        end = cmd.find("\n", pos)
        line = cmd[pos:] if end < 0 else cmd[pos:end]
        if (line.lstrip("\t") if strip_tabs else line) == delim:
            rest = "" if end < 0 else cmd[end:]
            return cmd[:i] + HEREDOC + cmd[m.end():line_end] + rest
        if end < 0:
            break
        pos = end + 1
    raise Fallback


def scan(cmd):
    """Normalise unquoted newlines to `;` and reject constructs that run code from inside words.

    Returns (normalised command, whether a heredoc body was cut out).
    """
    out, quote, i, heredoc = [], None, 0, False
    while i < len(cmd):
        c = cmd[i]
        nxt = cmd[i + 1] if i + 1 < len(cmd) else ""
        if quote == "'":
            if c == "'":
                quote = None
        elif c == "\\":
            out.append(c + nxt)
            i += 2
            continue
        elif c == "`" or (c == "$" and nxt == "("):
            raise Fallback
        elif quote == '"':
            if c == '"':
                quote = None
        elif c in "'\"":
            quote = c
        elif c in "<>" and nxt == "(":
            raise Fallback
        elif c == "<" and nxt == "<":
            cmd = cut_heredoc(cmd, i)
            heredoc = True
            continue
        elif c == "\n":
            out.append(" ; ")
            i += 1
            continue
        out.append(c)
        i += 1
    if quote:
        raise Fallback
    return "".join(out), heredoc


def split_commands(cmd):
    text, heredoc = scan(cmd)
    lex = shlex.shlex(text, posix=True, punctuation_chars="();<>|&")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    try:
        tokens = list(lex)
    except ValueError:
        raise Fallback
    commands, words, sep = [], [], None
    skip_next = False
    for tok in tokens:
        if skip_next:
            skip_next = False
            continue
        # Only an operator token (punctuation alone) opens a subshell; `"fix: x (y)"` is one word.
        if tok in FALLBACK_TOKENS or (set(tok) <= set("();<>|&") and ("(" in tok or ")" in tok)):
            raise Fallback
        if tok in SEPARATORS:
            if words:
                commands.append((sep, words))
            words, sep = [], tok
            continue
        # A redirection (`>`, `>>`, `2>&1` lexes as `2` `>&` `1`): its target is a file, not a word.
        if set(tok) <= set("<>&"):
            skip_next = True
            continue
        words.append(tok)
    if words:
        commands.append((sep, words))
    return commands, heredoc


def program_of(words):
    i = 0
    while i < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[i]):
        i += 1
    return i


def git_commit_dirs(args, home):
    """Return (is_commit, [-C paths in order]) for the words after `git`.

    Repeated `-C` options compose (`-C /a -C b` is /a/b). A `-C` that expands at
    runtime, or `--git-dir`/`--work-tree`, cannot be resolved here -> Fallback.
    """
    cdirs, i = [], 0
    while i < len(args):
        a = args[i]
        if a.split("=", 1)[0] in ("--git-dir", "--work-tree"):
            raise Fallback
        if a in GIT_OPTS_WITH_ARG:
            if a == "-C" and i + 1 < len(args):
                target = expand(args[i + 1], home)
                if "$" in target:
                    raise Fallback
                cdirs.append(target)
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        return a == "commit", cdirs
    return False, cdirs


def mentions_commit(words):
    joined = " ".join(words)
    return "save.sh" in joined or bool(GIT_COMMIT_RE.search(joined))


def reader_is_inert(name, args):
    """A reader stays exempt only while nothing it is told to execute mentions a commit.

    Readers that run a program for an option (`rg --pre`, `sort --compress-program`) execute that
    value; file operands and ordinary flags (`cat -n ~/save.sh`) are inert. (sed is not a reader at
    all: GNU `e` runs its script, which can sit in any argument, stdin form included.)
    """
    for idx, word in enumerate(args):
        prev = args[idx - 1] if idx else ""
        if (prev in EXEC_OPTIONS or word.split("=", 1)[0] in EXEC_OPTIONS) and mentions_commit([word]):
            return False
    return True


def sed_prints_lines_only(args):
    """`sed -n 1,40p FILE…` — the one sed shape that provably runs nothing (no room for GNU `e`)."""
    return (len(args) >= 3 and args[0] == "-n" and re.fullmatch(r"\d+(,\d+)?p", args[1]) is not None
            and all(not a.startswith("-") for a in args[2:]))


def resolve(base, target):
    return os.path.normpath(target if os.path.isabs(target) else os.path.join(base, target))


def precise(cmd, cwd, home):
    commands, heredoc = split_commands(cmd)
    if heredoc:
        # The body never reaches a shell unless some program here is one: allow pure readers only.
        for _, words in commands:
            start = program_of(words)
            if start >= len(words):
                continue
            name = os.path.basename(expand(words[start], home))
            if name == "git" and not git_commit_dirs(words[start + 1:], home)[0]:
                continue
            if name in HEREDOC_SINKS or (name in READERS and reader_is_inert(name, words[start + 1:])):
                continue
            raise Fallback
    ctx = {cwd}
    chain_points = [set(ctx)]
    targets = []
    for idx, (sep, words) in enumerate(commands):
        nxt_sep = commands[idx + 1][0] if idx + 1 < len(commands) else None
        if sep == ";":
            ctx = set().union(*chain_points)
            chain_points = [set(ctx)]
        start = program_of(words)
        if start >= len(words):
            continue
        prog, args = expand(words[start], home), words[start + 1:]
        name = os.path.basename(prog)
        in_pipeline = sep in ("|", "|&") or nxt_sep in ("|", "|&")
        if name == "cd":
            target = expand(args[0], home) if len(args) == 1 else "$"
            if "$" in target or target == "-":
                raise Fallback
            if in_pipeline:
                continue
            ctx = {resolve(d, target) for d in ctx}
            chain_points.append(set(ctx))
            continue
        if name in ("pushd", "popd"):
            raise Fallback
        if name == "save.sh":
            targets.extend(ctx)
            continue
        if name == "git":
            is_commit, cdirs = git_commit_dirs(args, home)
            if is_commit:
                for d in ctx:
                    for c in cdirs:
                        d = resolve(d, c)
                    targets.append(d)
            continue
        if name in READERS and reader_is_inert(name, args):
            continue
        if name == "sed" and sed_prints_lines_only(args):
            continue
        # Shell runners, wrappers (env, timeout, nohup, sudo …) and unknown programs: any mention may run.
        if mentions_commit(args):
            raise Fallback
    return targets


def fallback_targets(cmd, cwd, home):
    dirs = [cwd]
    for m in re.finditer(r"(?:^|[;&|(\s])cd\s+(\"[^\"]*\"|'[^']*'|[^\s;&|)]+)", cmd):
        target = expand(m.group(1).strip("\"'"), home)
        if "$" not in target and target != "-":
            dirs.append(resolve(cwd, target))
    return dirs


def main():
    cwd = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    cmd = sys.stdin.read()
    home = os.environ.get("HOME", "")
    if "save.sh" not in cmd and not GIT_COMMIT_RE.search(cmd):
        print("none")
        return
    try:
        targets = precise(cmd, cwd, home)
    except Fallback:
        # The pre-helper trigger plus block-raw-git's `git [opts] commit`: never looser than before.
        old_trigger = "save.sh" in cmd or "git commit" in cmd or bool(GIT_INVOCATION_RE.search(cmd))
        targets = fallback_targets(cmd, cwd, home) if old_trigger else []
    if not targets:
        print("none")
        return
    seen = []
    for t in targets:
        if t not in seen:
            seen.append(t)
            print(f"dir {t}")


if __name__ == "__main__":
    main()
