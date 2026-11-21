#!/usr/bin/env bash
# @hook-event: Stop
# Stop hook: OS notification + attention-queue push when a Claude turn finishes.
# Delegates platform notification + queue logic to scripts/notify-attention.sh.
#
# Opt out: touch ~/.claude/state/notify-stop-disabled

set -u

[[ -f "$HOME/.claude/state/notify-stop-disabled" ]] && exit 0

input=$(cat 2>/dev/null || true)
session=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
hook_cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null)

cwd_name=$(basename "${hook_cwd:-$PWD}")
title="Claude · $cwd_name"
body="Turn finished"

exec "$(dirname "$0")/../scripts/notify-attention.sh" \
    --kind stop \
    --source claude \
    --title "$title" \
    --body "$body" \
    --session "$session" \
    --cwd "$hook_cwd"
