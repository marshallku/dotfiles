#!/usr/bin/env bash
# PreToolUse Bash hook — blocks commit/push commands until this session has
# (a) run codex-review successfully for the current repo, and (b) captured a
# valid intent file in ~/docs/sources/sessions/ (hard-gate mode only).
#
# Triggers on Bash commands that match: save.sh, git commit, git push.
# Allows when:
#   - ~/.claude/state/auto-review-disabled exists (global opt-out)
#   - no dirty log for this session (nothing to review)
#   - dirty log has fewer than AUTO_REVIEW_MIN_FILES entries (trivial change)
#   - git diff HEAD line count below AUTO_REVIEW_MIN_LINES
#   - a reviewed-<repo-hash> marker exists AND intent gate passes
#
# Intent gate (hard-gate mode only, AUTO_INTENT_SOFT_GATE=0):
#   - intent-active-<session>-<repo>.path marker exists
#   - intent file referenced by the marker exists on disk
#   - intent-acks/<basename>.ack marker exists and is newer than the intent file
#   - verification.e2e field is one of required|not_applicable|deferred (schema
#     enforced by intent-finalize.sh — this is a sanity recheck)
#
# On block, injects instructions for Claude to write an intent brief or
# finalize the intent file before re-running the blocked command.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

[ -z "$CMD" ] && { echo '{}'; exit 0; }

STATE_DIR="$HOME/.claude/state"
DISABLED="$STATE_DIR/auto-review-disabled"
LOG_FILE="$HOME/.claude/hooks-debug.log"

MIN_FILES="${AUTO_REVIEW_MIN_FILES:-2}"
MIN_LINES="${AUTO_REVIEW_MIN_LINES:-40}"
INTENT_DISABLED="$STATE_DIR/intent-capture-disabled"
INTENT_SOFT_GATE="${AUTO_INTENT_SOFT_GATE:-1}"

log() {
    echo "[$(date +%H:%M:%S)] pre-commit-gate: $*" >> "$LOG_FILE"
}

# Verify the active intent file for this session+repo is in a shippable state.
# Echoes one of: ok | missing | stale_ack | bad_e2e | parse_fail
# Followed by an optional second token containing the intent file path or
# offending field. Pure read; never modifies state.
check_intent_state() {
    local session="$1" repo_hash="$2"
    local active="$STATE_DIR/intent-active-${session}-${repo_hash}.path"
    if [ ! -f "$active" ]; then
        echo "missing"
        return 0
    fi
    local intent
    intent=$(cat "$active" 2>/dev/null || echo "")
    if [ -z "$intent" ] || [ ! -f "$intent" ]; then
        echo "missing $intent"
        return 0
    fi
    local basename
    basename=$(basename "$intent" .md)
    local ack="$STATE_DIR/intent-acks/${basename}.ack"
    if [ ! -f "$ack" ]; then
        echo "missing $intent"
        return 0
    fi
    local ack_mt intent_mt
    ack_mt=$(portable_mtime "$ack")
    intent_mt=$(portable_mtime "$intent")
    if [ "$intent_mt" -gt "$ack_mt" ]; then
        echo "stale_ack $intent"
        return 0
    fi
    # Sanity check the verification.e2e field. The intent-finalize.sh validator
    # already enforced this, but the file is mutable below ## Notes so make sure
    # nothing pathological slipped in via subsequent edits to the frontmatter.
    local e2e
    e2e=$(awk '
        /^---$/ { c++; if(c==2) exit; next }
        c==1 && /^verification:$/ { flag=1; next }
        c==1 && flag && /^[a-z_]+:/ && !/^  / { flag=0 }
        c==1 && flag && /^  e2e: / { sub(/^  e2e: /, ""); print; exit }
    ' "$intent" 2>/dev/null || true)
    case "$e2e" in
        required|not_applicable|deferred)
            echo "ok $intent"
            ;;
        *)
            echo "bad_e2e $intent"
            ;;
    esac
}

