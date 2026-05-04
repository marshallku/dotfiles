#!/usr/bin/env bash
# codex-ask.sh — Ask Codex for a quick opinion on a design question.
# Routes through the codex-companion app-server runtime so the user sees
# streaming progress phases (starting / investigating / finalizing) instead
# of a black box. Read-only sandbox — codex cannot modify files.
#
# Usage:
#   codex-ask.sh "Should I use X or Y?"
#   cat src/auth.ts | codex-ask.sh "Is this middleware order correct?"
#
# Environment overrides:
#   CODEX_ASK_MODEL   — override model passed to the companion (--model)
#   CODEX_ASK_TIMEOUT — seconds before the call is aborted (default 180)

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <question>" >&2
    exit 2
fi

COMPANION="$(dirname "$0")/codex-companion.sh"
if [[ ! -x "$COMPANION" ]]; then
    echo "[codex-ask] companion wrapper missing: $COMPANION" >&2
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

# stdin must be /dev/null — companion `task` falls back to reading piped stdin
# as the prompt otherwise.
portable_timeout "$TIMEOUT" "$COMPANION" task ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT" </dev/null
