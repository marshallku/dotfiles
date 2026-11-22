# /// script
# requires-python = ">=3.9"
# dependencies = ["tree-sitter-language-pack==1.25.2"]
# ///
"""Find low-value comments added to Rust, TypeScript/JavaScript, Go, Bash and Python sources.

    comment_guard.py hook --session ID FILE...   findings for comments FILE gained since HEAD,
                                                 each reported once per session (plain text)
    comment_guard.py diff [--cached | REV_RANGE] every comment block touching added lines (JSON lines)

Run through `uv run --script` so the tree-sitter dependency resolves on any machine.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set

from tree_sitter_language_pack import get_parser

LANG_BY_EXT = {
    ".rs": "rust",
    ".ts": "typescript",
    ".mts": "typescript",
    ".cts": "typescript",
    ".tsx": "tsx",
    ".js": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".jsx": "javascript",
    ".go": "go",
    ".sh": "bash",
    ".bash": "bash",
    ".py": "python",
}
COMMENT_NODES = {"comment", "line_comment", "block_comment"}
MAX_PLAIN_LINES = 3
MAX_DOC_LINES = 12
STATE_TTL_SECS = 7 * 24 * 3600

REASONS = {
    "process-narration": "names the review, plan or process that produced it; that belongs in the commit message",
    "change-history": "describes what used to be or what changed; that belongs in the commit message",
    "escape-hatch": "defers or excuses work (for now / placeholder / untracked TODO); implement it or drop it",
    "stub-code": "sits on a stub; implement it",
    "commented-out-code": "is commented-out code",
    "narration": "narrates steps the code already shows",
    "banner": "is a section banner",
    "emphasis": "is emphasis noise",
    "restates-code": "restates the next line",
}
ADVISORY = {"long-block", "long-doc"}

DIRECTIVE = re.compile(
    r"^\s*(//|#|/\*)\s*("
    r"eslint|@ts-(expect-error|ignore|nocheck)|prettier-ignore|biome-ignore|istanbul|c8|"
    r"nolint|go:|\+build|lint:|shellcheck|@hook-event|noqa|type:\s*ignore|pragma|pylint|"
    r"rustfmt::|SAFETY:|Safety:|region|endregion|/ <reference|"
    r"///\s*(script)?\s*$|requires-python|dependencies\s*=|\s+\"[\w.-]+[=<>~]"
    r")",
)
GO_DOC_TARGET = re.compile(r"^\s*(func|type|var|const|package)\b")
PROCESS = re.compile(
    r"(\b(codex|claude|reviewer|cross-?review|review)\s+(round|r\d|flagged|found|asked|pointed out|noted|suggested|"
    r"caught|finding|feedback)\b|"
    r"\b(review|codex)\s+(?:round\s*)?#?\d+\b|\bround\s*\d+\b|\bREVISE\b|\bper (the )?(review|reviewer|codex)\b|"
    r"\baddress(es|ed)? (the )?(review|reviewer|finding|feedback)\b|\bfinding\s*#?\d+\b|"
    r"\bas (requested|suggested|you asked)\b|\bthe user (asked|wants|requested)\b|"
    r"docs/plans/|\((?:[A-Z]{1,3}\d+[a-z]?)(?:[,/ ]+[A-Z]{1,3}\d+[a-z]?)*\)|"
    r"\[P[0-4]\]|\b(review|codex|reviewer)\b[^.\n]{0,12}\bP[0-4]\b|^regression\b)",
    re.M | re.I,
)
HISTORY = re.compile(
    r"\b(previously|(we|it|this|that|code|which) used to|the old (version|code|implementation|behaviou?r|approach)|"
    r"(was|were) (changed|replaced|renamed|switched|rewritten|removed)|before this (change|fix|commit)|renamed from|"
    r"instead of the (old|previous)|switched (from|to)|we (removed|replaced|changed|switched|moved)|"
    r"(fixed|added|changed|introduced) in (round|review|v?\d)|was (silently )?(broken|dead)|"
    r"now (uses|returns|handles|checks)\b.*\binstead\b)",
    re.I,
)
HISTORY_MARKER = re.compile(r"\bHISTORY\b")
ESCAPE_MARKER = re.compile(r"\b(TODO|FIXME|XXX|HACK)\b")
ESCAPE_PHRASE = re.compile(
    r"\b(for now|placeholder|not (yet )?implemented|unimplemented|in a real (implementation|app|world|system|scenario)|"
    r"for simplicity|simplified (version|implementation|for)|left as an exercise|out of scope for|"
    r"could be (improved|extended|optimi[sz]ed) later|in production,? (you|we) (would|should)|hard-?coded for now|"
    r"a proper (implementation|solution) would|full implementation would|stubbed( out)?)\b",
    re.I,
)
TICKET = re.compile(r"(TODO|FIXME)\s*[(:\[]\s*(#?\d+|[A-Z]+-\d+|https?://|@?\w+\))")
NARRATION = re.compile(
    r"^(first,|then,|next,|now,? (we|let'?s|the|call|check|parse|get|set|update|create)|finally,?|here,? we|let'?s|"
    r"we (now|then|first))\b|^step \d+[:.)]",
    re.I,
)
EMPHASIS = re.compile(r"(\bIMPORTANT\b|\bCRITICAL\b|!!|[✅❌✨🚀💡👉])")
BANNER = re.compile(r"^[\s=\-*#~_/]{4,}|[=\-*#~]{4,}\s*$")
STUB_CODE = re.compile(
    r"(todo!\(|unimplemented!\(|panic!\(\s*\"not implemented|throw new Error\(\s*[\"'`]not implemented|"
    r"panic\(\s*\"not implemented|NotImplementedError)",
    re.I,
)
CODE_WRAP = {
    "rust": ("fn __f() {\n", "\n}"),
    "go": ("package p\nfunc __f() {\n", "\n}"),
    "typescript": ("", ""),
    "tsx": ("", ""),
    "javascript": ("", ""),
    "python": ("", ""),
}
# Shell prose parses as commands, so Bash uses shapes that prose does not take.
BASH_CODE = re.compile(
    r"^[A-Za-z_][A-Za-z0-9_]*=\S|\$\(|\$\{|^(if|while|until)\s.*;\s*(then|do)\b|^for\s+\w+\s+in\s|"
    r"^(fi|done|esac|then|else)$|^(local|export|readonly|declare)\s+\w+=|\|\s*(grep|sed|awk|jq|xargs|sort|head|tail)\b|"
    r"\s2?>\s*/dev/null|2>&1|^(echo|printf|rm|cp|mv|mkdir|cd|source|\.)\s+\S+.*[\"'$/]"
)
CODE_PUNCT = re.compile(r"[;{}()=]")
WORD = re.compile(r"[A-Za-z][a-z]+|[A-Z]+(?![a-z])")
STOP_WORDS = {
    "the", "a", "an", "to", "of", "and", "or", "in", "on", "for", "is", "it", "this", "that", "with", "be",
    "by", "we", "if", "as", "at", "from", "get", "set", "new", "into", "then",
}


@dataclass
class Comment:
    path: str
    lang: str
    start: int
    end: int
    text: str
    kind: str
    next_code: str
    hits: List[str] = field(default_factory=list)

    @property
    def blocking_hits(self) -> List[str]:
        return [h for h in self.hits if h in REASONS]


def lang_for(path: str) -> Optional[str]:
    p = Path(path)
    if p.suffix in LANG_BY_EXT:
        return LANG_BY_EXT[p.suffix]
    if p.suffix or not p.is_file():
        return None
    try:
        with p.open("rb") as fh:
            first = fh.readline()
    except OSError:
        return None
    if first.startswith(b"#!") and (b"bash" in first or b"/sh" in first):
        return "bash"
    return None


def strip_markers(raw: str) -> str:
    lines = []
    for line in raw.splitlines():
        s = re.sub(r"^(///?!?|/\*\*?|\*/|\*|#+!?)", "", line.strip())
        lines.append(re.sub(r"\*/$", "", s).strip())
    return "\n".join(lines).strip()


def words(s: str) -> Set[str]:
    return {w.lower().rstrip("s") for w in WORD.findall(s) if w.lower() not in STOP_WORDS and len(w) >= 3}


def restates(body: str, next_code: str) -> bool:
    said = words(body)
    if not 2 <= len(said) <= 6:
        return False
    code = words(next_code)
    return bool(code) and len(said & code) / len(said) >= 0.6


def looks_like_code(lang: str, body: str) -> bool:
    lines = [l.strip() for l in re.sub(r"`[^`]*`", "", body).splitlines() if l.strip()]
    if lang == "bash":
        return bool(lines) and all(BASH_CODE.search(l) for l in lines)
    wrap = CODE_WRAP.get(lang)
    if not wrap or not lines or not all(CODE_PUNCT.search(l) for l in lines):
        return False
    return not get_parser(lang).parse((wrap[0] + body + wrap[1]).encode()).root_node.has_error


def apply_rules(c: Comment) -> None:
    body = strip_markers(c.text)
    first = body.splitlines()[0] if body else ""
    n_lines = c.end - c.start + 1
    checks = [
        ("process-narration", PROCESS.search(body)),
        ("change-history", HISTORY.search(body) or HISTORY_MARKER.search(body)),
        ("escape-hatch", (ESCAPE_MARKER.search(body) or ESCAPE_PHRASE.search(body)) and not TICKET.search(body)),
        ("stub-code", STUB_CODE.search(c.next_code)),
        ("narration", NARRATION.match(first)),
        ("emphasis", EMPHASIS.search(body)),
        ("banner", BANNER.search(first) and len(words(first)) <= 3),
        ("commented-out-code", c.kind == "plain" and looks_like_code(c.lang, body)),
        ("restates-code", c.kind == "plain" and restates(body, c.next_code)),
        ("long-block", c.kind == "plain" and n_lines > MAX_PLAIN_LINES),
        ("long-doc", c.kind == "doc" and n_lines > MAX_DOC_LINES),
    ]
    c.hits.extend(name for name, hit in checks if hit)


def walk_comments(node):
    if node.type in COMMENT_NODES:
        yield node
        return
    for child in node.children:
        yield from walk_comments(child)


def last_row(node) -> int:
    """tree-sitter-rust ends a line comment at column 0 of the next row."""
    end_row, end_col = node.end_point
    return end_row - 1 if end_col == 0 and end_row > node.start_point[0] else end_row


def classify(lang: str, text: str, start: int, next_code: str, trailing: bool) -> str:
    s = text.lstrip()
    if DIRECTIVE.match(text):
        return "directive"
    if lang == "rust" and s.startswith(("///", "//!", "/**")):
        return "doc"
    if lang in ("typescript", "tsx", "javascript") and s.startswith("/**"):
        return "doc"
    if lang == "go" and not trailing and GO_DOC_TARGET.match(next_code):
        return "doc"
    if lang in ("bash", "python") and start <= 2:
        return "header"
    return "plain"


def extract(path: str, source: bytes, lang: str) -> List[Comment]:
    tree = get_parser(lang).parse(source)
    src_lines = source.decode("utf-8", "replace").splitlines()
    blocks: List[List[dict]] = []
    for node in sorted(walk_comments(tree.root_node), key=lambda n: n.start_point[0]):
        row, col = node.start_point
        line = src_lines[row] if row < len(src_lines) else ""
        text = source[node.start_byte : node.end_byte].decode("utf-8", "replace").rstrip("\n")
        part = {
            "text": text,
            "start": row,
            "end": last_row(node),
            "col": col,
            "trailing": line[:col].strip() != "",
            "alone": (row == 0 and line.startswith("#!")) or bool(DIRECTIVE.match(text)),
        }
        prev = blocks[-1][-1] if blocks else None
        joins = (
            prev is not None
            and not part["alone"]
            and not blocks[-1][0]["alone"]
            and not part["trailing"]
            and not prev["trailing"]
            and row == prev["end"] + 1
            and col == prev["col"]
        )
        if joins:
            blocks[-1].append(part)
        else:
            blocks.append([part])
    out = []
    for parts in blocks:
        head, start, end = parts[0], parts[0]["start"], parts[-1]["end"]
        text = "\n".join(p["text"] for p in parts)
        if head["trailing"]:
            next_code = src_lines[start][: head["col"]]
        else:
            next_code = next((l for l in src_lines[end + 1 : end + 6] if l.strip()), "")
        if start == 0 and text.startswith("#!"):
            kind = "shebang"
        else:
            kind = classify(lang, text, start, next_code.strip(), head["trailing"])
        comment = Comment(path, lang, start + 1, end + 1, text, kind, next_code.strip())
        if kind in ("plain", "doc", "header"):
            apply_rules(comment)
        out.append(comment)
    return out


def git(cwd: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, errors="replace")


def parse_added(diff: str) -> Dict[str, Set[int]]:
    added: Dict[str, Set[int]] = {}
    current = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            current = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@") and current:
            plus = line.split("+", 1)[1].split(" ", 1)[0]
            first, _, count = plus.partition(",")
            added.setdefault(current, set()).update(range(int(first), int(first) + int(count or 1)))
    return added


def diff_added(cwd: str, *args: str) -> Dict[str, Set[int]]:
    """Added line numbers per path; mnemonicPrefix and friends are overridden so paths parse."""
    out = git(cwd, "diff", "-U0", "--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", *args)
    return parse_added(out.stdout)


def added_since_head(path: Path) -> Optional[Set[int]]:
    root = git(str(path.parent), "rev-parse", "--show-toplevel").stdout.strip()
    if not root:
        return None
    rel = os.path.relpath(path, root)
    if git(root, "ls-files", "--error-unmatch", "--", rel).returncode != 0:
        return set(range(1, path.read_bytes().count(b"\n") + 2))
    if git(root, "rev-parse", "--verify", "-q", "HEAD").returncode != 0:
        return set(range(1, path.read_bytes().count(b"\n") + 2))
    return diff_added(root, "HEAD", "--", rel).get(rel.replace(os.sep, "/"), set())


def state_file(session: str) -> Path:
    base = Path(os.environ.get("COMMENT_GUARD_STATE_DIR", Path.home() / ".claude/state/comment-guard"))
    base.mkdir(parents=True, exist_ok=True)
    now = time.time()
    for old in base.glob("*.json"):
        try:
            if now - old.stat().st_mtime > STATE_TTL_SECS:
                old.unlink()
        except OSError:
            continue
    return base / f"{re.sub(r'[^A-Za-z0-9_-]', '_', session) or 'default'}.json"


def cmd_hook(session: str, files: List[str]) -> int:
    state = state_file(session)
    try:
        seen = set(json.loads(state.read_text()))
    except (OSError, ValueError):
        seen = set()
    findings, reported = [], set()
    for name in files:
        path = Path(name).resolve()
        lang = lang_for(str(path))
        if not lang or not path.is_file():
            continue
        added = added_since_head(path)
        if not added:
            continue
        for c in extract(str(path), path.read_bytes(), lang):
            hits = c.blocking_hits
            if not hits or not added & set(range(c.start, c.end + 1)):
                continue
            key = hashlib.sha1(f"{path}\0{c.text}".encode()).hexdigest()
            if key in seen or key in reported:
                continue
            reported.add(key)
            first = c.text.splitlines()[0].strip()[:110]
            findings.append(f"- {path.name}:{c.start} `{first}` — " + "; ".join(REASONS[h] for h in hits))
    if reported:
        state.write_text(json.dumps(sorted(seen | reported)))
    print("\n".join(findings))
    return 0


def source_at(cwd: str, rel: str, mode: List[str]) -> Optional[bytes]:
    if "--cached" in mode:
        spec = f":{rel}"
    elif mode and ".." in mode[0]:
        spec = f"{mode[0].split('..', 1)[1] or 'HEAD'}:{rel}"
    else:
        path = Path(cwd) / rel
        return path.read_bytes() if path.is_file() else None
    out = subprocess.run(["git", "-C", cwd, "show", spec], capture_output=True)
    return out.stdout if out.returncode == 0 else None


def cmd_diff(mode: List[str]) -> int:
    cwd = git(os.getcwd(), "rev-parse", "--show-toplevel").stdout.strip()
    if not cwd:
        print("comment_guard: not a git repository", file=sys.stderr)
        return 2
    for rel, lines in diff_added(cwd, *mode).items():
        lang = lang_for(str(Path(cwd) / rel))
        source = source_at(cwd, rel, mode) if lang else None
        if not source:
            continue
        src_lines = source.decode("utf-8", "replace").splitlines()
        for c in extract(rel, source, lang):
            if c.kind not in ("plain", "doc", "header") or not lines & set(range(c.start, c.end + 1)):
                continue
            lo, hi = max(0, c.start - 4), min(len(src_lines), c.end + 8)
            record = asdict(c)
            record["context"] = "\n".join(f"{i + 1:4} {src_lines[i]}" for i in range(lo, hi))
            print(json.dumps(record, ensure_ascii=False))
    return 0


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    hook = sub.add_parser("hook")
    hook.add_argument("--session", default="default")
    hook.add_argument("files", nargs="+")
    diff = sub.add_parser("diff")
    diff.add_argument("--cached", action="store_true", help="the staged index against HEAD")
    diff.add_argument("rev_range", nargs="?", help="A..B; default is the working tree against the index")
    args = parser.parse_args(argv)
    if args.cmd == "hook":
        return cmd_hook(args.session, args.files)
    return cmd_diff(["--cached"] if args.cached else [args.rev_range] if args.rev_range else [])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