# Heuristic: scan the recent transcript for evidence that an e2e/test run
# actually happened this session. Returns 0 if found, 1 otherwise.
e2e_evidence_in_transcript() {
    local transcript="$1"
    [ -z "$transcript" ] || [ ! -f "$transcript" ] && return 1
    # Look at the last 64KB of transcript for tool invocations or terminal
    # output that smells like a test/e2e run. Heuristic only — the schema
    # already enforces declaration; this just adds a soft signal.
    tail -c 65536 "$transcript" 2>/dev/null | grep -qiE \
        '(playwright|cypress|@playwright|test:e2e|npm run e2e|pnpm e2e|bun test|jest|vitest|cargo test|go test|pytest|rspec)' \
        && return 0
    return 1
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

# Resolve cwd → repo → pending marker BEFORE checking dirty log. A pure
# /codex-delegate --write session never invokes track-edit.sh, so no
# dirty log exists for this session — but codex-delegate-pending DOES,
# and we must respect it as proof the change is non-trivial.
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

REPO_HASH=$(repo_hash "$REPO_ROOT")
MARKER="$STATE_DIR/reviewed-$REPO_HASH"
DELEGATE_PENDING="$STATE_DIR/codex-delegate-pending-$REPO_HASH"

# Nothing edited via Claude this session AND no pending delegate → nothing
# to review. The pending marker overrides this fast-path because a
# delegate-only session has no dirty log but still has writes.
DIRTY_LOG="$STATE_DIR/dirty-${SESSION}.log"
if [ ! -f "$DIRTY_LOG" ] && [ ! -f "$DELEGATE_PENDING" ]; then
    echo '{}'
    exit 0
fi

# Count only *distinct* dirty-log entries whose path is under this repo.
# track-edit.sh appends one line per edit, so the same file can appear many
# times; dedupe before counting to match the AUTO_REVIEW_MIN_FILES semantics.
# The trailing "/" on $REPO_ROOT prevents sibling repos with the same prefix
# (e.g. /home/foo vs /home/foo-bar) from bleeding into the count. When the
# dirty log is missing entirely (delegate-only session) skip grep — `set -e`
# + `pipefail` would otherwise kill the script on grep's non-zero exit
# before we reach the pending-marker logic below.
FILE_COUNT=0
if [ -f "$DIRTY_LOG" ]; then
    # awk index() does literal substring matching, no regex. This avoids two
    # grep failure modes that would trip `set -euo pipefail`: (a) zero matches
    # → grep exit 1, (b) repo path containing regex metachars (e.g. "[")
    # → grep exit 2 (parse error). Both would otherwise abort the hook
    # before reaching the pending-marker logic.
    FILE_COUNT=$(awk -v p="${REPO_ROOT}/" 'index($0, p) == 1' "$DIRTY_LOG" | sort -u | wc -l | tr -d ' ')
fi

# Honor the file-count early-exit only when codex-delegate has not run with
# write access since the last cross-review. The pending flag means codex
# wrote files outside Claude's Edit/Write tools — track-edit.sh did not
# count those, so dirty-log undercounts and the early-exit would falsely
# allow the commit. The flag is cleared by mark_repo_reviewed() in
# codex-review.sh on APPROVED.
if [ "$FILE_COUNT" -lt "$MIN_FILES" ] && [ ! -f "$DELEGATE_PENDING" ]; then
    log "allow: only $FILE_COUNT file(s) touched in $REPO_ROOT (min $MIN_FILES)"
    echo '{}'
    exit 0
fi

# Fresh review marker → check intent gate before allowing
if [ -f "$MARKER" ]; then
    # Intent gate is a no-op in soft-gate or globally-disabled mode. The
    # review marker alone is the gate, same as before this hook was extended.
    if [ "$INTENT_SOFT_GATE" = "1" ] || [ -f "$INTENT_DISABLED" ]; then
        log "allow: reviewed marker present (intent gate soft/disabled)"
        echo '{}'
        exit 0
    fi

    INTENT_STATE=$(check_intent_state "$SESSION" "$REPO_HASH")
    INTENT_KIND=$(echo "$INTENT_STATE" | awk '{print $1}')
    INTENT_PATH=$(echo "$INTENT_STATE" | awk '{print $2}')

    case "$INTENT_KIND" in
        ok)
            # Final soft-signal e2e check when required
            E2E_DECL=$(awk '
                /^---$/ { c++; if(c==2) exit; next }
                c==1 && /^verification:$/ { flag=1; next }
                c==1 && flag && /^[a-z_]+:/ && !/^  / { flag=0 }
                c==1 && flag && /^  e2e: / { sub(/^  e2e: /, ""); print; exit }
            ' "$INTENT_PATH" 2>/dev/null || true)
            if [ "$E2E_DECL" = "required" ] && ! e2e_evidence_in_transcript "$TRANSCRIPT"; then
                log "BLOCK: e2e=required but no test/e2e evidence in transcript"
                # shellcheck disable=SC2016
                E2E_MSG='[pre-commit-gate] Blocking '"$CMD"'

Intent file declares `verification.e2e: required` but no test/e2e run is
visible in the recent transcript. Either:

1. Run the relevant test/e2e suite now and surface the result, OR
2. If e2e is no longer required, edit the intent file to set
   `verification.e2e: deferred` with a `reason`, then re-ack:
       bash ~/.claude/scripts/intent-finalize.sh '"$INTENT_PATH"'

Intent file: '"$INTENT_PATH"'

Bypass: touch ~/.claude/state/intent-capture-disabled  (session-wide)'
                jq -n --arg msg "$E2E_MSG" '{permissionDecision: "deny", message: $msg}'
                exit 0
            fi
            log "allow: reviewed marker + intent gate passed ($INTENT_PATH)"
            echo '{}'
            exit 0
            ;;
        missing)
            log "BLOCK: reviewed but no intent file for session"
            # shellcheck disable=SC2016
            INTENT_MSG='[pre-commit-gate] Blocking '"$CMD"'

