#!/usr/bin/env bash
# Stop hook — if this session left uncommitted implementation changes without
# an external cross-review, block the stop once and inject a reminder telling
# Claude to run codex-review.sh before concluding.
#
# Fires at most once per session (stop-blocked-<session> marker).
# Skips if:
#   - ~/.claude/state/auto-review-disabled exists (opt-out)
#   - fewer than AUTO_REVIEW_MIN_FILES (default 2) distinct files touched
#   - git diff HEAD line count below AUTO_REVIEW_MIN_LINES (default 40)
#   - last assistant message ends with "?" (Claude is asking a clarification)
#
# Env overrides:
#   AUTO_REVIEW_MIN_FILES  (default 2)
#   AUTO_REVIEW_MIN_LINES  (default 40)

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

LOG_FILE="$HOME/.claude/hooks-debug.log"
INPUT=$(cat)

SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

STATE_DIR="$HOME/.claude/state"
DIRTY_LOG="$STATE_DIR/dirty-${SESSION}.log"
BLOCKED="$STATE_DIR/stop-blocked-${SESSION}"
DISABLED="$STATE_DIR/auto-review-disabled"

MIN_FILES="${AUTO_REVIEW_MIN_FILES:-2}"
MIN_LINES="${AUTO_REVIEW_MIN_LINES:-40}"

log() {
    echo "[$(date +%H:%M:%S)] auto-cross-review: $*" >> "$LOG_FILE"
}

# Global opt-out
if [ -f "$DISABLED" ]; then
    echo '{}'
    exit 0
fi

# Nothing tracked this session → nothing to review
if [ ! -f "$DIRTY_LOG" ]; then
    echo '{}'
    exit 0
fi

# Already blocked once this session → let this stop proceed
if [ -f "$BLOCKED" ]; then
    echo '{}'
    exit 0
fi

# Count unique files touched
FILE_COUNT=$(sort -u "$DIRTY_LOG" 2>/dev/null | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -lt "$MIN_FILES" ]; then
    log "skip: only $FILE_COUNT file(s) touched (min $MIN_FILES)"
    echo '{}'
    exit 0
fi

# Check git diff size if cwd is a repo — skip near-trivial changes even if spread across files
if [ -n "$CWD" ] && REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
    # If this repo already has a fresh reviewed marker, skip (pre-commit-gate handled it)
    REPO_HASH=$(repo_hash "$REPO_ROOT")
    if [ -f "$STATE_DIR/reviewed-$REPO_HASH" ]; then
        log "skip: repo already reviewed this session ($REPO_ROOT)"
        echo '{}'
        exit 0
    fi

    # git diff HEAD only shows tracked changes; a session that added only new
    # files (common during scaffolding) would have DIFF_LINES=0 and get skipped
    # here even though there are real, un-reviewed edits. Weight untracked
    # files into the count so those sessions still trigger the gate.
    TRACKED_LINES=$(git -C "$REPO_ROOT" diff HEAD 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    DIFF_LINES=$(( TRACKED_LINES + UNTRACKED * 10 ))
    if [ "$DIFF_LINES" -lt "$MIN_LINES" ]; then
        log "skip: $TRACKED_LINES tracked lines + $UNTRACKED untracked (weighted=$DIFF_LINES, min $MIN_LINES)"
        echo '{}'
        exit 0
    fi
fi

# Clarification-pause heuristic — if the last assistant message ends with a
# question mark, Claude is likely waiting for the user, not finishing a task.
# Uses jq to extract the last assistant text field robustly (the previous
# grep-based regex was fragile to JSONL layout changes).
if [ -f "$TRANSCRIPT" ]; then
    LAST_TEXT=$(tail -c 16384 "$TRANSCRIPT" 2>/dev/null \
        | jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
        | tail -n1 \
        || true)
    if echo "$LAST_TEXT" | grep -qE '\?\s*$'; then
        log "skip: last message looks like a clarification question"
        echo '{}'
        exit 0
    fi
fi

# All checks passed — block this stop and inject the review reminder
touch "$BLOCKED"
log "BLOCK: injecting review reminder ($FILE_COUNT files)"

REASON="[auto-review] You edited $FILE_COUNT files this session with no external cross-review yet. Before concluding this turn, do the following in order:

1. Write a SHORT intent brief to a temp file (≤150 words total, three sections):

    BRIEF=\$(mktemp /tmp/codex-brief.XXXXXX.md)
    cat > \"\$BRIEF\" <<'EOF'
    ## User's request
    <paraphrase of what the user asked for, 1-2 lines>

    ## What was done
    <what you actually implemented, 2-3 lines, name the key files/functions>

    ## Key decisions
    <tradeoffs, alternatives rejected, scope deliberately excluded, or \"none\">
    EOF

2. Run the cross-review WITH that context:

    bash ~/.claude/scripts/codex-review.sh --uncommitted --context-file \"\$BRIEF\"

3. Parse the output:
   - exit 0 (VERDICT: APPROVED) → summarize briefly and conclude the turn
   - exit 1 (VERDICT: REVISE) → apply Fix-First (auto-fix mechanical CRITICAL findings immediately, surface judgment calls as numbered questions). Pay extra attention to [INTENT-MISMATCH] findings — these mean codex thinks the diff does not match the stated intent.
   - exit 2 (error) → report the error to the user and conclude

Rules:
  - Codex is a peer LLM, not ground truth. Surface disagreements rather than silently accepting.
  - Be honest in the brief — if you skipped something, say so. Hiding gaps defeats the review.
  - Suppress style/naming/TODO noise (same rules as /review skill).
  - This reminder fires at most once per session. To disable entirely: touch ~/.claude/state/auto-review-disabled"

jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
