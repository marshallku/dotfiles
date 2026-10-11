#!/usr/bin/env bash
set -euo pipefail

if [[ -x "$HOME/.local/bin/copad" ]]; then
    exec "$HOME/.local/bin/copad" "$@"
fi
exec kitty "$@"
