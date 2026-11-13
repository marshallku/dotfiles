#!/usr/bin/env bash
# Harness health scorecard + trip wires.
#
# Reads the two ledgers the harness now keeps:
#   ~/.claude/state/hook-events.jsonl  — structured hook events (hook_event)
#   ~/.claude/state/codex-usage.jsonl  — codex token spend per run (codex-exec)
#
# Two modes:
#   (default)    full scorecard on stdout — run it by hand
#   --tripwire   silent unless something tripped; called from SessionStart, so
#                an anomaly reaches you when you sit down rather than never
#
# Why trip wires exist here: post-typecheck.sh was dead for four months and
# nothing noticed, because no layer of this harness answered "is a component
# that used to work still working?". TW3 below is that question, generalized.
#
# Opt-out: touch ~/.claude/state/tripwire-disabled

set -uo pipefail

. "$(dirname "$0")/../hooks/_lib.sh" 2>/dev/null || true

STATE="$HOME/.claude/state"
EVENTS="${HOOK_EVENT_LOG:-$STATE/hook-events.jsonl}"
USAGE="${CODEX_USAGE_LEDGER:-$STATE/codex-usage.jsonl}"

MODE="report"
[ "${1:-}" = "--tripwire" ] && MODE="tripwire"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$STATE/tripwire-disabled" ] && [ "$MODE" = "tripwire" ] && exit 0

TODAY=$(date '+%Y-%m-%d')
# Trailing baseline window, excluding today.
BASE_DAYS="${TRIPWIRE_BASELINE_DAYS:-6}"
SINCE=$(date -d "-${BASE_DAYS} days" '+%Y-%m-%d' 2>/dev/null \
     || date -v-"${BASE_DAYS}"d '+%Y-%m-%d' 2>/dev/null || echo "$TODAY")
WEEK_AGO=$(date -d '-7 days' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
        || date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "1970-01-01T00:00:00Z")
DAY_AGO=$(date -d '-1 day' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
       || date -u -v-1d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "1970-01-01T00:00:00Z")

TRIPS=()

