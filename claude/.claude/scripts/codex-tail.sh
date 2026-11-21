#!/usr/bin/env bash
# codex-tail.sh — follow a codex-exec run from another pane (comux split, tmux, a second terminal).
#
#   codex-tail.sh            follow the newest run (waits for one to start)
#   codex-tail.sh review     follow the newest run whose thread key contains "review"
#   codex-tail.sh --list     list recent runs: state, age, round, verdict, key
#
# Reads ~/.claude/state/codex-live/<key>-<run>.{jsonl,status.json} written by codex-exec.sh
# and renders events with the same codex-render.jq the wrapper uses on stderr. Stops when the
# run's status turns "done" and prints its exit and verdict. Linux and macOS (tail -F, jq).

set -uo pipefail

LIVE_DIR="$HOME/.claude/state/codex-live"
RENDERER="$(cd "$(dirname "$0")" && pwd)/codex-render.jq"
POLL_SECONDS=1
LIST_LIMIT=15

command -v jq >/dev/null 2>&1 || { echo "[codex-tail] jq not found" >&2; exit 2; }

# Status files newest run first, by started_at — not mtime: finishing rewrites a status file,
# so an older run ending after a newer one started would otherwise win.
runs_by_start() {
    local files=("$LIVE_DIR"/*.status.json)
    [[ -e "${files[0]}" ]] || return 0
    jq -r '[.started_at // "", input_filename] | @tsv' "${files[@]}" 2>/dev/null | sort -r | cut -f2
}

newest_status() {
    local filter="${1:-}"
    runs_by_start | while IFS= read -r file; do
        [[ -z "$filter" || "$(basename "$file")" == *"$filter"* ]] && { printf '%s\n' "$file"; break; }
    done
}

if [[ "${1:-}" == "--list" ]]; then
    runs_by_start | head -n "$LIST_LIMIT" | while IFS= read -r file; do
        jq -r '[.state, .started_at, (.round // "-" | tostring), (.verdict // "-"), (if (.thread_key // "") == "" then "adhoc" else .thread_key end)] | @tsv' \
            "$file" 2>/dev/null
    done | column -t -s $'\t' 2>/dev/null || true
    exit 0
fi

FILTER="${1:-}"
STATUS_FILE=$(newest_status "$FILTER")
if [[ -z "$STATUS_FILE" ]]; then
    echo "[codex-tail] waiting for a codex run${FILTER:+ matching '$FILTER'}…" >&2
    while [[ -z "$STATUS_FILE" ]]; do
        sleep "$POLL_SECONDS"
        STATUS_FILE=$(newest_status "$FILTER")
    done
fi

EVENTS_FILE=$(jq -r '.events // empty' "$STATUS_FILE" 2>/dev/null)
[[ -n "$EVENTS_FILE" ]] || EVENTS_FILE="${STATUS_FILE%.status.json}.jsonl"
jq -r '"── \(if (.thread_key // "") == "" then "adhoc" else .thread_key end) · round \(.round // "-") · started \(.started_at) · \(.state)"' "$STATUS_FILE" 2>/dev/null

# Subshell so pkill -P reaches both tail and jq.
( tail -n +1 -F "$EVENTS_FILE" 2>/dev/null | jq -r --unbuffered -f "$RENDERER" 2>/dev/null ) &
TAIL_PID=$!
trap 'kill "$TAIL_PID" 2>/dev/null; pkill -P "$TAIL_PID" 2>/dev/null; exit 130' INT TERM

while [[ "$(jq -r '.state // "running"' "$STATUS_FILE" 2>/dev/null)" == "running" ]]; do
    # A crashed wrapper never writes "done"; stop when its pid is gone.
    pid=$(jq -r '.pid // empty' "$STATUS_FILE" 2>/dev/null)
    [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null && break
    sleep "$POLL_SECONDS"
done
sleep "$POLL_SECONDS"
pkill -P "$TAIL_PID" 2>/dev/null
kill "$TAIL_PID" 2>/dev/null
wait "$TAIL_PID" 2>/dev/null
jq -r '"── \(.state) · exit \(.exit // "?") · verdict \(.verdict // "-") · ended \(.ended_at // "?")"' "$STATUS_FILE" 2>/dev/null
