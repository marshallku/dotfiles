#!/bin/bash
# Bootstrap the codex-plugin-cc runtime that ~/.claude/scripts/codex-*.sh wraps.
# Run after `stow claude`. Idempotent.

set -e

CODEX_PLUGIN_DIR="${CODEX_COMPANION_ROOT:-$HOME/dev/codex-plugin-cc}"
STATE_DIR="$HOME/.claude/state/codex-companion"

if ! command -v node >/dev/null 2>&1; then
    echo "✗ node not found — install Node.js 18.18+ first"
    exit 1
fi

NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
NODE_MINOR=$(node -p "process.versions.node.split('.')[1]")
if [ "$NODE_MAJOR" -lt 18 ] || { [ "$NODE_MAJOR" -eq 18 ] && [ "$NODE_MINOR" -lt 18 ]; }; then
    echo "✗ node $(node -v) is too old — codex-plugin-cc needs >=18.18"
    exit 1
fi
echo "✓ node $(node -v)"

if ! command -v codex >/dev/null 2>&1; then
    echo "✗ codex CLI not found — install first: npm i -g @openai/codex"
    exit 1
fi
echo "✓ codex $(codex --version 2>/dev/null | head -1)"

if [ -d "$CODEX_PLUGIN_DIR/.git" ]; then
    echo "✓ codex-plugin-cc already at $CODEX_PLUGIN_DIR"
else
    mkdir -p "$(dirname "$CODEX_PLUGIN_DIR")"
    git clone --depth 1 https://github.com/openai/codex-plugin-cc.git "$CODEX_PLUGIN_DIR"
    echo "✓ cloned codex-plugin-cc → $CODEX_PLUGIN_DIR"
fi

mkdir -p "$STATE_DIR"
echo "✓ state dir $STATE_DIR"

if command -v codex >/dev/null 2>&1 && [ ! -f "$HOME/.codex/auth.json" ]; then
    echo "! codex not authenticated — run: codex login"
fi

echo "Done."
