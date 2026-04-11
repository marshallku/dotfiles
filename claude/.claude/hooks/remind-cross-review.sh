#!/usr/bin/env bash
# UserPromptSubmit hook — proactive cross-review reminder.
#
# Injects a short additionalContext into every user prompt *when the session
# already has pending implementation edits*. Keeps Claude aware throughout
# a multi-turn coding task so the Stop hook is not the only safety net.
#
# Conditions for injection:
#   - dirty-<session>.log exists with ≥ AUTO_REVIEW_MIN_FILES distinct entries
#   - stop-blocked-<session> marker does NOT exist (already handled this session)
#   - ~/.claude/state/auto-review-disabled does NOT exist (global opt-out)

set -euo pipefail

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')

STATE_DIR="$HOME/.claude/state"
DIRTY_LOG="$STATE_DIR/dirty-${SESSION}.log"
BLOCKED="$STATE_DIR/stop-blocked-${SESSION}"
DISABLED="$STATE_DIR/auto-review-disabled"

MIN_FILES="${AUTO_REVIEW_MIN_FILES:-2}"

# Global opt-out
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

# Already handled this session (Stop hook fired once) — no need to nag further
[ -f "$BLOCKED" ] && { echo '{}'; exit 0; }

# No pending edits → nothing to remind about
[ -f "$DIRTY_LOG" ] || { echo '{}'; exit 0; }

FILE_COUNT=$(sort -u "$DIRTY_LOG" 2>/dev/null | wc -l)
[ "$FILE_COUNT" -lt "$MIN_FILES" ] && { echo '{}'; exit 0; }

# If the cwd repo already has a fresh reviewed marker, skip the reminder
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -n "$CWD" ] && REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
    REPO_HASH=$(printf '%s' "$REPO_ROOT" | md5sum | awk '{print $1}' | head -c 12)
    if [ -f "$STATE_DIR/reviewed-$REPO_HASH" ]; then
        echo '{}'
        exit 0
    fi
fi

REMINDER="[auto-review] This session already has pending edits across ${FILE_COUNT} files. When you finish this turn, before concluding: write a short intent brief (user's ask / what was done / key decisions, ≤150 words) to a temp file, then run 'bash ~/.claude/scripts/codex-review.sh --uncommitted --context-file <brief>'. The brief matters — without it codex only judges code quality, not whether you actually did what was asked. Apply Fix-First triage on CRITICAL findings (especially [INTENT-MISMATCH]). Opt-out: touch ~/.claude/state/auto-review-disabled"

jq -n --arg ctx "$REMINDER" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
