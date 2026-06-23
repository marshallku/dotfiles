#!/usr/bin/env bash
# tmux status-bar segment: transient "session saved" indicator.
#
#   󰆓 saved   shown for a few seconds after a tmux-resurrect save completes —
#             both manual (prefix+Ctrl-s) and continuum auto-saves (which run
#             save.sh in "quiet" mode and would otherwise be silent).
#
# Wiring: the @resurrect-hook-post-save-all hook (see .tmux.conf) touches the
# marker file below after every save and forces a status redraw, so this
# segment lights up promptly without waiting for the next status-interval.
#
# Prints nothing when no save is recent so the status bar stays clean. Invoked
# by tmux #() every status-interval; must stay fast and self-contained (no jq,
# no tmux calls, no network).

set -u

marker="${TMUX_SAVE_MARKER:-${TMPDIR:-/tmp}/tmux-last-save}"
window=8  # seconds the indicator stays visible

[[ -f "$marker" ]] || exit 0

saved=$(stat -c %Y "$marker" 2>/dev/null || echo 0)
age=$(( $(date +%s) - saved ))

if (( age >= 0 && age < window )); then
    printf '#[bg=#a6e3a1,fg=#1e1e2e,bold] 󰆓 saved #[default] '
fi
