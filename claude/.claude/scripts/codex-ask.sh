#!/usr/bin/env bash
# codex-ask.sh — Ask Codex for a quick opinion on a design question.
# Routes through codex-exec.sh for the progress stream. Read-only sandbox.
#
# One-shot by design: no thread key, so an /ask-codex in the middle of a
# plan or review loop can never disturb those threads.
#
# Usage:
#   codex-ask.sh "Should I use X or Y?"
#   cat src/auth.ts | codex-ask.sh "Is this middleware order correct?"
#
# Environment overrides:
#   CODEX_ASK_MODEL   — override model passed to codex (-m)
#   CODEX_ASK_TIMEOUT — seconds before the call is aborted (default 180)
#   CODEX_ASK_EFFORT  — reasoning effort (default medium; high is too slow for a ~30 s consult)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <question>" >&2
    exit 2
fi

RUNNER="$(dirname "$0")/codex-exec.sh"
if [[ ! -x "$RUNNER" ]]; then
    echo "[codex-ask] runner missing: $RUNNER" >&2
    exit 2
fi

QUESTION="$*"
TIMEOUT="${CODEX_ASK_TIMEOUT:-180}"

# A non-tty stdin that never sends EOF (an agent harness's inherited pipe) would
# block a bare `cat` forever, so wait only CODEX_ASK_STDIN_WAIT seconds for the
# first byte; a real pipe has data or EOF by then. 0 skips stdin entirely.
STDIN_CONTEXT=""
STDIN_WAIT="${CODEX_ASK_STDIN_WAIT:-2}"
if ! [[ -t 0 ]] && [[ "$STDIN_WAIT" != 0 ]]; then
    FIRST=""
    READ_STATUS=0
    IFS= read -r -t "$STDIN_WAIT" FIRST || READ_STATUS=$?
    if [[ "$READ_STATUS" -eq 0 ]]; then
        STDIN_CONTEXT="$FIRST"$'\n'"$(cat)"
    elif [[ "$READ_STATUS" -eq 1 && -n "$FIRST" ]]; then
        STDIN_CONTEXT="$FIRST"    # EOF after a line without a trailing newline
    fi                            # >128: timed out; any partial line is dropped
fi

MODEL_ARGS=()
if [[ -n "${CODEX_ASK_MODEL:-}" ]]; then
    MODEL_ARGS=(--model "$CODEX_ASK_MODEL")
fi

# stdin was already drained above (or was a tty); hand the runner /dev/null so
# codex never blocks waiting for more input.

# Consultation-mode rules (concrete recommendation + 1 tradeoff, no hedging,
# ~150-word cap) live in ~/.codex/AGENTS.md and auto-load. Don't restate.
if [[ -n "$STDIN_CONTEXT" ]]; then
    PROMPT=$(cat <<EOF
Consultation mode.

Context:
${STDIN_CONTEXT}

Question: ${QUESTION}
EOF
)
else
    PROMPT="Consultation mode.

Question: ${QUESTION}"
fi

exec "$RUNNER" --timeout "$TIMEOUT" --effort "${CODEX_ASK_EFFORT:-medium}" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
    --prompt "$PROMPT" </dev/null
