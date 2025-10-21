#!/usr/bin/env bash

set -euo pipefail

STATUS_RAW="$(adguardvpn-cli status 2>/dev/null || true)"
STATUS_RAW="$(echo "$STATUS_RAW" | sed 's/\x1B\[[0-9;]*[A-Za-z]//g')"

connected="false"
city=""
mode=""
iface=""

if grep -qE '^Connected to ' <<< "$STATUS_RAW"; then
  connected="true"
  city="$(sed -n 's/^Connected to \([^ ]\+\).*/\1/p' <<< "$STATUS_RAW")"
  mode="$(sed -n 's/^Connected to .* in \([^ ]\+\) mode.*/\1/p' <<< "$STATUS_RAW")"
  iface="$(sed -n 's/^Connected to .* running on \([^ ]\+\).*/\1/p' <<< "$STATUS_RAW")"
fi

if [[ "$connected" == "true" ]]; then
  icon="󰒋"
  text="${icon} ${city}"
  cls="connected"
  tooltip="Connected to ${city}\nMode: ${mode}\nInterface: ${iface}"
else
  icon="󰦞"
  text="${icon} Disconnected"
  cls="disconnected"
  tooltip="${STATUS_RAW:-Not connected}"
fi

jq -c --null-input --arg text "$text" --arg cls "$cls" --arg tip "$tooltip" \
  '{text: $text, "class": $cls, tooltip: $tip}'

