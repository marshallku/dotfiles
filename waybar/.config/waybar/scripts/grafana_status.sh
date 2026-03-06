#!/bin/bash
# Waybar Grafana module - Fetches key metrics from Grafana API
#
# Config file: ~/.config/grafana-waybar/config (chmod 600)
# Required vars: GRAFANA_URL, GRAFANA_API_KEY, DATASOURCE_UID
# Optional vars: GRAFANA_DASHBOARD_URL

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/grafana-waybar/config"

if [ ! -f "$CONFIG_FILE" ]; then
  echo '{"text": "󱁤  Grafana", "tooltip": "Not configured.\nCreate ~/.config/grafana-waybar/config (chmod 600)", "class": "error"}'
  exit 0
fi

config_perms=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null)
if [ "$config_perms" != "600" ] && [ "$config_perms" != "400" ]; then
  echo '{"text": "󱁤  Grafana ⚠", "tooltip": "Unsafe permissions: '"$config_perms"'\nRun: chmod 600 '"$CONFIG_FILE"'", "class": "error"}'
  exit 0
fi

source "$CONFIG_FILE"

if [ -z "$GRAFANA_URL" ] || [ -z "$GRAFANA_API_KEY" ] || [ -z "$DATASOURCE_UID" ]; then
  echo '{"text": "󱁤  Grafana", "tooltip": "Missing required config vars", "class": "error"}'
  exit 0
fi

# Handle --open flag
if [ "$1" = "--open" ]; then
  xdg-open "${GRAFANA_DASHBOARD_URL:-$GRAFANA_URL}"
  exit 0
fi

PROXY_URL="${GRAFANA_URL}/api/datasources/proxy/uid/${DATASOURCE_UID}/api/v1/query"

# Auth header via temp file to avoid /proc exposure
HEADER_FILE=$(mktemp)
trap 'rm -f "$HEADER_FILE"' EXIT
printf 'Authorization: Bearer %s' "$GRAFANA_API_KEY" > "$HEADER_FILE"

# Query using POST with --data-urlencode for safe encoding
query_grafana() {
  curl -sf --max-time 5 \
    -H @"$HEADER_FILE" \
    --data-urlencode "query=$1" \
    "$PROXY_URL" 2>/dev/null
}

# Fetch per-node CPU and memory
cpu_raw=$(query_grafana '100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)')
mem_raw=$(query_grafana '(1 - avg by (node) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100')

if [ -z "$cpu_raw" ] && [ -z "$mem_raw" ]; then
  echo '{"text": "󱁤  Grafana ✗", "tooltip": "Failed to reach Grafana API", "class": "error"}'
  exit 0
fi

# Parse per-node values: produces "node=value" lines
parse_nodes() {
  echo "$1" | jq -r '.data.result[] | "\(.metric.node // "unknown")=\(.value[1])"' 2>/dev/null
}

cpu_nodes=$(parse_nodes "$cpu_raw")
mem_nodes=$(parse_nodes "$mem_raw")

# Collect unique node names
nodes=$(echo -e "${cpu_nodes}\n${mem_nodes}" | cut -d= -f1 | sort -u | grep -v '^$')

# Build tooltip with per-node breakdown
tooltip="Server Metrics\n"
bar_text=""
class="normal"

for node in $nodes; do
  cpu_val=$(echo "$cpu_nodes" | grep "^${node}=" | cut -d= -f2)
  mem_val=$(echo "$mem_nodes" | grep "^${node}=" | cut -d= -f2)

  cpu_fmt=$([ -n "$cpu_val" ] && printf "%.1f%%" "$cpu_val" || echo "N/A")
  mem_fmt=$([ -n "$mem_val" ] && printf "%.1f%%" "$mem_val" || echo "N/A")

  tooltip+="\n${node}:  CPU ${cpu_fmt}  MEM ${mem_fmt}"

  # Check thresholds
  if [ -n "$cpu_val" ]; then
    cpu_int=${cpu_val%.*}
    [ "${cpu_int:-0}" -gt 80 ] && class="error"
  fi
  if [ -n "$mem_val" ]; then
    mem_int=${mem_val%.*}
    [ "${mem_int:-0}" -gt 90 ] && class="error"
  fi
done

tooltip+="\n\nClick to open Grafana"

# Short bar text: average across all nodes
avg_cpu=$(echo "$cpu_nodes" | awk -F= '{ sum += $2; n++ } END { if (n>0) printf "%.0f%%", sum/n; else print "N/A" }')
avg_mem=$(echo "$mem_nodes" | awk -F= '{ sum += $2; n++ } END { if (n>0) printf "%.0f%%", sum/n; else print "N/A" }')

text="󱁤  ${avg_cpu} │ ${avg_mem}"

echo "{\"text\": \"${text}\", \"tooltip\": \"${tooltip}\", \"class\": \"${class}\"}"
