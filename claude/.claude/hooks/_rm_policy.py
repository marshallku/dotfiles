#!/usr/bin/env python3
"""Classify the recursive deletes in a Bash command for careful-with-judge.sh.

Usage: _rm_policy.py <cwd> <home>   (command on stdin)
Prints one line: `none`, `allow`, `ask <why>` or `deny <why>`.

The shell hook it replaces split the command on whitespace, so it judged words that
were never rm operands: heredoc bodies, quoted code, `ssh` remote commands and
`find -exec rm {}`. It also could not see that `S=/tmp/x; rm -rf $S/y` deletes
scratch. Replaying 1,487 recursive-rm commands from real sessions gave 67 deny and
1,242 ask verdicts, nearly all for scratch paths. This walks the command the way the
shell would: it tracks `cd` and variable assignments, recurses into `bash -c`,
`ssh host CMD`, `trap`, `eval`, `$(...)` and heredocs fed to a shell, and resolves
each operand to a path before judging it.

Anything it cannot resolve is `ask`, never `allow`.
"""
import os
import posixpath
import re
import shlex
import sys

SEPARATORS = {";", "&&", "||", "|", "|&", "&", "(", ")", ";;"}
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "}", "fi", "done", "esac"}
WRAPPERS = {"sudo", "env", "nohup", "time", "nice", "command", "exec", "stdbuf", "setsid", "caffeinate"}
SHELLS = {"bash", "sh", "zsh", "dash"}
SSH_VALUE_OPTS = set("bcDEeFIiJLlmOoPpQRSWw")
GLOB = re.compile(r"[*?\[]")
# $NAME or ${...}. Inside braces only ${NAME}, ${NAME?msg}, ${NAME-def} and ${NAME=def} (with
# or without `:`) keep the value of a set NAME; every other operation (${NAME+w}, ${NAME#p},
# ${NAME/a/b}, ...) changes it, so the operand is unresolved.
VAR = re.compile(r"\$(?:\{([^}]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
KEEPS_VALUE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(?:(:?)[-?=].*)?$", re.S)
SHELL_VALUE_OPTS = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
PURE_GLOB = re.compile(r"^[.*?]*\*[.*?]*$")  # `*`, `.*`, `*.*`: every entry of the directory
ARTIFACTS = {"node_modules", "dist", "build", "target", ".next", "coverage", "__pycache__", ".cache", ".turbo",
             "DerivedData", ".pytest_cache", ".mypy_cache", ".gradle"}
TEMP_ROOTS = ("/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/var/folders/",
              "/private/var/folders/", "/dev/shm/")
SYSTEM_DIRS = {"/usr", "/etc", "/bin", "/sbin", "/var", "/opt", "/lib", "/lib64", "/boot", "/srv", "/root",
               "/System", "/Library", "/Applications", "/private", "/Users", "/home", "/Volumes", "/nix"}
DEFAULT_MKTEMP = "/tmp/mktemp.XXXXXXXX"  # where `mktemp` with no template puts its file
REMOTE_HOME = "\x00remote-home\x00"
MAX_DEPTH = 6


class Verdicts:
    def __init__(self):
        self.deny, self.ask, self.allow = [], [], 0


def split_heredocs(text):
    """Cut heredoc bodies out of `text`. Returns (text without bodies, [body per `<<`]).

    The `<<WORD` operator stays in place so the command that owns the body can be found;
    bodies are numbered in order of appearance.
    """
    out, bodies, quote, i, pending = [], [], None, 0, []
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\" and quote == '"':
                out.append(text[i:i + 2])
                i += 2
                continue
            if c == quote:
                quote = None
            out.append(c)
            i += 1
            continue
        if c in "'\"":
            quote = c
        elif c == "\\":
            out.append(text[i:i + 2])
            i += 2
            continue
        elif text.startswith("<<", i) and not text.startswith("<<<", i):
            m = re.compile(r"<<(-?)[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2").match(text, i)
            if m:
                pending.append((m.group(1) == "-", m.group(3), len(bodies)))
                bodies.append("")
                out.append(f"<<__HEREDOC{len(bodies) - 1}__")
                i = m.end()
                continue
        elif c == "\n" and pending:
            out.append(c)
            i += 1
            for strip, delim, idx in pending:
                lines = []
                while i <= len(text):
                    end = text.find("\n", i)
                    line = text[i:] if end < 0 else text[i:end]
                    i = len(text) + 1 if end < 0 else end + 1
                    if (line.lstrip("\t") if strip else line) == delim:
                        break
                    lines.append(line)
                bodies[idx] = "\n".join(lines)
            pending = []
            continue
        out.append(c)
        i += 1
    return "".join(out), bodies


def split_substitutions(text):
    """Replace `$(...)` and backquotes with placeholders. Returns (text, [inner command])."""
    out, inner, i, quote = [], [], 0, None
    while i < len(text):
        c = text[i]
        if quote == "'":
            out.append(c)
            quote = None if c == "'" else quote
            i += 1
            continue
        if c == "\\":
            out.append(text[i:i + 2])
            i += 2
            continue
        if c == "'" and quote is None:
            quote = "'"
        elif c == '"':
            quote = None if quote == '"' else '"'
        if text.startswith("$(", i) and not text.startswith("$((", i):
            depth, j = 1, i + 2
            while j < len(text) and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            inner.append(text[i + 2:j - 1])
            out.append(f"__SUBST{len(inner) - 1}__")
            i = j
            continue
        if c == "`":
            j = text.find("`", i + 1)
            j = len(text) if j < 0 else j
            inner.append(text[i + 1:j])
            out.append(f"__SUBST{len(inner) - 1}__")
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out), inner


