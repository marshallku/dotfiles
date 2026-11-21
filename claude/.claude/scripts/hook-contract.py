#!/usr/bin/env python3
"""Check that settings.json registers every hook on the event its script declares.

Each registered hook carries `# @hook-event: Event[=arg] ...` near its top. On the work Mac
`track-bash-edit.sh post` sat under UserPromptSubmit from 2026-11-14: the header said
PostToolUse, Bash edits went unchecked in autonomous loops for a week, and no ledger event
showed it. This makes that mismatch a trip wire and a test failure.

Usage: hook-contract.py <settings.json> <hooks-dir>   → one violation per line, exit 1 if any.
"""
from pathlib import Path
import json
import re
import sys

COMMAND_RE = re.compile(r"\.claude/hooks/([A-Za-z0-9_.-]+\.sh)(?:\s+([A-Za-z0-9_-]+))?")
ANNOTATION_RE = re.compile(r"^#\s*@hook-event:\s*(.+)$", re.M)
HEADER_BYTES = 2048


def declared(script):
    """{(event, arg-or-None)} from the script header, or None when it declares nothing."""
    try:
        head = script.read_text(encoding="utf-8", errors="replace")[:HEADER_BYTES]
    except OSError:
        return None
    match = ANNOTATION_RE.search(head)
    if not match:
        return None
    tokens = set()
    for token in match.group(1).split():
        event, _, arg = token.partition("=")
        tokens.add((event, arg or None))
    return tokens


def registrations(settings):
    """[(event, script, arg-or-None)] for every hook command under ~/.claude/hooks."""
    found = []
    for event, blocks in (settings.get("hooks") or {}).items():
        for block in blocks or []:
            for hook in block.get("hooks") or []:
                match = COMMAND_RE.search(hook.get("command", ""))
                if match:
                    found.append((event, match.group(1), match.group(2)))
    return found


def violations(settings, hooks_dir):
    problems = []
    seen = {}
    for event, script, arg in registrations(settings):
        seen.setdefault(script, set()).add((event, arg))
        tokens = declared(hooks_dir / script)
        if tokens is None:
            problems.append(f"{script}: registered under {event} but declares no @hook-event")
            continue
        if (event, arg) not in tokens and (event, None) not in tokens:
            label = f"{script} {arg}" if arg else script
            problems.append(f"{label}: registered under {event}, but its header declares "
                            + " ".join(f"{e}={a}" if a else e for e, a in sorted(tokens, key=str)))
    for script, used in seen.items():
        for event, arg in declared(hooks_dir / script) or ():
            if (event, arg) not in used and not (arg is None and any(e == event for e, _ in used)):
                label = f"{script} {arg}" if arg else script
                problems.append(f"{label}: header declares {event}, but settings.json never registers it there")
    return problems


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    try:
        settings = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"cannot read {argv[1]}: {error}")
        return 1
    problems = violations(settings, Path(argv[2]))
    for problem in problems:
        print(problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
