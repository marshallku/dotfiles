#!/usr/bin/env bash
# codex-exec.sh — shared `codex exec` runner for the codex-* wrappers.
#
# Replaces the old codex-companion.sh (@openai/codex-plugin-cc app-server
# runtime). That layer existed for background job management, broker reuse,
# and progress streaming; only the last one was ever load-bearing, and it
# cost a leaking app-server daemon per workspace plus two behaviour
# regressions (config.toml `notify` never fired; resume could not target a
# thread id). `codex exec --json` gives us the same stream natively.
#
# Contract for callers:
#   stdout — the final assistant message ONLY (safe to parse for VERDICT)
#   stderr — rendered progress lines (💬 🧠 ▶ ✓ 🟢 🔵 ❌)
#
# Usage:
#   codex-exec.sh --prompt-file F [options]
#   codex-exec.sh --prompt "text"  [options]
#
# Options:
#   --write             workspace-write sandbox (default: read-only)
#   --model M           model override (codex -m)
#   --effort E          reasoning effort: none|minimal|low|medium|high|xhigh
#   --timeout SECS      abort after SECS (default 600)
#   --thread-key KEY    persist/lookup this run's thread id under KEY, so a
#                       later --resume continues exactly this thread
#   --resume            resume the thread stored under --thread-key instead
#                       of starting a fresh one
#   --quiet             suppress progress rendering on stderr
#
# Exit codes:
#   0   completed
#   2   usage error / codex failure
#   3   resume unavailable (no stored thread, or codex has no such rollout) —
#       callers should retry with a fresh prompt
#   124 timed out
#
# Thread ids live in ~/.claude/state/codex-threads/<key>. Keys are chosen by
# the caller (e.g. plan-<repo_hash>, review-<repo_hash>-<session>) so that
# unrelated codex calls can no longer hijack a resume — the failure mode of
# the companion's workspace-wide `--resume-last`.

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

PROMPT_FILE=""
PROMPT_TEXT=""
WRITE=0
MODEL=""
EFFORT=""
TIMEOUT="${CODEX_EXEC_TIMEOUT:-600}"
THREAD_KEY=""
RESUME=0
QUIET=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
        --prompt)      PROMPT_TEXT="$2"; shift 2 ;;
        --write)       WRITE=1; shift ;;
        --model)       MODEL="$2"; shift 2 ;;
        --effort)      EFFORT="$2"; shift 2 ;;
        --timeout)     TIMEOUT="$2"; shift 2 ;;
        --thread-key)  THREAD_KEY="$2"; shift 2 ;;
        --resume)      RESUME=1; shift ;;
        --quiet)       QUIET=1; shift ;;
        -h|--help)     sed -n '2,40p' "$0"; exit 0 ;;
        *)
            echo "[codex-exec] unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if ! command -v codex >/dev/null 2>&1; then
    echo "[codex-exec] codex CLI not found in PATH" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "[codex-exec] jq not found in PATH" >&2
    exit 2
fi

# Resolve the prompt to a file — it is always fed through stdin (`-`), never
# argv. A large review diff on argv overflows the exec arg limit, and that is
# exactly why the old wrapper needed --prompt-file.
CLEANUP_PROMPT=0
if [[ -n "$PROMPT_TEXT" ]]; then
    PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-exec-prompt.XXXXXX")
    CLEANUP_PROMPT=1
    printf '%s' "$PROMPT_TEXT" > "$PROMPT_FILE"
fi
if [[ -z "$PROMPT_FILE" ]]; then
    echo "[codex-exec] one of --prompt-file / --prompt is required" >&2
    exit 2
fi
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "[codex-exec] prompt file not found: $PROMPT_FILE" >&2
    exit 2
fi

MSG_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-exec-msg.XXXXXX")
EVENTS_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-exec-events.XXXXXX")
ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-exec-err.XXXXXX")
cleanup() {
    rm -f "$MSG_FILE" "$EVENTS_FILE" "$ERR_FILE"
    [[ "$CLEANUP_PROMPT" -eq 1 ]] && rm -f "$PROMPT_FILE"
    return 0
}
trap cleanup EXIT

SANDBOX="read-only"
[[ "$WRITE" -eq 1 ]] && SANDBOX="workspace-write"

