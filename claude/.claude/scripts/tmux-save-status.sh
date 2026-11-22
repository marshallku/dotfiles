#!/usr/bin/env bash
# tmux status-bar segment: shows "󰆓 saved" for a few seconds after any tmux-resurrect save,
# including continuum auto-saves, which are otherwise silent. The @resurrect-hook-post-save-all
# hook in .tmux.conf touches the marker and forces a redraw.
#
# Runs via tmux #() every status-interval, so it must stay fast and self-contained (no jq,
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
