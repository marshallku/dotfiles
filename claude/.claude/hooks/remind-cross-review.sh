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

. "$(dirname "$0")/_lib.sh"

LOG_FILE="$HOME/.claude/hooks-debug.log"
log() {
    echo "[$(date +%H:%M:%S)] remind-cross-review: $*" >> "$LOG_FILE"
}

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')

STATE_DIR="$HOME/.claude/state"
DIRTY_LOG="$STATE_DIR/dirty-${SESSION}.log"
BLOCKED="$STATE_DIR/stop-blocked-${SESSION}"
DISABLED="$STATE_DIR/auto-review-disabled"

MIN_FILES="${AUTO_REVIEW_MIN_FILES:-2}"

# Global opt-out
[ -f "$DISABLED" ] && { log "skip: globally disabled"; echo '{}'; exit 0; }

# Already handled this session (Stop hook fired once) — no need to nag further
[ -f "$BLOCKED" ] && { log "skip: already blocked this session"; echo '{}'; exit 0; }

# No pending edits → nothing to remind about
[ -f "$DIRTY_LOG" ] || { log "skip: no dirty log"; echo '{}'; exit 0; }

FILE_COUNT=$(sort -u "$DIRTY_LOG" 2>/dev/null | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -lt "$MIN_FILES" ]; then
    log "skip: only $FILE_COUNT file(s) (min $MIN_FILES)"
    echo '{}'
    exit 0
fi

# If the cwd repo already has a fresh reviewed marker, skip the reminder
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -n "$CWD" ] && REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
    REPO_HASH=$(repo_hash "$REPO_ROOT")
    if [ -f "$STATE_DIR/reviewed-$REPO_HASH" ]; then
        log "skip: repo already reviewed ($REPO_ROOT)"
        echo '{}'
        exit 0
    fi
fi

log "INJECT: reminder for $FILE_COUNT files"

REMINDER="[auto-review] This session already has pending edits across ${FILE_COUNT} files. When you finish this turn, before concluding: write a short intent brief (user's ask / what was done / key decisions, ≤150 words) to a temp file, then run 'bash ~/.claude/scripts/codex-review.sh --uncommitted --context-file <brief>'. The brief matters — without it codex only judges code quality, not whether you actually did what was asked. Apply Fix-First triage on CRITICAL findings (especially [INTENT-MISMATCH]). Opt-out: touch ~/.claude/state/auto-review-disabled"

jq -n --arg ctx "$REMINDER" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
