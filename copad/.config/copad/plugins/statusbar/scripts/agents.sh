#!/usr/bin/env bash
# copad statusbar module: claude agent attention queue + busy/idle counts.
#
# Plain-text sibling of ~/.claude/scripts/tmux-agent-status.sh — that one
# emits tmux `#[bg=..]` markup which copad's GTK label would render
# literally, so the counting logic is duplicated here with a clean
# {text,tooltip} JSON output instead. Kept self-contained (no jq, no
# coctl, no network) so it stays fast under the 8s module timeout.
#
#   ⚑N    distinct tmux sessions with fresh (<1h) attention entries
#   ●B/T  B busy agents out of T live agent processes
#
# Prints nothing (blank label) when there is no live agent and nothing
# pending, matching the tmux segment's "stay clean when idle" behaviour.
set -u

queue="${XDG_CACHE_HOME:-$HOME/.cache}/claude-attention/queue.jsonl"
sessions_dir="$HOME/.claude/sessions"

attention=0
if [[ -f "$queue" ]]; then
    cutoff=$(( $(date +%s) - 3600 ))
    attention=$(awk -v c="$cutoff" '
        match($0, /"ts":[0-9]+/) {
            if (substr($0, RSTART+5, RLENGTH-5) + 0 < c) next
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
        kill -0 "$pid" 2>/dev/null || continue
        total=$(( total + 1 ))
        grep -q '"status":"busy"' "$f" 2>/dev/null && busy=$(( busy + 1 ))
    done
fi

parts=()
tips=()
if (( attention > 0 )); then
    parts+=("⚑${attention}")
    tips+=("${attention} waiting for input")
fi
if (( total > 0 )); then
    parts+=("●${busy}/${total}")
    tips+=("${busy} busy of ${total} live")
fi

(( ${#parts[@]} == 0 )) && exit 0

text="${parts[*]}"
tip=""
for t in "${tips[@]}"; do
    tip="${tip:+$tip · }$t"
done

# Hand-rolled JSON: text/tip are digits + known ASCII/glyphs, no escaping
# needed. The glyphs get a trailing space (same overdraw fix as the tmux
# segment) — wide glyphs bleed into the next char otherwise.
printf '{"text":"%s ","tooltip":"%s"}\n' "$text" "$tip"
