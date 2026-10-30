#!/usr/bin/env python3
"""Attribution policy for GitHub-side commits (`gh pr merge|create|edit`, `gh api .../merge`).

GitHub writes the squash/merge commit itself, so the git commit-msg hook never sees it.
Its default squash message (COMMIT_MESSAGES) concatenates the branch commits and appends
a `Co-authored-by:` trailer for every other author and every trailer found in them, so a
merge without an explicit body records co-authors even when the PR text is clean.

Reads a Bash command on stdin, argv[1] = its cwd. Prints a deny reason, or nothing.
"""

import json
import os
import re
import sys

ATTRIBUTION = re.compile(r"^[^0-9A-Za-z]*(co-authored-by\s*:|generated with \[?claude)", re.I | re.M)

# gh pr merge|create|edit flags that take a value.
VALUE_FLAGS = {"--body", "--body-file", "--subject", "--title", "--author-email", "--match-head-commit",
               "--base", "--head", "--repo", "--reviewer", "--assignee", "--label", "--project",
               "--milestone", "--template"}
MERGE_SHORT_VALUES = set("bFtAR")
EDIT_SHORT_VALUES = set("bFtBHRralpmT")


PUNCTUATION = ";&|()\n"
GH_WRITE = re.compile(r"\bgh\b.*\b(pr\b.*\b(merge|create|edit)|api)\b", re.S)
UNREADABLE = ("A message file the hook cannot read (`-` / stdin, or a missing path) can't be checked "
              "for attribution. Pass the text inline, or a file that exists before the command runs.")


class Unreadable(Exception):
    pass


