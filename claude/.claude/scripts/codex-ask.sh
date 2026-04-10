#!/usr/bin/env bash
# codex-ask.sh — Ask Codex for a quick opinion on a design question.
# Runs in read-only sandbox. Intended for one-shot consultations during work.
#
# Usage:
#   codex-ask.sh "Should I use X or Y?"
#   cat src/auth.ts | codex-ask.sh "Is this middleware order correct?"
#
# Environment overrides:
#   CODEX_ASK_MODEL   — override model passed to `codex exec -m`
#   CODEX_ASK_TIMEOUT — seconds before the call is aborted (default 120)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <question>" >&2
    exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "[codex-ask] codex CLI not found in PATH" >&2
    exit 2
fi

QUESTION="$*"
TIMEOUT="${CODEX_ASK_TIMEOUT:-120}"

STDIN_CONTEXT=""
if ! [[ -t 0 ]]; then
    STDIN_CONTEXT=$(cat)
fi

MODEL_ARGS=()
if [[ -n "${CODEX_ASK_MODEL:-}" ]]; then
    MODEL_ARGS=(-m "$CODEX_ASK_MODEL")
fi

if [[ -n "$STDIN_CONTEXT" ]]; then
    PROMPT=$(cat <<EOF
You are in consultation mode (see AGENTS.md). Give a concrete recommendation and the single most important tradeoff. No hedging, no multi-option comparison, no caveat lists.

Context:
${STDIN_CONTEXT}

Question: ${QUESTION}
EOF
)
else
    PROMPT=$(cat <<EOF
You are in consultation mode (see AGENTS.md). Give a concrete recommendation and the single most important tradeoff. No hedging, no multi-option comparison, no caveat lists.

Question: ${QUESTION}
EOF
)
fi

exec timeout "$TIMEOUT" codex exec --skip-git-repo-check -s read-only "${MODEL_ARGS[@]}" "$PROMPT"
