#!/usr/bin/env bash
# PostToolUse hook for Edit|Write — records touched files per session AND
# invalidates the cross-review "reviewed" marker for the file's repo, so any
# new edit after an approved review requires a fresh review before commit.

set -euo pipefail

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] && { echo '{}'; exit 0; }

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
echo "$FILE" >> "$STATE_DIR/dirty-${SESSION}.log"

# Invalidate reviewed marker for this file's repo (if it is a git repo)
FILE_DIR=$(dirname "$FILE")
if REPO_ROOT=$(cd "$FILE_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null); then
    REPO_HASH=$(printf '%s' "$REPO_ROOT" | md5sum | awk '{print $1}' | head -c 12)
    rm -f "$STATE_DIR/reviewed-$REPO_HASH"
fi

echo '{}'