The cross-review passed, but this session has no captured intent file —
the long-term comparison artifact is missing. Capture intent before
committing so future maintainers can read *why* this change was made
without needing the original prompt.

Make an Edit/Write call in '"$REPO_ROOT"' and intent-capture.sh will
instruct you. Or to bypass for this commit:
  touch ~/.claude/state/intent-capture-disabled

Bypass markers (use sparingly):
  touch ~/.claude/state/intent-capture-disabled   (intent only)
  touch ~/.claude/state/auto-review-disabled      (review + intent)'
            jq -n --arg msg "$INTENT_MSG" '{permissionDecision: "deny", message: $msg}'
            exit 0
            ;;
        stale_ack)
            log "BLOCK: intent file edited after ack ($INTENT_PATH)"
            # shellcheck disable=SC2016
            STALE_MSG='[pre-commit-gate] Blocking '"$CMD"'

The intent file was modified after the user'\''s ack — the ack is now
stale. Re-confirm with the user, then run:
  bash ~/.claude/scripts/intent-finalize.sh '"$INTENT_PATH"'

Intent file: '"$INTENT_PATH"''
            jq -n --arg msg "$STALE_MSG" '{permissionDecision: "deny", message: $msg}'
            exit 0
            ;;
        bad_e2e)
            log "BLOCK: verification.e2e invalid in $INTENT_PATH"
            # shellcheck disable=SC2016
            BADE2E_MSG='[pre-commit-gate] Blocking '"$CMD"'

The intent file at '"$INTENT_PATH"' has an invalid `verification.e2e`
value. Must be one of: required, not_applicable, deferred.
Edit the file and re-run intent-finalize.sh.'
            jq -n --arg msg "$BADE2E_MSG" '{permissionDecision: "deny", message: $msg}'
            exit 0
            ;;
        *)
            log "WARN: unexpected intent check state '$INTENT_KIND', falling through to allow"
            echo '{}'
            exit 0
            ;;
    esac
fi

# Trivial diff → allow even without review. Weight untracked files (same
# rationale as auto-cross-review.sh) so a new-file-only session still gates.
# As with the file-count check above, the codex-delegate-pending flag
# overrides the trivial-diff allow-path: we cannot trust the diff size to
# represent the change because codex may have written and reverted, or
# made small but consequential edits, outside Claude's tracked path.
TRACKED_LINES=$(git -C "$REPO_ROOT" diff HEAD 2>/dev/null | wc -l | tr -d ' ')
UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
DIFF_LINES=$(( TRACKED_LINES + UNTRACKED * 10 ))
if [ "$DIFF_LINES" -lt "$MIN_LINES" ] && [ ! -f "$DELEGATE_PENDING" ]; then
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

# NESTTY_HOOK_PUBLISH: claude.commit_blocked $(jq -n --arg c "$CMD" '{reason:"missing-review",command:$c}')
command -v nestctl >/dev/null && nestctl event publish claude.commit_blocked --quiet "$(jq -n --arg c "$CMD" '{reason:"missing-review",command:$c}')" &
# NESTTY_HOOK_PUBLISH_END
jq -n --arg msg "$REASON" '{permissionDecision: "deny", message: $msg}'
