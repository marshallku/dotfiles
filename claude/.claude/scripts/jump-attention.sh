#!/usr/bin/env bash
# Jump to the tmux session of the most recent attention queue entry and
# remove that entry from the queue (most-recent-pop semantics — repeated
# presses drain the queue rather than looping on the same entry).
#
# For deliberate selection over multiple pending entries, use the fzf picker
# at scripts/attention-picker.sh (tmux: prefix+A).

set -u

queue="${XDG_CACHE_HOME:-$HOME/.cache}/claude-attention/queue.jsonl"
[[ -f "$queue" ]] || { echo "no attention queue" >&2; exit 0; }

cutoff=$(( $(date +%s) - 3600 ))

# Find the newest entry with ts >= cutoff. Scanning forward and keeping the
# last match avoids `tac` (GNU-only — macOS BSD coreutils don't ship it; the
# previous `tac …2>/dev/null` swallowed the missing-binary error and the
# whole pipeline silently produced no entry, making `a` look like a no-op
# popup-close on macOS).
entry=$(awk -v c="$cutoff" '
    match($0, /"ts":[0-9]+/) {
        ts = substr($0, RSTART+5, RLENGTH-5) + 0
        if (ts >= c) latest = $0
    }
    END { if (length(latest)) print latest }' "$queue")

[[ -z "$entry" ]] && { echo "no fresh attention" >&2; exit 0; }

ts=$(printf '%s' "$entry" | jq -r '.ts // ""' 2>/dev/null)
session=$(printf '%s' "$entry" | jq -r '.tmux_session // ""' 2>/dev/null)

# Consume the entry. Delete before switch so failed switches still drain the
# queue — the next notification will re-populate if attention truly needed.
if [[ -n "$ts" ]]; then
    awk -v t="\"ts\":${ts}," '!index($0, t) { print }' "$queue" > "${queue}.tmp" \
        && mv "${queue}.tmp" "$queue"
fi

[[ -z "$session" ]] && { echo "no tmux_session in latest entry" >&2; exit 0; }

if ! command -v tmx >/dev/null 2>&1; then
    echo "tmx not found on PATH; falling back to raw tmux" >&2
    if [[ -n "${TMUX:-}" ]]; then
        exec tmux switch-client -t "$session"
    else
        exec tmux attach-session -t "$session"
    fi
fi

exec tmx switch "$session"