def read_file(path, cwd):
    """A message file's text; Unreadable when it cannot be checked (stdin, missing path)."""
    if path == "-":
        raise Unreadable
    try:
        with open(os.path.join(cwd, os.path.expanduser(path)), encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        raise Unreadable


ANSI_C = re.compile(r"\\(x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}|[0-7]{1,3}|c.|.)", re.S)
ANSI_C_SIMPLE = {"a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n", "r": "\r",
                 "t": "\t", "v": "\v"}


def ansi_c(text):
    """Decode a `$'…'` body the way bash does (variable-width hex/octal/unicode escapes)."""
    def escape(match):
        seq = match.group(1)
        if seq[0] in "xuU" and len(seq) > 1:
            return chr(int(seq[1:], 16))
        if seq[0] in "01234567":
            return chr(int(seq, 8) & 0xFF)
        if seq[0] == "c" and len(seq) == 2:
            return chr(ord(seq[1].upper()) & 0x1F)
        return ANSI_C_SIMPLE.get(seq, seq if seq in "\\'\"?" else "\\" + seq)
    return ANSI_C.sub(escape, text)


def tokenize(command):
    """Yield (text, is_operator) the way bash splits words. Operators are unquoted only, so
    `--body ""` or `--body ";"` stay words; an unquoted backslash-newline joins the words."""
    word, in_word, quote, i = [], False, None, 0
    while i < len(command):
        c = command[i]
        if quote == "'":
            if c == "'":
                quote = None
            else:
                word.append(c)
        elif quote == '"':
            if c == '"':
                quote = None
            elif c == "\\" and command[i + 1:i + 2] in ('"', "\\", "$", "`", "\n"):
                i += 1
                if command[i] != "\n":
                    word.append(command[i])
            else:
                word.append(c)
        elif c == "\\":
            i += 1
            if command[i:i + 1] not in ("", "\n"):
                word.append(command[i])
                in_word = True
        elif c == "$" and command[i + 1:i + 2] == "'":
            # ANSI-C quoting: bash sends `$'a\nb'` with a real newline, so decode it before checking.
            end = i + 2
            while end < len(command) and command[end] != "'":
                end += 2 if command[end] == "\\" else 1
            if end >= len(command):
                raise ValueError("unterminated quote")
            word.append(ansi_c(command[i + 2:end]))
            in_word, i = True, end
        elif c in "'\"":
            quote, in_word = c, True
        elif c in " \t\r" or c in PUNCTUATION:
            if in_word:
                yield "".join(word), False
            word, in_word = [], False
            if c in "()\n":
                yield c, True
            elif c in PUNCTUATION:
                # `&&`, `||`, `;;`: one operator per run of the same character.
                j = i
                while command[j + 1:j + 2] == c:
                    j += 1
                yield command[i:j + 1], True
                i = j
        else:
            word.append(c)
            in_word = True
        i += 1
    if quote:
        raise ValueError("unterminated quote")
    if in_word:
        yield "".join(word), False


def segments(command, cwd):
    """Yield (tokens, cwd) per simple command, following `cd` so relative files resolve.
    A `cd` inside `( … )` / `$( … )`, or in a pipeline or background job, runs in a subshell
    and does not move the commands after it."""
    current, stack, previous = [], [], None
    for text, is_operator in list(tokenize(command)) + [(";", True)]:
        if not is_operator:
            current.append(text)
            continue
        if current[:1] == ["cd"] and len(current) == 2:
            if previous not in ("|", "&") and text not in ("|", "&"):
                cwd = os.path.join(cwd, os.path.expanduser(current[1]))
        elif current:
            yield current, cwd
        current, previous = [], text
        if text == "(":
            stack.append(cwd)
        elif text == ")" and stack:
            cwd = stack.pop()


def parse_flags(args, short_values):
    """Return (flags, values): flags is a set of names, values a list of (name, value)."""
    flags, values = set(), []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg.startswith("--"):
            name, eq, value = arg.partition("=")
            if name in VALUE_FLAGS and not eq and i + 1 < len(args):
                i += 1
                value = args[i]
            flags.add(name)
            if name in VALUE_FLAGS:
                values.append((name, value))
        elif arg.startswith("-") and len(arg) > 1:
            for j, char in enumerate(arg[1:], 1):
                flags.add("-" + char)
                if char in short_values:
                    value = arg[j + 1:]
                    if not value and i + 1 < len(args):
                        i += 1
                        value = args[i]
                    values.append(("-" + char, value))
                    break
        i += 1
    return flags, values


def message_texts(values, cwd):
    for name, value in values:
        if name in ("--body", "-b", "--subject", "--title", "-t"):
            yield value
        elif name in ("--body-file", "-F"):
            yield read_file(value, cwd)


def check_pr(sub, args, cwd):
    short_values = MERGE_SHORT_VALUES if sub == "merge" else EDIT_SHORT_VALUES
    flags, values = parse_flags(args, short_values)
    if any(ATTRIBUTION.search(text) for text in message_texts(values, cwd)):
        return f"`gh pr {sub}` text has a co-author trailer or a \"Generated with Claude\" line. Remove it."
    if sub != "merge" or flags & {"--rebase", "-r"}:
        return None
    if not flags & {"--body", "-b", "--body-file", "-F"}:
        return ("`gh pr merge` without --body lets GitHub write its default squash/merge message, "
                "which appends `Co-authored-by:` trailers from the branch commits and other authors. "
                "Pass an explicit --body (a short summary of the change; `--body \"\"` for title only).")
    return None


def check_api(args, cwd):
    if not any(re.search(r"pulls/\d+/merge/?$", arg) for arg in args):
        return None
    fields, i = {}, 0
    while i < len(args):
        arg = args[i]
        name, eq, value = arg.partition("=")
        pair = None
        if name in ("-f", "-F", "--field", "--raw-field") and not eq and i + 1 < len(args):
            i += 1
            pair = (name, args[i])
        elif name in ("--field", "--raw-field") and eq:
            pair = (name, value)
        if pair:
            key, _, field = pair[1].partition("=")
            # Typed fields (-F/--field) read `@file` values from that file, as gh does.
            if pair[0] in ("-F", "--field") and field.startswith("@"):
                field = read_file(field[1:], cwd)
            fields[key] = field
        elif name == "--input" and i + 1 < len(args):
            i += 1
            text = read_file(args[i], cwd)
            try:
                fields.update({k: str(v) for k, v in json.loads(text or "{}").items()})
            except (ValueError, AttributeError):
                fields["commit_message"] = text or ""
        i += 1
    if ATTRIBUTION.search(fields.get("commit_message", "") + "\n" + fields.get("commit_title", "")):
        return "The merge commit_message has a co-author trailer or a \"Generated with Claude\" line. Remove it."
    if fields.get("merge_method") != "rebase" and "commit_message" not in fields:
        return ("A merge via the API without commit_message gets GitHub's default message, which "
                "appends `Co-authored-by:` trailers. Pass -f commit_message=<summary>.")
    return None


def main():
    command, cwd = sys.stdin.read(), (sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
    try:
        parsed = list(segments(command, cwd))
    except (ValueError, OverflowError):
        # A GitHub-side commit whose text cannot be decoded cannot be checked: fail closed.
        if GH_WRITE.search(command):
            print("The hook could not parse this gh command, so its merge/PR text can't be checked. "
                  "Use plain quoting (or a --body-file).")
        return
    for tokens, cwd in parsed:
        for k, token in enumerate(tokens):
            if os.path.basename(token) != "gh":
                continue
            words = subcommand_words(tokens[k + 1:])
            try:
                if words[:2] == ["pr", "merge"] or words[:2] == ["pr", "create"] or words[:2] == ["pr", "edit"]:
                    reason = check_pr(words[1], tokens[k + 1:], cwd)
                elif words[:1] == ["api"]:
                    reason = check_api(tokens[k + 1:], cwd)
                else:
                    continue
            except Unreadable:
                reason = UNREADABLE
            if reason:
                print(reason)
                return


def subcommand_words(args):
    """Leading positional words, skipping flags placed before the subcommand (`gh -R o/r pr merge`)."""
    words, i = [], 0
    while i < len(args) and len(words) < 2:
        if args[i] in ("-R", "--repo", "--hostname"):
            i += 1
        elif not args[i].startswith("-"):
            words.append(args[i])
        i += 1
    return words


if __name__ == "__main__":
    main()
