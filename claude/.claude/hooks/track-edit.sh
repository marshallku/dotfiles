#!/usr/bin/env bash
# PostToolUse Edit|Write: retain touched paths for session reporting.
# Review gates independently compare Git content.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] && { echo '{}'; exit 0; }

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
echo "$FILE" >> "$STATE_DIR/dirty-${SESSION}.log"

# Approval validity is checked against content, including edits made outside Claude.
echo '{}'
