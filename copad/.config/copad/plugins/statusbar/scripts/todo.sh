#!/usr/bin/env bash
# copad statusbar module: active (non-done) todo count from the copad todo
# plugin — backlog state no external bar (waybar/tmux/zsh) can see. A `!`
# is appended when any todo is blocked. Blank when nothing is open.
#
# coctl by absolute path (daemon PATH lacks ~/.local/bin).
set -u

coctl="$HOME/.local/bin/coctl"
[[ -x "$coctl" ]] || exit 0

json=$("$coctl" --json todo list 2>/dev/null) || exit 0

# Count only the actionable buckets explicitly; the headline total is
# their sum (below), so it can never disagree with the tooltip — entries
# with a missing/unknown status are simply not counted in either.
counts=$(printf '%s' "$json" | jq -r '
    [.todos[]? | .status] as $s
    | "\($s | map(select(. == "open")) | length)\t" +
      "\($s | map(select(. == "in_progress")) | length)\t" +
      "\($s | map(select(. == "blocked")) | length)"' 2>/dev/null) || exit 0

IFS=$'\t' read -r open doing blocked <<< "$counts"
total=$(( ${open:-0} + ${doing:-0} + ${blocked:-0} ))
(( total == 0 )) && exit 0

mark=""
[[ -n "$blocked" && "$blocked" != "0" ]] && mark="!"
tip="${open:-0} open · ${doing:-0} in progress · ${blocked:-0} blocked"

# U+F0AE tasks glyph + trailing space (overdraw guard).
jq -cn --arg t " ${total}${mark} " --arg tip "$tip" '{text: $t, tooltip: $tip}'
