#!/usr/bin/env bash

set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
  exit 0
fi

# `tailscale up/down` needs root unless this user is registered as the operator.
operator="$(tailscale debug prefs 2>/dev/null | jq -r '.OperatorUser // ""')"
if [[ "$operator" != "$USER" && "$EUID" -ne 0 ]]; then
  notify-send "Tailscale" "Toggle needs operator rights.\nRun: sudo tailscale set --operator=$USER"
  exit 0
fi

state="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // ""')"

if [[ "$state" == "Running" ]]; then
  tailscale down >/dev/null 2>&1 || exit 0
  notify-send "Tailscale" "Disconnected"
else
  tailscale up >/dev/null 2>&1 || exit 0
  notify-send "Tailscale" "Connected"
fi

pkill -SIGRTMIN+11 waybar || true
