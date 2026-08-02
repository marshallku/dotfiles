#!/bin/bash
# Check prerequisites for the ~/.claude tooling and register the infra-ops MCP.
# Run after `stow claude`. Idempotent.

set -e

# The codex-*.sh wrappers drive the codex CLI directly (codex exec), so codex
# and jq are the only hard requirements for them. Node is still needed for the
# infra-ops MCP server further down.
if ! command -v node >/dev/null 2>&1; then
    echo "✗ node not found — install Node.js 18.18+ first (needed by the infra-ops MCP)"
    exit 1
fi

NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
NODE_MINOR=$(node -p "process.versions.node.split('.')[1]")
if [ "$NODE_MAJOR" -lt 18 ] || { [ "$NODE_MAJOR" -eq 18 ] && [ "$NODE_MINOR" -lt 18 ]; }; then
    echo "✗ node $(node -v) is too old — need >=18.18"
    exit 1
fi
echo "✓ node $(node -v)"

if ! command -v codex >/dev/null 2>&1; then
    echo "✗ codex CLI not found — install first: npm i -g @openai/codex"
    exit 1
fi
echo "✓ codex $(codex --version 2>/dev/null | head -1)"

if ! command -v jq >/dev/null 2>&1; then
    echo "✗ jq not found — the codex wrappers parse codex's JSONL event stream with it"
    exit 1
fi
echo "✓ jq $(jq --version 2>/dev/null)"

if command -v codex >/dev/null 2>&1 && [ ! -f "$HOME/.codex/auth.json" ]; then
    echo "! codex not authenticated — run: codex login"
fi

# infra-ops MCP: install deps + register (idempotent). Lets Claude Code manage
# the homelab (docker@prd01, k3s+Prometheus@mgmt01) over ssh. See its server.mjs.
INFRA_MCP="$HOME/dotfiles/claude/.claude/mcp/infra-ops"
if [ -f "$INFRA_MCP/package.json" ]; then
    if (cd "$INFRA_MCP" && npm install --no-audit --no-fund >/dev/null 2>&1); then
        echo "✓ infra-ops MCP deps installed"
        # Only register once deps are present — a registered-but-broken server
        # (missing node_modules) would fail to start and look mysteriously dead.
        if command -v claude >/dev/null 2>&1; then
            if claude mcp list 2>/dev/null | grep -q '^infra-ops:'; then
                echo "✓ infra-ops MCP already registered"
            else
                claude mcp add infra-ops -s user -- node "$INFRA_MCP/server.mjs" >/dev/null 2>&1 &&
                    echo "✓ infra-ops MCP registered (user scope)"
            fi
        fi
    else
        echo "✗ infra-ops MCP npm install failed — NOT registering (would be unusable)"
    fi
fi

# Retire the codex-broker-reaper launchd agent if a previous install left one.
# It reaped app-server brokers spawned by the old codex-plugin-cc runtime;
# `codex exec` spawns no daemon, so there is nothing left to reap.
if [ "$(uname -s)" = "Darwin" ]; then
    REAPER_PLIST_DST="$HOME/Library/LaunchAgents/com.marshallku.codex-broker-reaper.plist"
    if [ -f "$REAPER_PLIST_DST" ]; then
        launchctl bootout "gui/$(id -u)/com.marshallku.codex-broker-reaper" 2>/dev/null || true
        rm -f "$REAPER_PLIST_DST"
        echo "✓ removed obsolete codex-broker-reaper launchd agent"
    fi
fi

echo "Done."
