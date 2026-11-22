#!/usr/bin/env bash
# @hook-event: Stop
# Stop hook — after a work unit is committed (~/save.sh succeeded) in a session whose context has
# grown past SESSION_SIZE_NUDGE_TOKENS (default 300k), tell the user once that the next unit is
# cheaper in a fresh session. A note to the user (systemMessage), never a block.
# auto-handoff.sh already writes the handoff, so picking up again is cheap.
# Opt-out: ~/.claude/state/session-size-disabled

set -uo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
STATE_DIR="$HOME/.claude/state"
THRESHOLD="${SESSION_SIZE_NUDGE_TOKENS:-300000}"
TAIL_LINES=4000
log() { hook_log session-size "$@"; }

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
# Sessions already nudged, one id per line, never expired: a long session must not get the note
# twice, and at ~37 bytes per nudged session the list stays small.
NUDGED="$STATE_DIR/session-size-nudged.list"

if [ -f "$STATE_DIR/session-size-disabled" ]; then log "allow: disabled"; echo '{}'; exit 0; fi
if [ -z "$SESSION" ]; then log "skip: no session id"; echo '{}'; exit 0; fi
if [ -f "$NUDGED" ] && grep -qxF -- "$SESSION" "$NUDGED" 2>/dev/null; then
    log "skip: already nudged"; echo '{}'; exit 0
fi
if [ ! -f "$TRANSCRIPT" ]; then log "skip: no transcript"; echo '{}'; exit 0; fi
case "$THRESHOLD" in ''|*[!0-9]*) THRESHOLD=300000 ;; esac

# Context of the latest assistant turn: everything the model re-read to produce it.
CONTEXT=$(tail -n "$TAIL_LINES" "$TRANSCRIPT" 2>/dev/null | jq -r '
    select(.type == "assistant" and (.isSidechain // false) == false) | .message.usage // empty
    | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)' 2>/dev/null \
    | tail -n 1 | tr -dc '0-9')
CONTEXT=${CONTEXT:-0}
if [ "$CONTEXT" -le "$THRESHOLD" ]; then
    log "skip: context ${CONTEXT} <= ${THRESHOLD}"
    echo '{}'; exit 0
fi

# A work unit committed by THIS session: ~/save.sh appends {session, repo, sha} to the save
# ledger after a successful commit and push, using CLAUDE_CODE_SESSION_ID. Transcript guesses
# could not tell a skipped `false && ~/save.sh` from a real run.
LEDGER="${SAVE_LEDGER:-$STATE_DIR/save-ledger.jsonl}"
SAVED=0
if [ -n "$SESSION" ] && [ -f "$LEDGER" ]; then
    SAVED=$(jq -r --arg s "$SESSION" 'select(.session == $s) | .sha' "$LEDGER" 2>/dev/null | grep -c . || true)
fi
SAVED=$(printf '%s' "${SAVED:-0}" | tr -dc '0-9')
if [ "${SAVED:-0}" -eq 0 ]; then
    log "skip: context ${CONTEXT} but this session has not committed through save.sh"
    echo '{}'; exit 0
fi

printf '%s\n' "$SESSION" >> "$NUDGED"
log "NUDGE: context ${CONTEXT} > ${THRESHOLD} after ${SAVED} save.sh run(s)"
hook_event session-size nudge context="$CONTEXT" saves="$SAVED"
K=$(( CONTEXT / 1000 ))
MESSAGE="💡 This session now re-reads ~${K}k tokens per turn, and a commit has landed in it. If the current work unit is done, start the next one in a fresh session: it is cheaper and the handoff is in ~/.claude/handoffs/. (once per session · mute: touch ~/.claude/state/session-size-disabled)"
jq -n --arg msg "$MESSAGE" '{systemMessage: $msg}'
