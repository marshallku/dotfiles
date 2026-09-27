#!/usr/bin/env bash
# Read-only Claude reviewer. stdout: final message; stderr: progress.
# Same runner contract as codex-exec.sh: 0 success, 2 error, 3 missing resume, 124 timeout.
set -euo pipefail
. "$(dirname "$0")/../hooks/_lib.sh"

PROMPT_FILE=""
THREAD_KEY=""
RESUME=0
TIMEOUT=540
MODEL=""
EFFORT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt-file|--thread-key|--timeout|--model|--effort)
            [[ $# -ge 2 ]] || { echo "[claude-exec] $1 requires a value" >&2; exit 2; } ;;
    esac
    case "$1" in
        --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
        --thread-key) THREAD_KEY="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --effort) EFFORT="$2"; shift 2 ;;
        --resume) RESUME=1; shift ;;
        *) echo "[claude-exec] unknown argument: $1" >&2; exit 2 ;;
    esac
done
command -v claude >/dev/null || { echo '[claude-exec] Claude CLI is required; no same-model fallback.' >&2; exit 2; }
[[ -f "$PROMPT_FILE" ]] || { echo '[claude-exec] --prompt-file is required' >&2; exit 2; }
RULES="$HOME/.codex/AGENTS.md"
[[ -f "$RULES" ]] || { echo "[claude-exec] Missing shared review contract: $RULES" >&2; exit 2; }
THREAD_FILE=""
if [[ -n "$THREAD_KEY" ]]; then
    SAFE_KEY=$(printf '%s' "$THREAD_KEY" | tr -c 'A-Za-z0-9._-' '_')
    THREAD_FILE="$HOME/.claude/state/claude-review-threads/$SAFE_KEY"
fi
ARGS=(-p --safe-mode --restricted --setting-sources "" --disable-slash-commands
    --strict-mcp-config --mcp-config '{"mcpServers":{}}'
    --tools 'Read,Glob,Grep' --allowedTools 'Read,Glob,Grep' --permission-mode dontAsk
    --output-format stream-json --verbose --append-system-prompt-file "$RULES")
if [[ "$RESUME" == 1 ]]; then
    [[ -n "$THREAD_FILE" && -s "$THREAD_FILE" ]] || exit 3
    RESUME_ID=$(cat "$THREAD_FILE")
    [[ "$RESUME_ID" =~ ^[a-fA-F0-9-]{36}$ ]] || exit 3
    ARGS+=(--resume "$RESUME_ID")
fi
[[ -z "$MODEL" ]] || ARGS+=(--model "$MODEL")
[[ -z "$EFFORT" ]] || ARGS+=(--effort "$EFFORT")
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/claude-review.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
START_SECONDS=$SECONDS
set +e
portable_timeout "$TIMEOUT" claude "${ARGS[@]}" < "$PROMPT_FILE" 2>"$SCRATCH/error" \
    | tee "$SCRATCH/events" \
    | jq -r --unbuffered '
        if .type == "system" and .subtype == "init" then "[claude] session " + .session_id
        elif .type == "assistant" then
            .message.content[]? | select(.type == "tool_use") | "[claude] " + .name
        elif .type == "result" then "[claude] " + .subtype
        else empty end' >&2
STATUS=${PIPESTATUS[0]}
set -e
if [[ "$STATUS" == 124 ]]; then
    echo "[claude-exec] timed out after ${TIMEOUT}s" >&2
    exit 124
fi
if [[ "$RESUME" == 1 ]] && grep -qiE 'No conversation found|No session found' "$SCRATCH/error"; then
    exit 3
fi
if [[ "$STATUS" != 0 ]]; then
    cat "$SCRATCH/error" >&2
    echo "[claude-exec] exited $STATUS" >&2
    exit 2
fi
if ! jq -es '[.[] | select(.type == "result")] | last |
    select(.subtype == "success" and .is_error != true and (.result | type == "string"))' \
    "$SCRATCH/events" > "$SCRATCH/result"; then
    cat "$SCRATCH/error" >&2
    echo '[claude-exec] No successful result; approval is not available.' >&2
    exit 2
fi
if [[ -n "$THREAD_FILE" ]]; then
    SESSION_ID=$(jq -r '.session_id // empty' "$SCRATCH/result")
    if [[ "$SESSION_ID" =~ ^[a-fA-F0-9-]{36}$ ]]; then
        mkdir -p "$(dirname "$THREAD_FILE")"
        TMP_THREAD=$(mktemp "${THREAD_FILE}.XXXXXX")
        printf '%s\n' "$SESSION_ID" > "$TMP_THREAD"
        mv -f "$TMP_THREAD" "$THREAD_FILE"
    fi
fi
# Keep Claude usage separate from the Codex spend ledger.
mkdir -p "$HOME/.claude/state"
jq -c --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg repo "$PWD" \
    --arg key "$THREAD_KEY" --argjson elapsed "$((SECONDS - START_SECONDS))" \
    --argjson round "${CODEX_REVIEW_ROUND:-0}" --argjson resumed "$RESUME" \
    '{ts:$ts, provider:"claude", repo:$repo, thread_key:$key, session_id:.session_id,
      round:$round, resumed:($resumed == 1), elapsed_seconds:$elapsed,
      usage_reported:(.usage != null), usage:.usage, model_usage:.modelUsage,
      cost_usd:.total_cost_usd, verdict:(.result | split("\n") | map(select(startswith("VERDICT: "))) | last)}' \
    "$SCRATCH/result" >> "$HOME/.claude/state/claude-review-usage.jsonl" \
    || echo '[claude-exec] Could not record usage' >&2
jq -r '.result' "$SCRATCH/result"