def tokenize(text):
    lex = shlex.shlex(text.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = "#"
    return list(lex)


def entry_cwds(ok, fail, sep):
    """Directories the next command may run in, given how it is joined to the previous one."""
    if sep == "&&":
        return ok
    if sep == "||":
        return fail
    return ok | fail


class Walker:
    def __init__(self, home):
        self.home = home
        self.verdicts = Verdicts()

    def walk(self, text, cwds, env, remote=False, depth=0):
        """Judge every command in `text`. `cwds` is the set of directories it may start in
        (None = unknown): a `cd` that may fail or be skipped leaves both possibilities open."""
        if depth > MAX_DEPTH:
            self.verdicts.ask.append("nesting too deep to check")
            return
        text, bodies = split_heredocs(text)
        text, substs = split_substitutions(text)
        for inner in substs:
            self.walk(inner, cwds, dict(env), remote, depth + 1)
        try:
            tokens = tokenize(text)
        except ValueError:
            if re.search(r"\brm\b", text):
                self.verdicts.ask.append("command could not be parsed")
            return
        # (ok, fail): directories after the chain so far succeeded / failed. `X && Y` fails
        # when either fails; `X || Y` succeeds when either succeeds; `;` starts a new chain.
        ok = fail = frozenset(cwds)
        sep, words, subshells = ";", [], []
        for token in tokens + [";"]:
            if token not in SEPARATORS:
                if words or token not in KEYWORDS:
                    words.append(token)
                continue
            if words:
                y_ok, y_fail = self.command(words, entry_cwds(ok, fail, sep), env, substs, bodies, remote, depth)
                if sep == "&&":
                    ok, fail = y_ok, fail | y_fail
                elif sep == "||":
                    ok, fail = ok | y_ok, y_fail
                else:
                    ok, fail = y_ok, y_fail
                words = []
            if token == "(":
                subshells.append(entry_cwds(ok, fail, sep))
                ok = fail = subshells[-1]
                sep = ";"
            elif token == ")":
                ok = fail = subshells.pop() if subshells else ok | fail  # a subshell's cd does not leak
            else:
                sep = token

    def command(self, words, cwds, env, substs, bodies, remote, depth):
        """Judge one simple command; returns the directory sets after it succeeds / fails."""
        assignments = []
        while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
            assignments.append(words.pop(0))
        if words and words[0] in {"export", "local", "declare", "readonly", "typeset"}:
            assignments.extend(w for w in words[1:] if "=" in w and not w.startswith("-"))
            words = []
        if not words:
            for item in assignments:
                name, value = item.split("=", 1)
                env[name] = self.assigned(value, env, substs)
            return cwds, cwds
        while words and (os.path.basename(words[0]) in WRAPPERS or re.match(r"^[A-Za-z_]\w*=", words[0])):
            prog = os.path.basename(words.pop(0))
            while words and words[0].startswith("-"):
                words.pop(0)
            if prog == "timeout" and words:
                words.pop(0)
        if words and os.path.basename(words[0]) in {"timeout", "gtimeout"}:
            words = words[1:]
            while words and (words[0].startswith("-") or re.match(r"^[0-9.]+[smhd]?$", words[0])):
                words.pop(0)
        if not words:
            return cwds, cwds
        prog, args = os.path.basename(words[0]), words[1:]
        heredoc = [bodies[int(m.group(1))] for a in args for m in [re.match(r"^<<__HEREDOC(\d+)__$", a)] if m]
        if prog == "cd":
            target = next((a for a in args if not a.startswith("-")), "~")
            moved = set()
            for cwd in cwds:
                resolved = self.resolve(target, cwd, env, substs, remote)
                moved.add(resolved if resolved and not GLOB.search(resolved) else None)
            return frozenset(moved), cwds
        if prog == "rm":
            self.rm(args, cwds, env, substs, remote)
        elif prog == "find":
            self.find(args, cwds, env, substs, remote)
        elif prog == "xargs" and any(os.path.basename(a) == "rm" for a in args):
            rm_at = next(i for i, a in enumerate(args) if os.path.basename(a) == "rm")
            if recursive_flags(args[rm_at + 1:]):
                self.verdicts.ask.append("xargs rm -r: operands come from stdin")
        elif prog in SHELLS:
            # `bash -c CMD`, `bash -lc CMD`, `sh -ec CMD`: CMD is the first operand after the options.
            options, command, i = [], None, 0
            while i < len(args):
                a = args[i]
                if a in SHELL_VALUE_OPTS:
                    i += 2
                    continue
                if a == "--" or not a.startswith(("-", "+")):
                    command = args[i + 1] if a == "--" and i + 1 < len(args) else (None if a == "--" else a)
                    break
                options.append(a)
                i += 1
            if any(re.match(r"^-[A-Za-z]*c[A-Za-z]*$", o) for o in options):
                if command is None:
                    self.verdicts.ask.append(f"{prog} -c without a readable command")
                else:
                    self.walk(command, cwds, dict(env), remote, depth + 1)
            for body in heredoc:
                self.walk(body, cwds, dict(env), remote, depth + 1)
        elif prog == "ssh":
            command = ssh_command(args)
            for text in ([command] if command else []) + heredoc:
                self.walk(text, {None}, {}, True, depth + 1)
        elif prog in {"eval", "trap"}:
            text = args[0] if prog == "trap" and args else " ".join(args)
            self.walk(text, cwds, dict(env), remote, depth + 1)
        return cwds, cwds

    def assigned(self, value, env, substs):
        m = re.match(r"^__SUBST(\d+)__$", value)
        if m:
            return self.mktemp_path(substs[int(m.group(1))], env, substs)
        return self.expand(value, env, substs, remote=False)

    def mktemp_path(self, inner, env, substs):
        """Where `$(mktemp ...)` creates its file, so `rm -rf "$D/../.."` is judged by path."""
        try:
            words = shlex.split(inner)
        except ValueError:
            return None
        if not words or os.path.basename(words[0]) != "mktemp":
            return None
        directory, template, args = None, None, words[1:]
        for i, a in enumerate(args):
            if a in {"-p", "--tmpdir"} and i + 1 < len(args):
                directory = args[i + 1]
            elif a.startswith("--tmpdir="):
                directory = a.split("=", 1)[1]
            elif not a.startswith("-") and (i == 0 or args[i - 1] not in {"-p", "--tmpdir", "--suffix"}):
                template = a
        if template and "/" in template:
            return self.expand(template, env, substs, remote=False)
        if "-t" in args or any(re.match(r"^-[A-Za-z]*t", a) for a in args):
            directory = directory or "/tmp"  # -t: the template is placed in TMPDIR
        if template and not directory:
            return None  # a bare template is created relative to the cwd at that moment
        if directory:
            base = self.expand(directory, env, substs, remote=False)
            return None if base is None else posixpath.join(base, template or "tmp.XXXXXXXX")
        return DEFAULT_MKTEMP

    def expand(self, word, env, substs, remote):
        """Expand `~` and `$VAR`; None when any part cannot be known statically."""
        if "__SUBST" in word:
            return None
        home = REMOTE_HOME if remote else self.home
        if word == "~" or word.startswith("~/"):
            word = home + word[1:]
        unknown = []

        def sub(m):
            if m.group(1) is not None:
                keeps = KEEPS_VALUE.match(m.group(1))
                if not keeps:
                    unknown.append(m.group(1))
                    return ""
                name = keeps.group(1)
                if keeps.group(2) and env.get(name) == "":
                    unknown.append(name)  # `:-`/`:=` use their fallback word for an empty value
                    return ""
            else:
                name = m.group(2)
            if name == "HOME":
                return home
            if name == "TMPDIR" and not remote:
                return env.get(name) or "/tmp"
            value = env.get(name)
            if value is None:
                unknown.append(name)
                return ""
            return value

        word = VAR.sub(sub, word)
        return None if unknown or "$" in word else word

    def resolve(self, word, cwd, env, substs, remote):
        value = self.expand(word, env, substs, remote)
        if value is None:
            return None
        if value.startswith("/") or value.startswith(REMOTE_HOME):
            return normalize(value)
        if cwd is None:
            return None
        return normalize(posixpath.join(cwd, value))

    def rm(self, args, cwds, env, substs, remote):
        options, operands = rm_args(args)
        if not recursive_flags(options):
            return
        if not operands:
            self.verdicts.ask.append("rm -r without operands")
        for word in operands:
            self.judge(word, cwds, env, substs, remote)

    def find(self, args, cwds, env, substs, remote):
        deletes = "-delete" in args
        for i, a in enumerate(args):
            if a in {"-exec", "-execdir"} and i + 1 < len(args) and os.path.basename(args[i + 1]) == "rm":
                end = next((j for j in range(i + 2, len(args)) if args[j] in {";", "+", "\\;"}), len(args))
                deletes |= recursive_flags(args[i + 2:end])
        if not deletes:
            return
        roots = []
        for a in args:
            if a.startswith("-") or a in {"(", "!", ")"}:
                break
            roots.append(a)
        for word in roots or ["."]:
            # find deletes only what its expression matches, so even a home root is a question.
            self.judge(word, cwds, env, substs, remote, worst="ask")

    def judge(self, word, cwds, env, substs, remote, worst="deny"):
        """Record the worst verdict for `word` over every directory it may be relative to."""
        bare = word in {".", "./", "..", "../", "*", "./*"}
        home = REMOTE_HOME if remote else self.home
        verdicts = []
        for cwd in cwds:
            path = self.resolve(word, cwd, env, substs, remote)
            if path is None:
                verdicts.append(("deny" if bare else "ask", f"{word} in an unknown directory" if bare
                                 else f"cannot resolve {word}"))
                continue
            verdict = classify(path, home)
            if bare and verdict == "ask":
                verdict = "deny"  # `rm -rf .` / `*` wipes a whole working directory that is not scratch
            verdicts.append((verdict, display(path, self.home)))
        rank = {"allow": 0, "ask": 1, "deny": 2}
        verdict, where = max(verdicts, key=lambda v: rank[v[0]])
        if verdict == "deny" and worst == "ask":
            verdict = "ask"
        if verdict == "deny":
            self.verdicts.deny.append(where)
        elif verdict == "ask":
            self.verdicts.ask.append(where)
        else:
            self.verdicts.allow += 1


def rm_args(args):
    options, operands, done = [], [], False
    for a in args:
        if a.startswith("<<__HEREDOC") or a.startswith((">", "2>", "<")):
            continue
        if not done and a == "--":
            done = True
        elif not done and a.startswith("-") and a != "-":
            options.append(a)
        else:
            operands.append(a)
    return options, operands


def recursive_flags(options):
    return any(o == "--recursive" or (re.match(r"^-[A-Za-z]+$", o) and re.search("[rR]", o)) for o in options)


def ssh_command(args):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        flag = args[i]
        i += 2 if len(flag) == 2 and flag[1] in SSH_VALUE_OPTS else 1
    rest = args[i + 1:]  # args[i] is the host
    return " ".join(rest)


def normalize(path):
    prefix = REMOTE_HOME if path.startswith(REMOTE_HOME) else ""
    body = path[len(prefix):]
    body = posixpath.normpath(body) if body else body
    if prefix:
        body = "" if body in {".", ""} else body if body.startswith("/") else "/" + body
        return prefix + body
    return "/" if body == "//" else body


def classify(path, home):
    """deny for a root that must never be bulk-deleted, allow for scratch/artifacts, else ask."""
    parent, base = posixpath.split(path)
    container = parent if PURE_GLOB.match(base) else path
    precious = {"/", home, posixpath.dirname(home)} | SYSTEM_DIRS
    if container in precious or (container + "/").rstrip("/") in precious:
        return "deny"
    if container.startswith(REMOTE_HOME) and container in {REMOTE_HOME, REMOTE_HOME + "/"}:
        return "deny"
    if any(path.startswith(root) and len(path) > len(root) for root in TEMP_ROOTS):
        return "allow"
    parts = path.split("/")
    if any(p in ARTIFACTS for p in parts[:-1] + ([parts[-1]] if not GLOB.search(parts[-1]) else [])):
        return "allow"
    if "/.claude/state/" in path + "/" or re.search(r"\.(count|log|tmp)$", path):
        return "allow"
    return "ask"


def display(path, home):
    path = path.replace(REMOTE_HOME, "remote:~")
    return "~" + path[len(home):] if home and path.startswith(home + "/") else path


def main():
    cwd = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
    home = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~")
    walker = Walker(home.rstrip("/") or "/")
    walker.walk(sys.stdin.read(), {cwd}, {})
    v = walker.verdicts
    if v.deny:
        print("deny " + ", ".join(v.deny[:3]))
    elif v.ask:
        print("ask " + ", ".join(v.ask[:3]))
    elif v.allow:
        print("allow")
    else:
        print("none")


if __name__ == "__main__":
    main()
