#!/usr/bin/env bash
# SessionStart hook: surface overdue open-loops once per day.
#
# The open-loops registry (life-assistant memory) is faithfully maintained but
# nothing surfaces it — items sit past their `review_after` for weeks (measured
# 2026-07-16: 11 items 38~56 days overdue) while daily evening reviews re-log a
# subset by hand. This hook closes that gap: a once-per-day nudge listing loops
# whose review date has passed, pointing at `/loops` to triage them.
#
# Design (mirrors the intent-capture noise lesson — a nudge, never a wall):
#   - throttled to once per calendar day via a state marker
#   - human summary to stderr; a SHORT additionalContext so the model is aware
#     when asked, but told not to raise it unprompted (won't derail a session)
#   - graceful no-op when the registry is absent (portable across machines)
#   - opt-out: touch ~/.claude/state/open-loops-surface-disabled
#   - override path: OPEN_LOOPS_FILE env var

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

# Global opt-out.
if [ -f "$STATE_DIR/open-loops-surface-disabled" ]; then
    echo '{}'
    exit 0
fi

LOOPS_FILE="${OPEN_LOOPS_FILE:-$HOME/bots/Marshall Ku/memory/open-loops.json}"

# Registry absent (e.g. different machine / bots repo not cloned) → no-op.
if [ ! -f "$LOOPS_FILE" ]; then
    echo '{}'
    exit 0
fi

TODAY=$(date +%Y-%m-%d)
MARKER="$STATE_DIR/open-loops-surfaced-$TODAY"

# GC yesterday's markers (keep only today's).
find "$STATE_DIR" -maxdepth 1 -type f -name 'open-loops-surfaced-*' \
    ! -name "open-loops-surfaced-$TODAY" -delete 2>/dev/null || true

# Throttle: atomically claim today's marker (create-if-not-exists via noclobber).
# This is the single check-and-set — a concurrent SessionStart that loses the race,
# or an unwritable state dir, both fail acquisition and no-op (no double nudge).
# The marker is released below only if the analyzer fails, so a failed run retries.
if ! ( set -o noclobber; : > "$MARKER" ) 2>/dev/null; then
    echo '{}'
    exit 0
fi

# Analyze + emit. Python does the JSON parse, date math, and output shaping:
#   stdout → SessionStart hookSpecificOutput JSON (or '{}')
#   stderr → human-readable nudge
# Guard against a malformed registry breaking session start.
set +e
OUT=$(LOOPS_FILE="$LOOPS_FILE" TODAY="$TODAY" python3 - "$LOOPS_FILE" "$TODAY" <<'PY'
import json, os, sys, datetime

path, today_s = sys.argv[1], sys.argv[2]
today = datetime.date.fromisoformat(today_s)

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    items = data.get("items", [])
except Exception:
    print("{}")
    sys.exit(0)

ACTIVE = {"active", "incubating"}
overdue = []
active_no_date = 0
for it in items:
    if it.get("status") not in ACTIVE:
        continue
    ra = it.get("review_after")
    if not ra:
        active_no_date += 1
        continue
    try:
        d = datetime.date.fromisoformat(ra)
    except Exception:
        continue
    if d < today:
        overdue.append((( today - d).days, it))

if not overdue:
    # Nothing overdue — stay silent, still throttle for the day.
    print("{}")
    sys.exit(0)

overdue.sort(key=lambda x: x[0], reverse=True)
total_active = sum(1 for it in items if it.get("status") in ACTIVE)

TOP = 6
lines = []
for days, it in overdue[:TOP]:
    lines.append(f"- [{days}d] {it.get('id','?')} ({it.get('domain','?')})")
more = len(overdue) - TOP
if more > 0:
    lines.append(f"- … and {more} more")

n = len(overdue)
body = (
    f"## ⏰ Overdue open-loops ({n})\n\n"
    f"{n} tracked loop(s) are past their `review_after` date with no movement. "
    f"Run `/loops` to triage each (close / defer / act).\n\n"
    + "\n".join(lines)
    + f"\n\n(active loops: {total_active} total · +{active_no_date} with no review date · "
    f"registry: {path})\n\n"
    "_This is a standing status nudge — do not raise it unless the user asks about pending work._"
)

# Human-facing nudge on stderr.
sys.stderr.write(f"[open-loops] {n} overdue — run /loops to triage\n")

out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": body,
    }
}
print(json.dumps(out, ensure_ascii=False))
PY
)
rc=$?
set -e

if [ "$rc" -ne 0 ] || [ -z "$OUT" ]; then
    # Analyzer failed — do not block session start; release the marker so a
    # later session retries (a valid "nothing overdue" result prints "{}" with
    # rc 0, so this branch is a genuine failure, not an empty registry).
    rm -f "$MARKER" 2>/dev/null || true
    echo '{}'
    exit 0
fi

# Marker already claimed atomically above — just emit the result.
printf '%s\n' "$OUT"
