#!/usr/bin/env bash
# codex-ask.sh — Ask Codex for a quick opinion on a design question.
# Routes through codex-exec.sh so the user sees the progress stream instead
# of a black box. Read-only sandbox — codex cannot modify files.
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

STDIN_CONTEXT=""
if ! [[ -t 0 ]]; then
    STDIN_CONTEXT=$(cat)
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

exec "$RUNNER" --timeout "$TIMEOUT" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} --prompt "$PROMPT" </dev/null
