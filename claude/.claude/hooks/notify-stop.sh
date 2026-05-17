#!/usr/bin/env bash
# Stop hook: OS notification + attention-queue push when a Claude turn finishes.
# Delegates platform notification + queue logic to scripts/notify-attention.sh.
#
# Opt out: touch ~/.claude/state/notify-stop-disabled

set -u

[[ -f "$HOME/.claude/state/notify-stop-disabled" ]] && exit 0

. "$(dirname "$0")/_lib.sh"

input=$(cat 2>/dev/null || true)
session=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
hook_cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null)
transcript=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
stop_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)

# Suppress on the first Stop fire if auto-cross-review is going to block it.
# Block-fire Claude continues, runs codex-review, re-Stops with stop_hook_active=true
# — that is the real "turn finished" moment to notify on.
if [[ "$stop_active" != "true" ]] && auto_review_would_block "$session" "$hook_cwd" "$transcript"; then
    exit 0
fi

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
