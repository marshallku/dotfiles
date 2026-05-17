#!/usr/bin/env bash
# PreToolUse Edit|Write hook — captures user intent before non-trivial sessions
# accumulate technical debt.
#
# When the session crosses the non-trivial threshold (cumulative files / lines)
# and no acked intent file exists for this session+repo, this hook BLOCKS the
# tool call and tells Claude to write a structured intent file to
# ~/docs/sources/sessions/<repo-slug>/<YYYY-MM-DD>-session-<short-id>.md.
#
# After writing, Claude runs ~/.claude/scripts/intent-finalize.sh to validate
# schema, compute content_hash/dedupe_key, and register the ack marker. The
# hook then sees the marker on the next call and allows.
#
# Allow paths:
#   - ~/.claude/state/intent-capture-disabled exists (global opt-out)
#   - AUTO_INTENT_SOFT_GATE=1 (dogfood default — warn, do not block)
#   - file being edited IS the intent file or lives in state dirs
#   - session has not crossed the non-trivial threshold yet
#   - active intent marker + ack file both present and consistent
#
# Env overrides (default in parens):
#   AUTO_INTENT_MIN_FILES    (2)   — distinct files in repo before gate fires
#   AUTO_INTENT_MIN_LINES    (40)  — weighted diff lines before gate fires
#   AUTO_INTENT_SOFT_GATE    (1)   — 1=warn-only (dogfood), 0=hard block

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

STATE_DIR="$HOME/.claude/state"
LOG_FILE="$HOME/.claude/hooks-debug.log"
DISABLED="$STATE_DIR/intent-capture-disabled"

MIN_FILES="${AUTO_INTENT_MIN_FILES:-${AUTO_REVIEW_MIN_FILES:-2}}"
MIN_LINES="${AUTO_INTENT_MIN_LINES:-${AUTO_REVIEW_MIN_LINES:-40}}"
SOFT_GATE="${AUTO_INTENT_SOFT_GATE:-1}"

log() {
    echo "[$(date +%H:%M:%S)] intent-capture: $*" >> "$LOG_FILE"
}

# Global opt-out
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }

