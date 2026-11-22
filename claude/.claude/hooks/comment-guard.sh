#!/usr/bin/env bash
# @hook-event: PostToolUse
# Sensor: comments an edit added that break the comment policy in CLAUDE.md (review or plan
# references, history, placeholders, commented-out code, narration) go back to Claude as
# additionalContext, each once per session. Never blocks; Bash edits arrive through
# track-bash-edit.sh, which passes the changed files as arguments.
#
# Opt-out: touch ~/.claude/state/comment-guard-disabled
# Tuning:  COMMENT_GUARD_TIMEOUT_SECS (default 15; settings.json gives the hook 20)

set -uo pipefail

. "$(dirname "$0")/_lib.sh" 2>/dev/null || true
command -v hook_event >/dev/null 2>&1 || hook_event() { :; }
command -v portable_timeout >/dev/null 2>&1 || portable_timeout() { shift; "$@"; }

SCRIPT="$(cd "$(dirname "$0")/../scripts" 2>/dev/null && pwd)/comment_guard.py"
TIMEOUT_SECS="${COMMENT_GUARD_TIMEOUT_SECS:-15}"
case "$TIMEOUT_SECS" in ''|*[!0-9]*) TIMEOUT_SECS=15 ;; esac

clean() { echo '{}'; exit 0; }

if [ -f "$HOME/.claude/state/comment-guard-disabled" ]; then
    hook_event comment-guard skip reason=disabled_marker
    clean
fi

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
case "$SESSION" in ''|*[!A-Za-z0-9_-]*) SESSION=default ;; esac

FILES=("$@")
if [ ${#FILES[@]} -eq 0 ]; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -n "$FILE_PATH" ] && FILES=("$FILE_PATH")
fi

CHECKABLE=()
for f in "${FILES[@]}"; do
    case "$f" in
        */claude-[0-9]*/*/scratchpad/*) continue ;;
        *.rs|*.ts|*.mts|*.cts|*.tsx|*.js|*.mjs|*.cjs|*.jsx|*.go|*.sh|*.bash|*.py) CHECKABLE+=("$f") ;;
    esac
done

# Most edits touch Markdown or config; a daily heartbeat instead of a record per such edit
# keeps harness-report's silence check meaningful without flooding the ledger.
BEAT="$HOME/.claude/state/comment-guard-heartbeat-$(date '+%Y-%m-%d')"
if [ ! -e "$BEAT" ]; then
    rm -f "$HOME"/.claude/state/comment-guard-heartbeat-* 2>/dev/null
    : > "$BEAT" 2>/dev/null && hook_event comment-guard heartbeat
fi
[ ${#CHECKABLE[@]} -gt 0 ] || clean

UV=$(command -v uv 2>/dev/null)
for candidate in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
    [ -n "$UV" ] && break
    [ -x "$candidate" ] && UV="$candidate"
done
if [ -z "$UV" ]; then
    hook_event comment-guard skip reason=no_uv
    clean
fi
if [ ! -f "$SCRIPT" ]; then
    hook_event comment-guard skip reason=missing_script
    clean
fi

ERR=$(mktemp "${TMPDIR:-/tmp}/comment-guard.XXXXXX" 2>/dev/null) || ERR=/dev/null
FINDINGS=$(portable_timeout "$TIMEOUT_SECS" "$UV" run -q --script "$SCRIPT" hook --session "$SESSION" \
    "${CHECKABLE[@]}" 2>"$ERR")
STATUS=$?
DETAIL=$(tail -c 300 "$ERR" 2>/dev/null | tr '\n' ' ')
[ "$ERR" != /dev/null ] && rm -f "$ERR"

if [ "$STATUS" -eq 124 ]; then
    hook_event comment-guard error reason=timeout files="${#CHECKABLE[@]}"
    clean
fi
if [ "$STATUS" -ne 0 ]; then
    hook_event comment-guard error reason=exit_"$STATUS" detail="$DETAIL"
    clean
fi

COUNT=$(printf '%s' "$FINDINGS" | grep -c '^- ')
hook_event comment-guard checked files="${#CHECKABLE[@]}" findings="$COUNT"
[ "$COUNT" -gt 0 ] || clean

jq -nc --arg ctx "Comment policy (CLAUDE.md): delete or rewrite these comments you just added. A comment stays only as a present-tense why the code cannot express; history and review notes go in the commit message.
$FINDINGS" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
exit 0
