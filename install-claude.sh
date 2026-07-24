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

# codex-broker-reaper: periodically reap idle codex app-server-broker orphans.
# These broker+app-server pairs (~85-290MB each) are spawned detached, survive
# the Claude session that created them, and have no idle timeout upstream — so
# they accumulate until reboot. macOS launchd only; on Linux the reaper still
# runs via the session-start.sh hook (just not on a fixed timer).
if [ "$(uname -s)" = "Darwin" ]; then
    REAPER_PLIST_SRC="$HOME/dotfiles/claude/.claude/launchd/com.marshallku.codex-broker-reaper.plist"
    REAPER_PLIST_DST="$HOME/Library/LaunchAgents/com.marshallku.codex-broker-reaper.plist"
    if [ -f "$REAPER_PLIST_SRC" ]; then
        mkdir -p "$HOME/Library/LaunchAgents"
        # Materialize $HOME into the plist (launchd does not expand ~ or env vars here).
        sed "s|__HOME__|$HOME|g" "$REAPER_PLIST_SRC" > "$REAPER_PLIST_DST"
        # Reload idempotently (bootout is harmless if not currently loaded).
        launchctl bootout "gui/$(id -u)/com.marshallku.codex-broker-reaper" 2>/dev/null || true
        if launchctl bootstrap "gui/$(id -u)" "$REAPER_PLIST_DST" 2>/dev/null; then
            echo "✓ codex-broker-reaper launchd agent installed (every 15m)"
        else
            echo "! codex-broker-reaper launchd bootstrap failed — reaper still runs via session-start hook"
        fi
    fi
fi

echo "Done."