# Always allow edits to the intent infrastructure itself. NOTE: do not blanket
# skip /tmp — repos can live there (smoke tests, scratch projects). The
# subsequent git-repo check filters out genuinely non-repo /tmp paths.
case "$FILE_PATH" in
    "$HOME"/docs/sources/sessions/*|"$STATE_DIR"/*)
        log "skip: infra/state file ($FILE_PATH)"
        echo '{}'
        exit 0
        ;;
esac

# Must be inside a git repo for the capture to make sense
FILE_DIR=$(dirname "$FILE_PATH")
if ! REPO_ROOT=$(cd "$FILE_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null); then
    log "skip: not a git repo ($FILE_PATH)"
    echo '{}'
    exit 0
fi

REPO_HASH=$(repo_hash "$REPO_ROOT")
ACTIVE_MARKER="$STATE_DIR/intent-active-${SESSION}-${REPO_HASH}.path"

# Active intent file exists AND has fresh ack → allow
if [ -f "$ACTIVE_MARKER" ]; then
    INTENT_FILE=$(cat "$ACTIVE_MARKER" 2>/dev/null || echo "")
    if [ -n "$INTENT_FILE" ] && [ -f "$INTENT_FILE" ]; then
        BASENAME=$(basename "$INTENT_FILE" .md)
        ACK_FILE="$STATE_DIR/intent-acks/${BASENAME}.ack"
        if [ -f "$ACK_FILE" ]; then
            # Stale-ack detection: intent file modified after ack → require re-ack
            ACK_MTIME=$(portable_mtime "$ACK_FILE")
            INTENT_MTIME=$(portable_mtime "$INTENT_FILE")
            if [ "$INTENT_MTIME" -le "$ACK_MTIME" ]; then
                log "allow: intent active+acked ($INTENT_FILE)"
                echo '{}'
                exit 0
            fi
            log "stale ack: intent modified after ack ($INTENT_FILE)"
            # fall through to block with a stale-ack message
            STALE_ACK=1
        fi
    fi
fi

# Threshold check: only gate non-trivial sessions
DIRTY_LOG="$STATE_DIR/dirty-${SESSION}.log"
FILE_COUNT=0
if [ -f "$DIRTY_LOG" ]; then
    FILE_COUNT=$(awk -v p="${REPO_ROOT}/" 'index($0, p) == 1' "$DIRTY_LOG" | sort -u | wc -l | tr -d ' ')
fi

# track-edit.sh fires after this hook, so the current file may not be counted yet.
# Add 1 if the projected file is not already in the log.
PROJECTED_FILE_COUNT=$FILE_COUNT
if [ -f "$DIRTY_LOG" ]; then
    if ! grep -Fxq "$FILE_PATH" "$DIRTY_LOG" 2>/dev/null; then
        PROJECTED_FILE_COUNT=$((FILE_COUNT + 1))
    fi
else
    PROJECTED_FILE_COUNT=1
fi

TRACKED_LINES=$(git -C "$REPO_ROOT" diff HEAD 2>/dev/null | wc -l | tr -d ' ')
UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
DIFF_LINES=$(( TRACKED_LINES + UNTRACKED * 10 ))

# Stale-ack short-circuit: re-ack required even on trivial follow-up
if [ "${STALE_ACK:-0}" != "1" ]; then
    if [ "$PROJECTED_FILE_COUNT" -lt "$MIN_FILES" ] && [ "$DIFF_LINES" -lt "$MIN_LINES" ]; then
        log "allow: trivial ($PROJECTED_FILE_COUNT files projected, $DIFF_LINES lines)"
        echo '{}'
        exit 0
    fi
fi

# Soft gate during first dogfood week
if [ "$SOFT_GATE" = "1" ]; then
    log "SOFT-GATE: would have blocked ($PROJECTED_FILE_COUNT files, $DIFF_LINES lines) — set AUTO_INTENT_SOFT_GATE=0 for hard block"
    echo '{}'
    exit 0
fi

# --- HARD BLOCK ---

REPO_SLUG=$(basename "$REPO_ROOT")
DATE_STR=$(date +%Y-%m-%d)
SHORT_ID=$(printf '%s' "$SESSION" | head -c 8)
INTENT_FILE="$HOME/docs/sources/sessions/${REPO_SLUG}/${DATE_STR}-session-${SHORT_ID}.md"
INTENT_DIR=$(dirname "$INTENT_FILE")
CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Detect owner/repo from git remote for the `repo:` field
REPO_REMOTE=$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || echo "")
REPO_OWNER_NAME=""
if [ -n "$REPO_REMOTE" ]; then
    REPO_OWNER_NAME=$(echo "$REPO_REMOTE" | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's/\.git$//')
fi

STALE_PREFIX=""
if [ "${STALE_ACK:-0}" = "1" ]; then
    STALE_PREFIX="STALE ACK — the intent file was modified after the user'\''s ack. You must re-ack the current intent before continuing.

"
fi

log "BLOCK: capture intent ($PROJECTED_FILE_COUNT files, $DIFF_LINES lines) → $INTENT_FILE"

REASON='[intent-capture] Blocking '"$TOOL"' on '"$FILE_PATH"'

'"$STALE_PREFIX"'This session has touched ~'"$PROJECTED_FILE_COUNT"' file(s) with '"$DIFF_LINES"' weighted diff lines in '"$REPO_ROOT"' but no captured intent.

Capture intent now so future review can compare *code-vs-intent* instead of *code-vs-prompt*. This persists to ~/docs/sources/sessions/ as an immutable SourceItem.

INTENT FILE PATH:
  '"$INTENT_FILE"'

STEP 1 — Create the directory if missing:
  mkdir -p '"$INTENT_DIR"'

STEP 2 — Use the Write tool to create the intent file with this exact frontmatter shape. Fill <BRACKETED> fields based on the original user request. REQUIRED: acceptance_criteria≥1, out_of_scope≥1, assumptions≥1. summary and commit_summary are one line each.

---
source_type: sessions
source_id: '"$SESSION"'
canonical_url: claude://session/'"$SESSION"'
captured_at: '"$CAPTURED_AT"'
extractor: claude-session-intent
content_hash: PENDING
hash_scope: intent_payload_v1
dedupe_key: PENDING
repo: '"${REPO_OWNER_NAME:-$REPO_SLUG}"'

summary: <one-line retrieval keyword summary for docs grep>
commit_summary: <one-line human-readable intent for git commit body>
tags: [<stack-axis>, <domain-axis>, <activity-axis>]

goal: <1-2 lines describing what and why>
acceptance_criteria:
  - <observable success signal — fight theater by being specific>
out_of_scope:
  - <explicit non-goal — what you will NOT touch>
assumptions:
  - <unstated assumption you are inferring from the prompt>
risk_level: low
rollback_plan: null
verification:
  e2e: not_applicable
  reason: null
blast_radius: []
plan_ref: null
supersedes: null
redaction_status: none
---

## Original prompt
<paste the user'"'"'s original prompt verbatim — if it contains secrets, set redaction_status to redacted or blocked and paraphrase here>

## Notes (append-only)


STEP 3 — Surface the captured intent to the user in their language. Show goal, acceptance_criteria, and out_of_scope. Ask them to confirm or modify. If they ask for modifications, edit the intent file and ask again. Do NOT proceed with '"$TOOL"' until the user explicitly acks (English "proceed/ok/go", Korean "진행해/오케이/예/네/응").

STEP 4 — Once the user acks, run:
  bash ~/.claude/scripts/intent-finalize.sh '"$INTENT_FILE"'

This validates the schema, computes content_hash + dedupe_key, sets the ack marker, and registers the session→intent mapping so this hook allows subsequent edits.

STEP 5 — Re-run the original '"$TOOL"' on '"$FILE_PATH"'.

Bypass mechanisms (use sparingly, document the reason):
  touch ~/.claude/state/intent-capture-disabled      # global opt-out, all sessions
  AUTO_INTENT_SOFT_GATE=1                            # warn-only mode (current: '"$SOFT_GATE"')

Schema reference: ~/docs/sources/sessions/<repo>/<date>-session-<id>.md follows the SourceItem standard (~/docs/CLAUDE.md:41) plus intent-capture-specific fields.'

jq -n --arg msg "$REASON" '{permissionDecision: "deny", message: $msg}'
