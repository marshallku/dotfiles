#!/usr/bin/env bash
# Desktop widget collector: homelab health in detail — what waybar squeezes
# into three icons (server_health / grafana / tailscale).
#
#   servers   : HTTP status + latency per server. The list is shared with
#               waybar via ~/.config/waybar/scripts/servers.conf.
#   nodes     : per-node CPU / MEM / root-disk / uptime from Prometheus via the
#               Grafana datasource proxy. Same config + auth handling as
#               waybar's grafana_status.sh.
#   tailscale : backend state + every peer with online flag.
#
# Sections run concurrently and fail independently ({ok:false, error}); the
# QML side keeps last-good data per section and marks it stale. Unlike
# server_health.sh this never notifies or writes state — waybar owns alerts.

set -u

servers_conf="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/servers.conf"
grafana_conf="${XDG_CONFIG_HOME:-$HOME/.config}/grafana-waybar/config"
now_ms=$(( $(date +%s%N) / 1000000 ))

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

error_json() {
    jq -n -c --arg e "$1" '{ok: false, error: $e}'
}

# ── servers ────────────────────────────────────────────────────────────────
collect_servers() {
    if [[ ! -r "$servers_conf" ]]; then
        error_json "missing $servers_conf"
        return
    fi
    local SERVER_GROUPS=()
    # shellcheck source=/dev/null
    source "$servers_conf"

    local group_def group domains domain url i=0
    for group_def in "${SERVER_GROUPS[@]}"; do
        group_def=${group_def%,}
        group=${group_def%%:*}
        IFS=',' read -ra domains <<<"${group_def#*:}"
        for domain in "${domains[@]}"; do
            domain=$(xargs <<<"$domain")
            [[ -n "$domain" ]] || continue
            url=$domain
            [[ "$url" =~ ^https?:// ]] || url="https://$url"
            (
                out=$(curl -s -o /dev/null --max-time 5 -w '%{http_code} %{time_total}' "$url" 2>/dev/null)
                read -r code secs <<<"${out:-000 0}"
                jq -n -c --arg g "$group" --arg n "${domain%/}" --arg c "$code" --arg t "$secs" \
                    '{group: $g, name: $n, code: ($c | tonumber),
                      up: (($c | tonumber) >= 200 and ($c | tonumber) < 400),
                      latency_ms: (($t | tonumber) * 1000 | round)}'
            ) >"$work/server.$i" &
            i=$(( i + 1 ))
        done
    done
    wait

    if (( i == 0 )); then
        error_json "no servers configured"
        return
    fi
    cat "$work"/server.* | jq -s -c '{ok: true, items: .}'
}

# ── nodes (Prometheus via Grafana) ─────────────────────────────────────────
collect_nodes() {
    if [[ ! -f "$grafana_conf" ]]; then
        error_json "grafana not configured"
        return
    fi
    local perms
    perms=$(stat -c '%a' "$grafana_conf" 2>/dev/null)
    if [[ "$perms" != "600" && "$perms" != "400" ]]; then
        error_json "unsafe permissions on grafana config: $perms"
        return
    fi

    local GRAFANA_URL="" GRAFANA_API_KEY="" DATASOURCE_UID=""
    # shellcheck source=/dev/null
    source "$grafana_conf"
    if [[ -z "$GRAFANA_URL" || -z "$GRAFANA_API_KEY" || -z "$DATASOURCE_UID" ]]; then
        error_json "grafana config missing required vars"
        return
    fi

    local proxy="${GRAFANA_URL}/api/datasources/proxy/uid/${DATASOURCE_UID}/api/v1/query"
    # Auth header via file so the key never appears in /proc/<pid>/cmdline.
    local header="$work/auth"
    ( umask 077; printf 'Authorization: Bearer %s' "$GRAFANA_API_KEY" >"$header" )

    local -A queries=(
        [cpu]='100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
        [mem]='(1 - avg by (node) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'
        [disk]='max by (node) ((1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)'
        [uptime]='max by (node) (time() - node_boot_time_seconds)'
    )
    local key
    for key in "${!queries[@]}"; do
        curl -sf --max-time 5 -H @"$header" --data-urlencode "query=${queries[$key]}" \
            "$proxy" >"$work/q.$key" 2>/dev/null &
    done
    wait

    # All four or nothing: a partial success would publish null metrics as a
    # fresh reading and overwrite the last good ones on the widget.
    local failed=()
    for key in cpu mem disk uptime; do
        jq -e '.status == "success"' "$work/q.$key" >/dev/null 2>&1 || failed+=("$key")
    done
    if (( ${#failed[@]} > 0 )); then
        error_json "grafana query failed: ${failed[*]}"
        return
    fi

    jq -n -c \
        --slurpfile cpu "$work/q.cpu" \
        --slurpfile mem "$work/q.mem" \
        --slurpfile disk "$work/q.disk" \
        --slurpfile up "$work/q.uptime" '
        def by_node($r): ($r[0].data.result // [])
            | map({key: (.metric.node // "unknown"), value: (.value[1] | tonumber)})
            | from_entries;
        by_node($cpu) as $c | by_node($mem) as $m | by_node($disk) as $d | by_node($up) as $u
        | {ok: true,
           items: ([$c, $m, $d, $u | keys[]] | unique
                   | map({name: ., cpu: $c[.], mem: $m[.], disk: $d[.], uptime_s: $u[.]}))}'
}

# ── tailscale ──────────────────────────────────────────────────────────────
collect_tailscale() {
    if ! command -v tailscale >/dev/null 2>&1; then
        error_json "tailscale not installed"
        return
    fi
    local raw
    raw=$(timeout 5 tailscale status --json 2>/dev/null)
    if [[ -z "$raw" ]]; then
        error_json "tailscale status failed"
        return
    fi
    # HostName is "localhost" for iOS peers; the DNS label is what people know.
    jq -c '
        def peer_name: ((.DNSName // "") | split(".")[0]) as $d
            | if $d != "" then $d else .HostName end;
        {ok: true,
         state: .BackendState,
         self: (.Self | peer_name),
         items: ([(.Peer // {})[] | {name: peer_name, online: .Online, os: .OS}]
                 | sort_by((.online | not), .name))}' <<<"$raw" 2>/dev/null \
        || error_json "tailscale: malformed json"
}

collect_servers >"$work/servers.json" &
collect_nodes >"$work/nodes.json" &
collect_tailscale >"$work/tailscale.json" &
wait

section() {
    local f="$work/$1.json"
    if jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
        cat "$f"
    else
        error_json "$1 collector crashed"
    fi
}

jq -n -c \
    --argjson now "$now_ms" \
    --argjson servers "$(section servers)" \
    --argjson nodes "$(section nodes)" \
    --argjson tailscale "$(section tailscale)" \
    '{generated_at: $now, servers: $servers, nodes: $nodes, tailscale: $tailscale}'
