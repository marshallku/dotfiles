#!/usr/bin/env bash
# PreToolUse Bash hook — blocks commit/push commands until this session has
# run codex-review successfully for the current repo.
#
# Triggers on Bash commands that match: save.sh, git commit, git push.
# Allows when:
#   - ~/.claude/state/auto-review-disabled exists (global opt-out)
#   - no dirty log for this session (nothing to review)
#   - dirty log has fewer than AUTO_REVIEW_MIN_FILES entries (trivial change)
#   - git diff HEAD line count below AUTO_REVIEW_MIN_LINES
#   - a reviewed-<repo-hash> marker exists for the repo (fresh review)
#
# On block, injects instructions telling Claude to write an intent brief,
# run codex-review.sh, then re-run the blocked command.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$CMD" ] && { echo '{}'; exit 0; }

STATE_DIR="$HOME/.claude/state"
DISABLED="$STATE_DIR/auto-review-disabled"
LOG_FILE="$HOME/.claude/hooks-debug.log"

MIN_FILES="${AUTO_REVIEW_MIN_FILES:-2}"
MIN_LINES="${AUTO_REVIEW_MIN_LINES:-40}"

log() {
    echo "[$(date +%H:%M:%S)] pre-commit-gate: $*" >> "$LOG_FILE"
}

# Global opt-out
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

# Detect commit-like commands
COMMIT_LIKE=false
case "$CMD" in
    *save.sh*)
        COMMIT_LIKE=true
        ;;
    *"git commit"*|*"git push"*)
        COMMIT_LIKE=true
        ;;
esac

if [ "$COMMIT_LIKE" = false ]; then
    echo '{}'
    exit 0
fi

# Nothing edited this session → nothing to review
DIRTY_LOG="$STATE_DIR/dirty-${SESSION}.log"
if [ ! -f "$DIRTY_LOG" ]; then
    echo '{}'
    exit 0
fi

# Determine the repo for this cwd first — we want to scope the dirty-log count
# to files inside the current repo so edits in an unrelated directory don't
# inflate the gate-trigger count.
if [ -z "$CWD" ]; then
    log "allow: no cwd provided"
    echo '{}'
    exit 0
fi

if ! REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
    log "allow: cwd is not a git repo ($CWD)"
    echo '{}'
    exit 0
fi

# Count only *distinct* dirty-log entries whose path is under this repo.
# track-edit.sh appends one line per edit, so the same file can appear many
# times; dedupe before counting to match the AUTO_REVIEW_MIN_FILES semantics.
# The trailing "/" on $REPO_ROOT prevents sibling repos with the same prefix
# (e.g. /home/foo vs /home/foo-bar) from bleeding into the count.
FILE_COUNT=$(grep "^${REPO_ROOT}/" "$DIRTY_LOG" 2>/dev/null | sort -u | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -lt "$MIN_FILES" ]; then
    log "allow: only $FILE_COUNT file(s) touched in $REPO_ROOT (min $MIN_FILES)"
    echo '{}'
    exit 0
fi

REPO_HASH=$(repo_hash "$REPO_ROOT")
MARKER="$STATE_DIR/reviewed-$REPO_HASH"

# Fresh review marker → allow
if [ -f "$MARKER" ]; then
    log "allow: reviewed marker present for $REPO_ROOT"
    echo '{}'
    exit 0
fi

# Trivial diff → allow even without review. Weight untracked files (same
# rationale as auto-cross-review.sh) so a new-file-only session still gates.
TRACKED_LINES=$(git -C "$REPO_ROOT" diff HEAD 2>/dev/null | wc -l | tr -d ' ')
UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
DIFF_LINES=$(( TRACKED_LINES + UNTRACKED * 10 ))
if [ "$DIFF_LINES" -lt "$MIN_LINES" ]; then
    log "allow: $TRACKED_LINES tracked lines + $UNTRACKED untracked (weighted=$DIFF_LINES, min $MIN_LINES)"
    echo '{}'
    exit 0
fi

log "BLOCK: $CMD — no review marker for $REPO_ROOT"

# shellcheck disable=SC2016
REASON='[pre-commit-gate] Blocking this commit/push: '"$CMD"'

Repo: '"$REPO_ROOT"'
Session has '"$FILE_COUNT"' edited files with '"$DIFF_LINES"' diff lines and NO recent cross-review for this repo.

Before re-running this command:

1. Write a short intent brief (≤150 words, three sections):

    BRIEF=$(mktemp /tmp/codex-brief-XXXXXX)
    cat > "$BRIEF" <<EOF
    ## User'"'"'s request
    <paraphrase, 1-2 lines>

    ## What was done
    <what you implemented, 2-3 lines, name key files>

    ## Key decisions
    <tradeoffs, alternatives rejected, or "none">
    EOF

2. Run the review (--session scopes the diff to only files touched this session, even if already committed):

    bash ~/.claude/scripts/codex-review.sh --session '"$SESSION"' --context-file "$BRIEF"

3. Handle the verdict:
   - APPROVED → a reviewed marker is set automatically; re-run the original command.
   - REVISE   → apply Fix-First (auto-fix mechanical CRITICALs, surface judgment calls as numbered questions, pay extra attention to [INTENT-MISMATCH]). After fixing, the track-edit hook will invalidate the marker, so you must re-review before retrying.
   - error    → report the cause to the user.

Emergency bypass (use sparingly, documents the skip):
    touch ~/.claude/state/reviewed-'"$REPO_HASH"'

To disable the gate entirely for this session:
    touch ~/.claude/state/auto-review-disabled'

jq -n --arg msg "$REASON" '{permissionDecision: "deny", message: $msg}'
