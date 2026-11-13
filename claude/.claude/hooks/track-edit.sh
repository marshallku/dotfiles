#!/usr/bin/env bash
# PostToolUse Edit|Write: retain touched paths for session reporting.
# Review gates independently compare Git content.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] && { echo '{}'; exit 0; }

# Subagents share the lead's session_id. Their edits (usually in scratchpad
# worktrees the lead never commits from) made auto-cross-review block the lead
# 163 times in one session. The commit gate still checks every staged path.
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
case "$FILE" in
    */claude-[0-9]*/*/scratchpad/*) SCRATCH=1 ;;
    *) SCRATCH= ;;
esac
if [ -n "$AGENT_ID" ] || [ -n "$SCRATCH" ]; then
    hook_log track-edit "skip ${AGENT_ID:+agent=$AGENT_ID }$FILE"
    echo '{}'
    exit 0
fi

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
echo "$FILE" >> "$STATE_DIR/dirty-${SESSION}.log"

# Approval validity is checked against content, including edits made outside Claude.
echo '{}'
