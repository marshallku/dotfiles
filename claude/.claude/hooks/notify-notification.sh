#!/usr/bin/env bash
# Notification hook: fires when Claude pauses for user input
# (permission prompts, idle timeout). More precise "needs attention" signal
# than Stop — Stop fires after every turn whether or not input is required.
#
# Opt out: touch ~/.claude/state/notify-notification-disabled

set -u

[[ -f "$HOME/.claude/state/notify-notification-disabled" ]] && exit 0

input=$(cat 2>/dev/null || true)
session=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
hook_cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null)
message=$(echo "$input" | jq -r '.message // ""' 2>/dev/null)

cwd_name=$(basename "${hook_cwd:-$PWD}")
title="Claude · $cwd_name"
body="${message:-Needs attention}"

exec "$(dirname "$0")/../scripts/notify-attention.sh" \
    --kind notification \
    --source claude \
    --title "$title" \
    --body "$body" \
    --session "$session" \
    --cwd "$hook_cwd"
