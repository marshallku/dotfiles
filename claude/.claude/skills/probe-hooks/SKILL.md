---
name: probe-hooks
description: Inspect Claude hook behavior — tail log, extract event counts, dump hook sources
user-invocable: true
arguments: lines
argument-hint: [N] (optional; number of log lines to scan, default 200)
allowed-tools: Bash
effort: low
---

## Purpose

Quick-start investigation for hook misfires or unexpected behavior. Replaces 3–4
manual Bash calls that recur every time hook behavior needs to be understood.
Observed in sessions 0f8a38e6, f447f64a, f7550a15 — each independently reconstructing
the same three-step sequence: tail log → grep event names → cat hook sources.

## Steps

### 1. Recent event counts

```bash
LOG="${HOME}/.claude/hooks-debug.log"
LINES="${1:-200}"
echo "=== Hook events (last ${LINES} log lines) ==="
# Extract the first identifier after the timestamp, matching BOTH log formats:
#   "[HH:MM:SS] careful triggered: ..."   (space-separated: careful-with-judge style)
#   "[HH:MM:SS] pre-commit-gate: ..."     (colon-separated: most other hooks)
tail -"${LINES}" "${LOG}" 2>/dev/null \
    | grep -oP '^\[\d+:\d+:\d+\] \K[a-z_-]+' \
    | sort | uniq -c | sort -rn
echo ""
```

### 2. Hook source listing

```bash
HOOKS_DIR="${HOME}/dotfiles/claude/.claude/hooks"
echo "=== Hook sources ==="
for f in "${HOOKS_DIR}"/*.sh; do
    [[ -f "${f}" ]] || continue
    echo "--- $(basename "${f}") ---"
    head -10 "${f}"
    echo ""
done
```

