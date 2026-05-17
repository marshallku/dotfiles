#!/usr/bin/env bash
# Jump to the tmux session of the most recent attention queue entry.
# Bind to tmux prefix+a (and optionally a global hotkey).
#
# Behavior: most-recent-wins. Stale entries (>1h) are ignored.
# Multi-attention disambiguation (fzf picker) is a future enhancement.

set -u

queue="${XDG_CACHE_HOME:-$HOME/.cache}/claude-attention/queue.jsonl"
[[ -f "$queue" ]] || { echo "no attention queue" >&2; exit 0; }

cutoff=$(( $(date +%s) - 3600 ))

entry=$(tac "$queue" 2>/dev/null | awk -v c="$cutoff" '
    match($0, /"ts":[0-9]+/) {
        ts = substr($0, RSTART+5, RLENGTH-5) + 0
        if (ts >= c) { print; exit }
    }')

[[ -z "$entry" ]] && { echo "no fresh attention" >&2; exit 0; }

session=$(printf '%s' "$entry" | jq -r '.tmux_session // ""' 2>/dev/null)
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
