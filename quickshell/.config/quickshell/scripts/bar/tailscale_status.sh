#!/usr/bin/env bash

set -euo pipefail

emit() {
  jq -c --null-input --arg text "$1" --arg cls "$2" --arg tip "$3" \
    '{text: $text, "class": $cls, tooltip: $tip}'
}

if ! command -v tailscale >/dev/null 2>&1; then
  emit "" "" ""
  exit 0
fi

STATUS_JSON="$(tailscale status --json 2>/dev/null || true)"

if [[ -z "$STATUS_JSON" ]]; then
  emit "󰖂  ?" "disconnected" "tailscaled is not reachable"
  exit 0
fi

printf '%s' "$STATUS_JSON" | jq -c '
  def icon: "󰖂";
  # HostName can be a generic "localhost"; the MagicDNS label is the readable name.
  def nodename: ((.DNSName // "") | split(".")[0] // "") as $n
    | if $n == "" then (.HostName // "?") else $n end;

  ((.Peer // {}) | to_entries | map(.value))          as $peers
  | ($peers | map(select(.Online)))                   as $up
  | ($peers | map(select(.ExitNode)) | first)         as $exit
  | (.Self | nodename)                                as $host
  | (.Self.TailscaleIPs // [] | first // "-")         as $ip
  | (.CurrentTailnet.Name // "-")                     as $tailnet
  | (.BackendState // "NoState")                      as $state

  | (if $state == "Running" then
       (if $exit then
          { text: "\(icon)  \($exit | nodename)", "class": "exit-node" }
        else
          { text: "\(icon)  \($up | length)/\($peers | length)", "class": "connected" }
        end)
     elif $state == "Stopped" then
       { text: "\(icon)  Off", "class": "disconnected" }
     else
       { text: "\(icon)  \($state)", "class": "disconnected" }
     end)

  | . + { tooltip: ([
      "\($host) · \($ip)",
      "Tailnet: \($tailnet)",
      "State: \($state)",
      "Exit node: \(if $exit then ($exit | nodename) else "none" end)",
      "Peers online: \($up | length)/\($peers | length)"
    ] + ($up | sort_by(nodename) | map("  \(nodename)  \(.TailscaleIPs // [] | first // "-")"))
    | join("\n")) }
'
