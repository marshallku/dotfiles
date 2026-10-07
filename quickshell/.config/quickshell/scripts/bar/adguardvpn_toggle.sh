#!/usr/bin/env bash
set -euo pipefail

STATUS_RAW="$(adguardvpn-cli status 2>/dev/null || true)"

if grep -qE '^Connected to ' <<< "$STATUS_RAW"; then
  # Connected → disconnect
  adguardvpn-cli disconnect >/dev/null 2>&1 || exit 0
  notify-send "AdGuard VPN" "Disconnected"
else
  # Disconnected → connect to last-used/default
  adguardvpn-cli connect >/dev/null 2>&1 || exit 0
  notify-send "AdGuard VPN" "Connected"
fi

