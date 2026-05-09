#!/bin/bash
# Bootstrap TPM and tmux plugins (resurrect, continuum) declared in .tmux.conf.
# Run after `stow tmux`. Idempotent.

set -e

TPM_DIR="$HOME/.tmux/plugins/tpm"

if ! command -v tmux >/dev/null 2>&1; then
    echo "✗ tmux not found — install it first"
    exit 1
fi
echo "✓ tmux $(tmux -V)"

if ! command -v git >/dev/null 2>&1; then
    echo "✗ git not found"
    exit 1
fi

if [ -d "$TPM_DIR/.git" ]; then
    echo "✓ TPM already at $TPM_DIR"
else
    echo "→ cloning TPM"
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

echo "→ installing plugins via TPM"
"$TPM_DIR/bin/install_plugins" >/dev/null

if tmux info >/dev/null 2>&1; then
    echo "→ sourcing ~/.tmux.conf into running server"
    tmux source-file "$HOME/.tmux.conf"
fi

if command -v systemctl >/dev/null 2>&1; then
    echo "→ enabling user-level tmux.service (continuum auto-start)"
    systemctl --user daemon-reload
    systemctl --user enable tmux.service >/dev/null 2>&1 || true
    echo "✓ tmux.service: $(systemctl --user is-enabled tmux.service)"
fi

echo "✓ tmux bootstrap complete"
