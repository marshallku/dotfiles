#!/usr/bin/env bash
# PreToolUse Bash hook — blocks commit/push commands until this session has
# (a) run codex-review successfully for the current repo, and (b) captured a
# valid intent file in ~/docs/sources/sessions/ (hard-gate mode only).
#
# Triggers on Bash commands that match: save.sh, git commit, git push.
# Allows when:
#   - ~/.claude/state/auto-review-disabled exists (global opt-out)
#   - no implementation changes since the work-unit baseline
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

INTENT_DISABLED="$STATE_DIR/intent-capture-disabled"
INTENT_SOFT_GATE="${AUTO_INTENT_SOFT_GATE:-1}"

log() {
    # Delegates to _lib.sh so every hook shares one date-stamped format.
    hook_log pre-commit-gate "$@"
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

# Resolve the repository independently of Edit/Write tracking.
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

# Fresh, session-owned, non-expired review marker → check intent gate before
# allowing. reviewed_marker_valid rejects changed-content/legacy/cross-session markers.
if reviewed_marker_valid "$MARKER" "$SESSION" "$REPO_ROOT"; then
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
                jq -n --arg msg "$E2E_MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
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
            jq -n --arg msg "$INTENT_MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
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
            jq -n --arg msg "$STALE_MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
            exit 0
            ;;
        bad_e2e)
            log "BLOCK: verification.e2e invalid in $INTENT_PATH"
            # shellcheck disable=SC2016
            BADE2E_MSG='[pre-commit-gate] Blocking '"$CMD"'

The intent file at '"$INTENT_PATH"' has an invalid `verification.e2e`
value. Must be one of: required, not_applicable, deferred.
Edit the file and re-run intent-finalize.sh.'
            jq -n --arg msg "$BADE2E_MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
            exit 0
            ;;
        *)
            log "WARN: unexpected intent check state '$INTENT_KIND', falling through to allow"
            echo '{}'
            exit 0
            ;;
    esac
fi

if ! review_required "$REPO_ROOT" "$SESSION" && [ ! -f "$DELEGATE_PENDING" ]; then
    log "allow: no implementation changes in this work unit"
    echo '{}'
    exit 0
fi

log "BLOCK: $CMD — no review marker for $REPO_ROOT"

# shellcheck disable=SC2016
REASON="[pre-commit-gate] This work unit has no approval matching the current repository and staged content.
Run /cross-review for session $SESSION in $REPO_ROOT. Use its evidence-first triage and maximum three rounds.
If no session baseline exists, identify the actual starting commit and pass --base <commit>; do not guess.
After fixes, run relevant tests and re-review with --resume --response-file <finding dispositions and test results>.
Only a full review grants approval. Stage the reviewed file versions; partial intermediate staging requires review.
On error or unresolved disagreement, report the evidence. Never fabricate an approval marker."

# COPAD_HOOK_PUBLISH: claude.commit_blocked $(jq -n --arg c "$CMD" '{reason:"missing-review",command:$c}')
command -v coctl >/dev/null && coctl event publish claude.commit_blocked --quiet "$(jq -n --arg c "$CMD" '{reason:"missing-review",command:$c}')" >/dev/null 2>&1 &
# COPAD_HOOK_PUBLISH_END
jq -n --arg msg "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