THREAD_DIR="$HOME/.claude/state/codex-threads"
THREAD_FILE=""
if [[ -n "$THREAD_KEY" ]]; then
    # Keys land in a filename; keep them to a safe charset.
    SAFE_KEY=$(printf '%s' "$THREAD_KEY" | tr -c 'A-Za-z0-9._-' '_')
    THREAD_FILE="$THREAD_DIR/$SAFE_KEY"
fi

# Resume needs a stored thread id. Missing one is not an error — it is the
# "round 1 hasn't happened (or was GC'd)" case, which callers handle by
# rerunning fresh.
RESUME_ID=""
if [[ "$RESUME" -eq 1 ]]; then
    if [[ -z "$THREAD_FILE" ]]; then
        echo "[codex-exec] --resume requires --thread-key" >&2
        exit 2
    fi
    RESUME_ID=$(cat "$THREAD_FILE" 2>/dev/null || true)
    if [[ -z "$RESUME_ID" ]]; then
        echo "[codex-exec] no stored thread for key ${THREAD_KEY}" >&2
        exit 3
    fi
fi

ARGS=(exec)
if [[ -n "$RESUME_ID" ]]; then
    # `resume` takes the sandbox as a config override — it has no --sandbox flag.
    ARGS+=(resume "$RESUME_ID" -c "sandbox_mode=\"${SANDBOX}\"")
else
    ARGS+=(--sandbox "$SANDBOX")
fi
ARGS+=(--skip-git-repo-check --json -o "$MSG_FILE")
[[ -n "$MODEL" ]] && ARGS+=(-m "$MODEL")
[[ -n "$EFFORT" ]] && ARGS+=(-c "model_reasoning_effort=\"${EFFORT}\"")
ARGS+=(-)

