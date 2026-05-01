#!/usr/bin/env bash
# codex-companion.sh — Thin wrapper around the @openai/codex-plugin-cc
# companion script. Provides shared env (persistent state dir, default model)
# and a single entrypoint for ask/review/plan/delegate wrappers.
#
# Why this exists: invoking the companion script directly defaults its state
# directory to /tmp/codex-companion (gets wiped on reboot). We pin it to
# ~/.claude/state/codex-companion so background jobs and broker sessions
# survive across Claude sessions.
#
# Usage:
#   codex-companion.sh task "prompt"
#   codex-companion.sh task --background --write "delegate this"
#   codex-companion.sh review --uncommitted
#   codex-companion.sh status
#   codex-companion.sh result <job-id>
#   codex-companion.sh cancel <job-id>
#
# Environment overrides:
#   CODEX_COMPANION_ROOT  — path to the codex-plugin-cc repo
#                            (default: ~/dev/codex-plugin-cc)
#   CLAUDE_PLUGIN_DATA    — state directory used by the companion
#                            (default: ~/.claude/state/codex-companion)

set -euo pipefail

CODEX_COMPANION_ROOT="${CODEX_COMPANION_ROOT:-$HOME/dev/codex-plugin-cc}"
COMPANION_SCRIPT="$CODEX_COMPANION_ROOT/plugins/codex/scripts/codex-companion.mjs"

if [[ ! -f "$COMPANION_SCRIPT" ]]; then
    echo "[codex-companion] script not found: $COMPANION_SCRIPT" >&2
    echo "  Set CODEX_COMPANION_ROOT or clone:" >&2
    echo "  git clone https://github.com/openai/codex-plugin-cc $CODEX_COMPANION_ROOT" >&2
    exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "[codex-companion] codex CLI not found in PATH" >&2
    exit 2
fi

if ! command -v node >/dev/null 2>&1; then
    echo "[codex-companion] node not found in PATH" >&2
    exit 2
fi

export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/state/codex-companion}"
mkdir -p "$CLAUDE_PLUGIN_DATA"

exec node "$COMPANION_SCRIPT" "$@"
