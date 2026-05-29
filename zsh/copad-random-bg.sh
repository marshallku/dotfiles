#!/bin/bash

CACHE_FILE="$HOME/.cache/terminal-wallpapers.txt"
MODE_FILE="$HOME/.cache/copad-bg-mode"
CURRENT_FILE="$HOME/.cache/copad-bg-current"
DEFAULT_INTERVAL=300
COCTL="$HOME/.local/bin/coctl"

copad_alive() {
    local id="${1:-$(instance_id)}"
    [[ -n "$id" ]] && kill -0 "$id" 2>/dev/null
}

socket_set_background() {
    local path="$1" sock="${2:-$COPAD_SOCKET}"
    $COCTL --socket "$sock" background set "$path" &>/dev/null
}

socket_clear_background() {
    local sock="${1:-$COPAD_SOCKET}"
    $COCTL --socket "$sock" background clear &>/dev/null
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
    local sock="${COPAD_SOCKET:-}"
    local base="${sock##*/}"
    base="${base#gui-}"
    base="${base#copad-}"
    echo "${base%.sock}"
}

save_current() {
    local id="$1" img="$2"
    echo "$img" > "${CURRENT_FILE}-${id}.txt"
}

get_current() {
    local id="$1"
    local file="${CURRENT_FILE}-${id}.txt"
    [[ -f "$file" ]] && cat "$file"
}

# Epoch of the last background switch for an instance, derived from the
# current-image file's mtime. save_current rewrites that file on every
# apply, so external --next/--toggle invocations reset the daemon's
# countdown here without sharing in-memory state across processes.
last_switch() {
    local id="$1"
    local file="${CURRENT_FILE}-${id}.txt"
    if [[ -f "$file" ]]; then
        stat -c %Y "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Print "<id>\t<socket>" for every live copad GUI instance, so toggle can
# broadcast to all of them via `coctl --socket`.
list_instances() {
    [[ -z "${COPAD_SOCKET:-}" ]] && return 1

    local dir="${COPAD_SOCKET%/*}"
    local f base id
    shopt -s nullglob
    for f in "$dir"/gui-*.sock; do
        base="${f##*/}"
        id="${base#gui-}"
        id="${id%.sock}"
        copad_alive "$id" && printf '%s\t%s\n' "$id" "$f"
    done
    shopt -u nullglob
}

apply_by_mode() {
    [[ -z "${COPAD_SOCKET:-}" ]] && return 1

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

# Toggle the (global) background mode and apply it immediately to every
# live copad instance. Without the broadcast, other instances' daemons
# only pick up the new mode on their next interval tick (up to `interval`
# seconds later).
toggle_mode() {
    local next
    if [[ "$(get_mode)" == "active" ]]; then
        next="deactive"
    else
        next="active"
    fi
    echo "$next" > "$MODE_FILE"

    local id sock img
    while IFS=$'\t' read -r id sock; do
        if [[ "$next" == "deactive" ]]; then
            socket_clear_background "$sock"
        else
            img=$(select_random_image) || continue
            socket_set_background "$img" "$sock"
            save_current "$id" "$img"
        fi
    done < <(list_instances)
}

next_image() {
    if [[ "$(get_mode)" == "deactive" ]]; then
        return 0
    fi

    [[ -z "${COPAD_SOCKET:-}" ]] && return 1

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
    local pid_file="$HOME/.cache/copad-bg-daemon-$(instance_id).pid"

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
        [[ -S "$COPAD_SOCKET" ]] && return 0
        sleep 0.1
    done
    return 1
}

sweep_stale() {
    local f id
    shopt -s nullglob
    for f in "$HOME/.cache/copad-bg-daemon-"*.pid; do
        id="${f##*copad-bg-daemon-}"
        id="${id%.pid}"
        if ! copad_alive "$id"; then
            local dpid
            dpid=$(cat "$f" 2>/dev/null)
            [[ -n "$dpid" ]] && kill -0 "$dpid" 2>/dev/null && kill "$dpid" 2>/dev/null
            rm -f "$f" "${CURRENT_FILE}-${id}.txt"
        fi
    done
    for f in "${CURRENT_FILE}-"*.txt; do
        id="${f##*copad-bg-current-}"
        id="${id%.txt}"
        copad_alive "$id" || rm -f "$f"
    done
    shopt -u nullglob
}

run_daemon() {
    local interval="${1:-$DEFAULT_INTERVAL}"

    if [[ -z "${COPAD_SOCKET:-}" ]]; then
        echo "Error: COPAD_SOCKET is not set" >&2
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
    local pid_file="$HOME/.cache/copad-bg-daemon-${id}.pid"
    echo $$ > "$pid_file"
    local current_file="${CURRENT_FILE}-${id}.txt"
    trap 'rm -f "$pid_file" "$current_file"; exit' EXIT INT TERM HUP

    while true; do
        sleep 10

        copad_alive "$id" || exit 0

        [[ "$(get_mode)" == "deactive" ]] && continue

        local now last
        now=$(date +%s)
        last=$(last_switch "$id")
        if (( now - last >= interval )); then
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