# Render the JSONL event stream into human-readable progress lines. Kept in
# jq (not awk) so model text can never be mistaken for a control line — every
# field is read from parsed JSON, not matched out of a formatted string.
render_events() {
    if [[ "$QUIET" -eq 1 ]]; then
        cat > /dev/null
        return 0
    fi
    jq -r --unbuffered '
        def clip($n): if (.|length) > $n then .[0:$n] + "…" else . end;
        def firstline: (. // "") | split("\n")[0] | clip(200);
        try (
            if .type == "thread.started" then "🧵 thread \(.thread_id)"
            elif .type == "turn.started" then "🟢 turn started"
            elif .type == "item.started" and .item.type == "command_execution" then
                "▶ " + ((.item.command // "") | sub("^/[^ ]*/(ba|z)?sh -lc "; "") | clip(160))
            elif .type == "item.completed" and .item.type == "command_execution" then
                "  ✓ exit \(.item.exit_code // "?")"
            elif .type == "item.completed" and .item.type == "agent_message" then
                "💬 " + (.item.text | firstline)
            elif .type == "item.completed" and .item.type == "reasoning" then
                "🧠 " + ((.item.text // .item.summary // "") | firstline)
            elif .type == "turn.completed" then
                "🔵 turn completed (\(.usage.input_tokens // 0) in / \(.usage.output_tokens // 0) out)"
            elif .type == "turn.failed" then
                "❌ turn failed: " + ((.error.message // "unknown") | firstline)
            elif .type == "error" then
                "❌ " + ((.message // "error") | firstline)
            else empty end
        ) catch empty
    ' 2>/dev/null || true
}

set +e
portable_timeout "$TIMEOUT" codex "${ARGS[@]}" < "$PROMPT_FILE" 2>"$ERR_FILE" \
    | tee "$EVENTS_FILE" \
    | render_events >&2
STATUS=${PIPESTATUS[0]}
set -e

# --- Cost ledger --------------------------------------------------------------
# codex reports per-turn token usage in the `turn.completed` event, which until
# now was rendered to stderr and thrown away. Persist it so cost per task is
# answerable at all — the harness had no cost telemetry of any kind, which also
# meant no trip wire could exist. Read from EVENTS_FILE rather than tapping the
# render pipeline, so a quiet run (--quiet) is still accounted for.
#
# Runs before the failure/timeout exits, so a run that burned 40k tokens and
# then failed is still accounted for — but only to the extent codex reported it:
# usage comes from `turn.completed`, so a run killed before any turn completed
# leaves no row. That is the best source available; it is not a full accounting
# of a hard timeout mid-turn.
# Best-effort throughout — never let accounting fail a codex run.
record_usage() {
    command -v jq >/dev/null 2>&1 || return 0
    local ledger="${CODEX_USAGE_LEDGER:-$HOME/.claude/state/codex-usage.jsonl}"
    local repo="" in_tok=0 out_tok=0 cached=0 turns=0
    repo=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")

    # Sum across turns: a resumed multi-turn run emits one turn.completed each.
    local sums
    sums=$(jq -s -r '
        [ .[] | select(.type == "turn.completed") ] as $t
        | [ ($t | length),
            ([$t[].usage.input_tokens // 0]         | add // 0),
            ([$t[].usage.output_tokens // 0]        | add // 0),
            ([$t[].usage.cached_input_tokens // 0]  | add // 0) ]
        | @tsv
    ' "$EVENTS_FILE" 2>/dev/null) || return 0
    [ -z "$sums" ] && return 0
    IFS=$'\t' read -r turns in_tok out_tok cached <<< "$sums" || return 0
    [ "${turns:-0}" -eq 0 ] && return 0

    mkdir -p "$(dirname "$ledger")" 2>/dev/null || true
    jq -c -n \
        --arg ts       "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg day      "$(date '+%Y-%m-%d')" \
        --arg thread   "${THREAD_KEY:-}" \
        --arg model    "${MODEL:-default}" \
        --arg sandbox  "$SANDBOX" \
        --arg repo     "$repo" \
        --argjson status  "${STATUS:-0}" \
        --argjson turns   "${turns:-0}" \
        --argjson input   "${in_tok:-0}" \
        --argjson output  "${out_tok:-0}" \
        --argjson cached  "${cached:-0}" \
        '{ts:$ts, day:$day, thread_key:$thread, model:$model, sandbox:$sandbox,
          repo:$repo, status:$status, turns:$turns,
          input_tokens:$input, output_tokens:$output, cached_input_tokens:$cached,
          total_tokens:($input + $output)}' \
        >> "$ledger" 2>/dev/null || true
    return 0
}
record_usage || true

if [[ $STATUS -eq 124 ]]; then
    echo "[codex-exec] timed out after ${TIMEOUT}s" >&2
    exit 124
fi

# portable_timeout's own "no timeout binary" status — pass it through so the
# caller can distinguish a missing coreutils from a codex failure.
if [[ $STATUS -eq 127 ]]; then
    cat "$ERR_FILE" >&2
    exit 127
fi

if [[ $STATUS -ne 0 ]]; then
    cat "$ERR_FILE" >&2
    # A resume against a thread codex no longer has is recoverable — tell the
    # caller to retry fresh instead of failing the whole workflow.
    if [[ "$RESUME" -eq 1 ]] && grep -qi "no rollout found\|thread/resume" "$ERR_FILE"; then
        echo "[codex-exec] stored thread ${RESUME_ID} is no longer resumable" >&2
        exit 3
    fi
    echo "[codex-exec] codex exec failed with status $STATUS" >&2
    exit 2
fi

# Persist the thread id so a later --resume can target exactly this thread.
# Resumed runs keep their original id, so this is a no-op rewrite for them.
if [[ -n "$THREAD_FILE" ]]; then
    TID=$(jq -r 'select(.type == "thread.started") | .thread_id' "$EVENTS_FILE" 2>/dev/null | head -n 1)
    if [[ -n "$TID" && "$TID" != "null" ]]; then
        mkdir -p "$THREAD_DIR"
        tmp=$(mktemp "$THREAD_DIR/.tmp.XXXXXX") && printf '%s\n' "$TID" > "$tmp" && mv -f "$tmp" "$THREAD_FILE"
    fi
fi

# codex writes the last message without a trailing newline; add one so callers
# that echo stdout straight through don't glue it to the next line.
cat "$MSG_FILE"
[[ -s "$MSG_FILE" ]] && [[ "$(tail -c1 "$MSG_FILE" | od -An -c | tr -d ' ')" != '\n' ]] && echo
exit 0
