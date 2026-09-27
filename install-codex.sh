#!/usr/bin/env bash
# Run after stow claude. Share source files; keep machine-specific config local.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
for dependency in python3 jq git codex; do
    command -v "$dependency" >/dev/null || { echo "Missing dependency: $dependency" >&2; exit 1; }
done
if [ ! -f "$HOME/.claude/settings.json" ] || [ ! -f "$HOME/.claude/hooks/_lib.sh" ]; then
    echo "Run stow claude first." >&2
    exit 1
fi
python3 "$ROOT/claude/.claude/scripts/codex-harness/install.py"

INFRA_MCP="$ROOT/claude/.claude/mcp/infra-ops"
if [ -d "$INFRA_MCP/node_modules/@modelcontextprotocol/sdk" ] && command -v node >/dev/null; then
    if ! codex mcp get infra-ops >/dev/null 2>&1; then
        codex mcp add infra-ops -- node "$INFRA_MCP/server.mjs"
    fi
else
    echo "infra-ops not registered: run install-claude.sh to install its dependencies, then rerun this script."
fi
