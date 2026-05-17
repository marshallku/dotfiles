#!/usr/bin/env bash
# Codex notify script: receives the agent-turn-complete event JSON as the
# last argv argument and forwards it to notify-attention.sh.
#
# Wire-up: in ~/.codex/config.toml
#   notify = ["bash", "/home/marshall/.claude/hooks/notify-codex.sh"]
#
# Opt out: touch ~/.claude/state/notify-codex-disabled

set -u

[[ -f "$HOME/.claude/state/notify-codex-disabled" ]] && exit 0

payload=""
if [[ $# -gt 0 ]]; then
    payload="${!#}"
fi
# Fallback to stdin (shouldn't happen with current codex behaviour, but cheap).
if [[ -z "$payload" ]] && ! [ -t 0 ]; then
    payload=$(cat 2>/dev/null || true)
fi

[[ -z "$payload" ]] && exit 0

event_type=$(printf '%s' "$payload" | jq -r '.type // ""' 2>/dev/null)

# Only react to agent-turn-complete for now; ignore other event types codex
# may emit so we don't double-notify per turn.
[[ "$event_type" != "agent-turn-complete" ]] && exit 0

cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)
turn_id=$(printf '%s' "$payload" | jq -r '."turn-id" // ""' 2>/dev/null)
last_msg=$(printf '%s' "$payload" | jq -r '."last-assistant-message" // ""' 2>/dev/null)

cwd_name=$(basename "${cwd:-${PWD:-}}")
title="Codex · $cwd_name"
# First line of last assistant message as the preview; fall back to generic.
preview=$(printf '%s' "$last_msg" | head -n1 | cut -c1-160)
body="${preview:-Turn finished}"

exec "$(dirname "$0")/../scripts/notify-attention.sh" \
    --kind codex-turn \
    --source codex \
    --title "$title" \
    --body "$body" \
    --session "$turn_id" \
    --cwd "$cwd"
