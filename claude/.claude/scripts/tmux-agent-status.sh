#!/usr/bin/env bash
# tmux status-bar segment: agent attention queue + busy/idle agent counts.
#
#   ⚑N    distinct tmux sessions with fresh (< 1h) claude-attention entries —
#         agents waiting for input. prefix+a jumps to the newest, prefix+A
#         picks. Distinct sessions, not raw entries: one chatty session can
#         queue dozens of notifications and ⚑41 reads as alarm, not signal.
#   ●B/T  B busy agents out of T live agent processes (~/.claude/sessions).
#
# Prints nothing when there are no live agents and no pending attention so the
# status bar stays clean. Invoked by tmux #() every status-interval; must stay
# fast and self-contained (no jq, no tmux calls, no network).

set -u

queue="${XDG_CACHE_HOME:-$HOME/.cache}/claude-attention/queue.jsonl"
sessions_dir="$HOME/.claude/sessions"

attention=0
if [[ -f "$queue" ]]; then
    cutoff=$(( $(date +%s) - 3600 ))
    attention=$(awk -v c="$cutoff" '
        match($0, /"ts":[0-9]+/) {
            if (substr($0, RSTART+5, RLENGTH-5) + 0 < c) next
            # Entries without a tmux_session are not jumpable (prefix+a would
            # drop them) and are not a session — skip rather than bucket as "".
            if (!match($0, /"tmux_session":"[^"]+"/)) next
            s = substr($0, RSTART+16, RLENGTH-17)
            if (!(s in seen)) { seen[s] = 1; n++ }
        }
        END { print n + 0 }' "$queue")
fi

busy=0
total=0
if [[ -d "$sessions_dir" ]]; then
    for f in "$sessions_dir"/*.json; do
        [[ -e "$f" ]] || break
        pid="${f##*/}"
        pid="${pid%.json}"
        # Skip stale files left behind by dead processes — sessions/ is not
        # garbage-collected on crash. kill -0 (not /proc) for macOS too.
        kill -0 "$pid" 2>/dev/null || continue
        total=$(( total + 1 ))
        grep -q '"status":"busy"' "$f" 2>/dev/null && busy=$(( busy + 1 ))
    done
fi

out=""
if (( attention > 0 )); then
    out+="#[fg=#f38ba8,bold]⚑${attention}#[default] "
fi
if (( total > 0 )); then
    if (( busy > 0 )); then
        out+="#[fg=#fab387]●${busy}#[fg=#6c7086]/${total}#[default] "
    else
        out+="#[fg=#6c7086]●0/${total}#[default] "
    fi
fi

printf '%s' "$out"
