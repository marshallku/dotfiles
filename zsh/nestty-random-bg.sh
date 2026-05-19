#!/bin/bash

CACHE_FILE="$HOME/.cache/terminal-wallpapers.txt"
MODE_FILE="$HOME/.cache/nestty-bg-mode"
CURRENT_FILE="$HOME/.cache/nestty-bg-current"
DEFAULT_INTERVAL=300
NESTCTL="nestctl"

g_elapsed=0

nestty_alive() {
    local id="${1:-$(instance_id)}"
    [[ -n "$id" ]] && kill -0 "$id" 2>/dev/null
}

socket_set_background() {
    local path="$1"
    $NESTCTL background set "$path" &>/dev/null
}

socket_clear_background() {
    $NESTCTL background clear &>/dev/null
}

get_mode() {
    if [[ -f "$MODE_FILE" ]]; then
        cat "$MODE_FILE"
    else
        echo "active"
    fi
}

select_random_image() {
    if [[ ! -f "$CACHE_FILE" ]] || [[ ! -s "$CACHE_FILE" ]]; then
        return 1
    fi
    shuf -n 1 "$CACHE_FILE"
}

instance_id() {
    local sock="${NESTTY_SOCKET:-}"
    local base="${sock##*/}"
    base="${base#gui-}"
    base="${base#nestty-}"
    echo "${base%.sock}"
}

save_current() {
    g_elapsed=0
    local id="$1" img="$2"
    echo "$img" > "${CURRENT_FILE}-${id}.txt"
}

get_current() {
    local id="$1"
    local file="${CURRENT_FILE}-${id}.txt"
    [[ -f "$file" ]] && cat "$file"
}

apply_by_mode() {
    [[ -z "${NESTTY_SOCKET:-}" ]] && return 1

    local id
    id=$(instance_id)

    if [[ "$(get_mode)" == "deactive" ]]; then
        socket_clear_background
    else
        local img
        img=$(select_random_image) || return 1
        socket_set_background "$img"
        save_current "$id" "$img"
    fi
}

toggle_mode() {
    local current
    current=$(get_mode)

    if [[ "$current" == "active" ]]; then
        echo "deactive" > "$MODE_FILE"
        socket_clear_background
    else
        echo "active" > "$MODE_FILE"
        apply_by_mode
    fi
}

next_image() {
    if [[ "$(get_mode)" == "deactive" ]]; then
        return 0
    fi

    [[ -z "${NESTTY_SOCKET:-}" ]] && return 1

    local img
    img=$(select_random_image) || return 1
    socket_set_background "$img"
    save_current "$(instance_id)" "$img"
}

delete_current() {
    local id
    id=$(instance_id)
    local img
    img=$(get_current "$id")

    if [[ -z "$img" ]]; then
        return 1
    fi

    rm -f "$img"

    if [[ -f "$CACHE_FILE" ]]; then
        grep -v -xF "$img" "$CACHE_FILE" > "${CACHE_FILE}.tmp"
        mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    fi

    next_image
}

daemon_running() {
    local pid_file="$HOME/.cache/nestty-bg-daemon-$(instance_id).pid"

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$pid_file"
    fi
    return 1
}

wait_for_socket() {
    local i
    for i in $(seq 1 50); do
        [[ -S "$NESTTY_SOCKET" ]] && return 0
        sleep 0.1
    done
    return 1
}

sweep_stale() {
    local f id
    shopt -s nullglob
    for f in "$HOME/.cache/nestty-bg-daemon-"*.pid; do
        id="${f##*nestty-bg-daemon-}"
        id="${id%.pid}"
        if ! nestty_alive "$id"; then
            local dpid
            dpid=$(cat "$f" 2>/dev/null)
            [[ -n "$dpid" ]] && kill -0 "$dpid" 2>/dev/null && kill "$dpid" 2>/dev/null
            rm -f "$f" "${CURRENT_FILE}-${id}.txt"
        fi
    done
    for f in "${CURRENT_FILE}-"*.txt; do
        id="${f##*nestty-bg-current-}"
        id="${id%.txt}"
        nestty_alive "$id" || rm -f "$f"
    done
    shopt -u nullglob
}

run_daemon() {
    local interval="${1:-$DEFAULT_INTERVAL}"

    if [[ -z "${NESTTY_SOCKET:-}" ]]; then
        echo "Error: NESTTY_SOCKET is not set" >&2
        exit 1
    fi

    wait_for_socket || exit 1

    sweep_stale

    if daemon_running; then
        exit 0
    fi

    apply_by_mode

    local id
    id=$(instance_id)
    local pid_file="$HOME/.cache/nestty-bg-daemon-${id}.pid"
    echo $$ > "$pid_file"
    local current_file="${CURRENT_FILE}-${id}.txt"
    trap 'rm -f "$pid_file" "$current_file"; exit' EXIT INT TERM HUP

    while true; do
        sleep 10

        # nestty process가 죽었으면 종료
        nestty_alive "$id" || exit 0

        g_elapsed=$((g_elapsed + 10))
        if (( g_elapsed >= interval )); then
            g_elapsed=0
            apply_by_mode
        fi
    done
}

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --toggle       Toggle background mode"
    echo "  --next         Switch to next random image"
    echo "  --delete       Delete current image and switch"
    echo "  --daemon       Daemon mode (auto rotation)"
    echo "  --interval N   Rotation interval in seconds (default: 300)"
    echo "  -h, --help     Show this help"
}

main() {
    local do_toggle=false
    local do_next=false
    local do_delete=false
    local do_daemon=false
    local interval=$DEFAULT_INTERVAL

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --toggle)  do_toggle=true; shift ;;
            --next)    do_next=true; shift ;;
            --delete)  do_delete=true; shift ;;
            --daemon)  do_daemon=true; shift ;;
            --interval) interval="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *)
                echo "Error: Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    $do_toggle && { toggle_mode; exit 0; }
    $do_next && { next_image; exit 0; }
    $do_delete && { delete_current; exit 0; }
    $do_daemon && { run_daemon "$interval"; exit 0; }

    apply_by_mode
}

main "$@"
