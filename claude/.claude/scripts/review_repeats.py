#!/usr/bin/env python3
"""Find CRITICAL findings that recur across two review rounds.

Usage: review_repeats.py PREVIOUS_FILE CURRENT_FILE
Each file holds the CRITICAL section of one round, one finding per "- [C" line.
Prints one line per current finding that repeats an earlier one:
    <current id>\t<previous id>\t<shared file names, comma-separated>
Exit 0 always on readable input (empty output = no repeats), 2 on unreadable input.

A finding repeats when it names a file the earlier one named and the two share most of
their significant words: line numbers move as fixes land, so file:line alone misses them.
Paths name the same file when one is a component-wise suffix of the other, so `shell.rs`
matches `linux/src/ui/shell.rs` but `client/index.ts` never matches `admin/index.ts`.
"""
import re
import sys

WORD_OVERLAP = 0.4
MIN_WORD_LEN = 4
FILE_RE = re.compile(r"[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[A-Za-z0-9]{1,8}(?=[:\]\)`\s,]|$)")
ID_RE = re.compile(r"^-\s*\[(C\d+)\]")
STOP_WORDS = frozenset(
    "that this with from when then than they their there still into only also does have been "
    "will would should could which while where after before because without within other "
    "change changes staged diff round fix fixed code line file files path".split()
)


def same_file(a: tuple[str, ...], b: tuple[str, ...]) -> bool:
    shorter, longer = sorted((a, b), key=len)
    return bool(shorter) and longer[-len(shorter):] == shorter


def shared_files(a: set[tuple[str, ...]], b: set[tuple[str, ...]]) -> list[str]:
    return sorted({"/".join(min(x, y, key=len)) for x in a for y in b if same_file(x, y)})


def parse(text: str) -> list[tuple[str, set[tuple[str, ...]], set[str]]]:
    findings = []
    for line in text.splitlines():
        match = ID_RE.match(line.strip())
        if not match:
            continue
        body = line.strip()[match.end():]
        files = {tuple(part for part in name.split("/") if part not in ("", ".")) for name in FILE_RE.findall(body)}
        prose = FILE_RE.sub(" ", body).lower()
        words = {w for w in re.findall(r"[a-z][a-z_]+", prose) if len(w) >= MIN_WORD_LEN and w not in STOP_WORDS}
        findings.append((match.group(1), files, words))
    return findings


def overlap(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


def repeats(previous: str, current: str) -> list[tuple[str, str, list[str]]]:
    earlier = parse(previous)
    result = []
    for cur_id, cur_files, cur_words in parse(current):
        for prev_id, prev_files, prev_words in earlier:
            shared = shared_files(cur_files, prev_files)
            if shared and overlap(cur_words, prev_words) >= WORD_OVERLAP:
                result.append((cur_id, prev_id, shared))
                break
    return result


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as prev, open(argv[2], encoding="utf-8") as cur:
            found = repeats(prev.read(), cur.read())
    except OSError as error:
        print(f"review_repeats: {error}", file=sys.stderr)
        return 2
    for cur_id, prev_id, shared in found:
        print(f"{cur_id}\t{prev_id}\t{','.join(shared)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