# --- TW1: codex spend today vs the trailing daily mean -----------------------
# Absolute floor so a quiet baseline (a 2k-token day) cannot make an ordinary
# day look like a 10x runaway.
FLOOR="${TRIPWIRE_TOKEN_FLOOR:-150000}"
MULT="${TRIPWIRE_TOKEN_MULTIPLIER:-2}"
SPEND_LINE=""
if [ -f "$USAGE" ]; then
    SPEND_LINE=$(jq -s -r --arg today "$TODAY" --arg since "$SINCE" \
        --argjson floor "$FLOOR" --argjson mult "$MULT" '
        ([.[] | select(.day == $today) | .total_tokens // 0] | add // 0) as $t
        | ([.[] | select(.day < $today and .day >= $since)]) as $base
        | (($base | map(.day) | unique | length)) as $days
        | (($base | map(.total_tokens // 0) | add // 0)) as $basetot
        | (if $days > 0 then ($basetot / $days) else 0 end) as $avg
        | [$t, ($avg | floor), (if ($avg > 0 and $t > $floor and $t > ($avg * $mult)) then "TRIP" else "ok" end)]
        | @tsv' "$USAGE" 2>/dev/null || true)
fi
if [ -n "$SPEND_LINE" ]; then
    IFS=$'\t' read -r SPEND_TODAY SPEND_AVG SPEND_FLAG <<< "$SPEND_LINE"
    [ "${SPEND_FLAG:-ok}" = "TRIP" ] && TRIPS+=("codex spend today ${SPEND_TODAY} tokens vs ${BASE_DAYS}-day avg ${SPEND_AVG} (>${MULT}x) — check for a runaway loop")
fi

# --- TW2: a sensor that is erroring rather than sensing -----------------------
# NB: on a missing file jq still prints a result AND exits non-zero, so a
# trailing `|| echo 0` yields the two-line value "0\n0" and every downstream
# `[ x -gt 0 ]` becomes a syntax error. Gate on the file, then keep digits only.
SENSOR_BROKEN=0
if [ -f "$EVENTS" ]; then
    SENSOR_BROKEN=$(jq -s -r --arg since "$DAY_AGO" '
        [.[] | select(.ts >= $since and .component == "post-typecheck"
                      and (.event == "checker_error" or .event == "timeout"))] | length
    ' "$EVENTS" 2>/dev/null | head -n1 | tr -dc '0-9')
fi
[ -z "$SENSOR_BROKEN" ] && SENSOR_BROKEN=0
[ "$SENSOR_BROKEN" -gt 0 ] 2>/dev/null && TRIPS+=("post-typecheck hit ${SENSOR_BROKEN} checker_error/timeout in 24h — the sensor is failing, not passing")

# --- TW3: a component that used to report has gone silent --------------------
# The generalized form of the four-month post-typecheck outage. If a component
# produced events before the last 7 days but none since, it stopped running.
SILENT=""
if [ -f "$EVENTS" ]; then
    SILENT=$(jq -s -r --arg since "$WEEK_AGO" '
        group_by(.component)
        | map({c: .[0].component,
               recent: ([.[] | select(.ts >= $since)] | length),
               older:  ([.[] | select(.ts <  $since)] | length)})
        | [.[] | select(.recent == 0 and .older > 0) | .c] | join(", ")
    ' "$EVENTS" 2>/dev/null | head -n1 | tr -d '\n')
fi
# post-typecheck runs only on Edit/Write. With a daily heartbeat on every edit, its silence
# means "dead" only if this machine edited anything this week (Linux tripped 309 times in
# November while only Bash ran there).
if [ -n "$SILENT" ] && ! find "$STATE" -maxdepth 1 -name 'dirty-*.log' -mtime -7 2>/dev/null | grep -q .; then
    SILENT=$(printf '%s' "$SILENT" | tr ',' '\n' | sed 's/^ *//' | grep -vx 'post-typecheck' | paste -sd, - | sed 's/,/, /g')
fi
[ -n "$SILENT" ] && [ "$SILENT" != "null" ] && TRIPS+=("no events in 7 days from: ${SILENT} — component may be dead (see post-typecheck, dead 2026-04→08)")

# --- TW4: the install no longer matches dotfiles -------------------------------
# A gate can only run if its files are where settings.json points. On one machine
# ~/.claude/hooks held per-file symlinks without the _*.py helpers, and the merge policy
# silently allowed everything; on another a retired launchd job failed every few minutes
# for months. Neither produced a single ledger event.
INSTALL=()
HOOKS="$HOME/.claude/hooks"
SRC_HOOKS=$(python3 -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$HOOKS/_lib.sh" 2>/dev/null)
if [ -n "$SRC_HOOKS" ] && [ -d "$SRC_HOOKS" ]; then
    for f in "$SRC_HOOKS"/*.sh "$SRC_HOOKS"/*.py; do
        [ -e "$f" ] || continue
        [ -e "$HOOKS/$(basename "$f")" ] || INSTALL+=("hooks/$(basename "$f") missing (link the whole hooks directory)")
    done
    SRC_SETTINGS="$(dirname "$SRC_HOOKS")/settings.json"
    if [ -f "$SRC_SETTINGS" ] && [ ! -L "$HOME/.claude/settings.json" ] \
        && ! cmp -s "$SRC_SETTINGS" "$HOME/.claude/settings.json"; then
        INSTALL+=("settings.json is a copy that differs from dotfiles")
    fi
fi
if [ -f "$HOME/.claude/settings.json" ]; then
    while IFS= read -r hook; do
        [ -e "$HOOKS/$hook" ] || INSTALL+=("settings.json runs hooks/$hook, which does not exist")
    done < <(jq -r '.. | .command? // empty' "$HOME/.claude/settings.json" 2>/dev/null \
        | grep -oE '\.claude/hooks/[A-Za-z0-9_.-]+' | sed 's|.*/||' | sort -u)
fi
if [ "$(uname -s)" = Darwin ]; then
    for plist in "$HOME"/Library/LaunchAgents/*.plist; do
        [ -f "$plist" ] || continue
        while IFS= read -r ref; do
            [ -e "$ref" ] || INSTALL+=("launchd $(basename "$plist" .plist) runs missing $ref")
        done < <(grep -oE "$HOME/\.claude/[^<\"' ]+" "$plist" 2>/dev/null | sort -u)
    done
fi
[ ${#INSTALL[@]} -gt 0 ] && TRIPS+=("install drift: $(printf '%s; ' "${INSTALL[@]:0:4}")")

# --- Output -------------------------------------------------------------------
if [ "$MODE" = "tripwire" ]; then
    [ ${#TRIPS[@]} -eq 0 ] && exit 0
    OUT="⚠️  Harness trip wire"
    for t in "${TRIPS[@]}"; do OUT="$OUT"$'\n'"  • $t"; done
    OUT="$OUT"$'\n'"  (detail: bash ~/.claude/scripts/harness-report.sh · mute: touch ~/.claude/state/tripwire-disabled)"
    jq -n --arg ctx "$OUT" '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}' 2>/dev/null || true
    hook_log harness-tripwire "TRIPPED: ${#TRIPS[@]} condition(s)"
    exit 0
fi

echo "=== Harness health — $TODAY ==="
echo
echo "-- Trip wires --"
if [ ${#TRIPS[@]} -eq 0 ]; then echo "  none"; else for t in "${TRIPS[@]}"; do echo "  ⚠️  $t"; done; fi
echo
echo "-- Sensor (post-typecheck), last 7d --"
if [ -f "$EVENTS" ]; then
    jq -s -r --arg since "$WEEK_AGO" '
        [.[] | select(.ts >= $since and .component == "post-typecheck")]
        | group_by(.event) | map("  \(.[0].event): \(length)") | .[]
    ' "$EVENTS" 2>/dev/null | sort || true
    n=$(jq -s -r --arg s "$WEEK_AGO" '[.[]|select(.ts>=$s and .component=="post-typecheck")]|length' "$EVENTS" 2>/dev/null | head -n1 | tr -dc '0-9')
    [ "${n:-0}" = "0" ] && echo "  (no events — sensor silent)"
else
    echo "  (no event ledger yet)"
fi
echo
echo "-- Codex spend --"
if [ -f "$USAGE" ]; then
    echo "  today: ${SPEND_TODAY:-0} tokens   ${BASE_DAYS}-day avg: ${SPEND_AVG:-0}"
    jq -s -r --arg since "$SINCE" '
        [.[] | select(.day >= $since)] | group_by(.day)
        | map("  \(.[0].day)  \([.[].total_tokens // 0] | add) tok  (\(length) run(s))") | .[]
    ' "$USAGE" 2>/dev/null || true
else
    echo "  (no usage ledger yet — run a codex command)"
fi
echo
echo "-- Gate activity, last 7d (blocks) --"
if [ -f "$HOME/.claude/hooks-debug.log" ]; then
    # String compare on the "[YYYY-MM-DD" prefix; it used to count the whole log.
    WEEK_DAY="${WEEK_AGO%%T*}"
    grep -hoE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+\] [a-z-]+: (BLOCK|INJECT|TRIPPED)' \
        "$HOME/.claude/hooks-debug.log" 2>/dev/null \
        | awk -v since="[$WEEK_DAY" '$1 >= since {print "  " $3 " " $4}' | sort | uniq -c | sort -rn | head -10
fi
if [ -f "$EVENTS" ]; then
    # Stop reminders that cost a turn vs. ones deduplicated away (since 2026-10-20).
    jq -s -r --arg since "$WEEK_AGO" '
        [.[] | select(.ts >= $since and .component == "auto-cross-review")] | group_by(.event)
        | map("  auto-cross-review \(.[0].event): \(length)") | .[]
    ' "$EVENTS" 2>/dev/null || true
fi
