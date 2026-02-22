#!/bin/bash

WALLPAPER_DIR=""
MIN_WIDTH=1500
MIN_RATIO_NUM=2
MIN_RATIO_DEN=2
CACHE_FILE="$HOME/.cache/terminal-wallpapers.txt"
MODE_FILE="$HOME/.cache/kitty-bg-mode"
CURRENT_FILE="$HOME/.cache/kitty-bg-current"
DEFAULT_INTERVAL=300

g_elapsed=0

is_valid_image() {
    local img="$1"
    local dimensions width height

    dimensions=$(identify -format "%w %h" "$img" 2>/dev/null | head -1)
    [[ -z "$dimensions" ]] && return 1

    read -r width height <<< "$dimensions"

    (( width < MIN_WIDTH )) && return 1
    (( width * MIN_RATIO_DEN < height * MIN_RATIO_NUM )) && return 1

    return 0
}

rebuild_cache() {
    mkdir -p "$(dirname "$CACHE_FILE")"

    declare -A cached=()
    local removed=0 added=0

    # 기존 캐시에서 삭제된 파일 제거
    if [[ -f "$CACHE_FILE" ]] && [[ -s "$CACHE_FILE" ]]; then
        while IFS= read -r path; do
            if [[ -f "$path" ]]; then
                cached["$path"]=1
            else
                ((removed++))
            fi
        done < "$CACHE_FILE"
    fi

    # 새 이미지만 검증
    while IFS= read -r -d '' img; do
        if [[ -z "${cached[$img]+x}" ]] && is_valid_image "$img"; then
            cached["$img"]=1
            ((added++))
            printf "\r새 이미지: %d개" "$added"
        fi
    done < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)

    [[ $added -gt 0 ]] && echo ""

    # 캐시 파일 갱신
    printf "%s\n" "${!cached[@]}" > "$CACHE_FILE"

    local total
    total=$(wc -l < "$CACHE_FILE")
    echo "제거: ${removed}개 / 추가: ${added}개 / 총: ${total}개"
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

save_current() {
    g_elapsed=0
    local socket_name="$1" img="$2"
    echo "$img" > "${CURRENT_FILE}-${socket_name}.txt"
}

get_current() {
    local socket_name="$1"
    local file="${CURRENT_FILE}-${socket_name}.txt"
    [[ -f "$file" ]] && cat "$file"
}

# 현재 kitty 인스턴스에 모드에 맞게 적용
apply_by_mode() {
    local socket="${1:-$KITTY_LISTEN_ON}"
    local socket_name
    socket_name=$(basename "${socket#unix:}")

    if [[ "$(get_mode)" == "deactive" ]]; then
        kitty @ --to "$socket" set-background-image none 2>/dev/null
    else
        local img
        img=$(select_random_image) || return 1
        kitty @ --to "$socket" set-background-image "$img" 2>/dev/null
        save_current "$socket_name" "$img"
    fi
}

# 모든 kitty 인스턴스에 적용
apply_to_all() {
    local mode
    mode=$(get_mode)

    for socket in /tmp/kitty-*; do
        [[ -S "$socket" ]] || continue
        if [[ "$mode" == "deactive" ]]; then
            kitty @ --to "unix:$socket" set-background-image --all none 2>/dev/null
        else
            local img
            img=$(select_random_image) || continue
            kitty @ --to "unix:$socket" set-background-image --all "$img" 2>/dev/null
        fi
    done
}

toggle_mode() {
    local current
    current=$(get_mode)

    if [[ "$current" == "active" ]]; then
        echo "deactive" > "$MODE_FILE"
    else
        echo "active" > "$MODE_FILE"
    fi

    apply_to_all
}

next_image() {
    if [[ "$(get_mode)" == "deactive" ]]; then
        return 0
    fi

    local img
    img=$(select_random_image) || return 1
    kitty @ --to "$KITTY_LISTEN_ON" set-background-image "$img" 2>/dev/null
    save_current "$(socket_id)" "$img"
}

delete_current() {
    local sid
    sid=$(socket_id)
    local img
    img=$(get_current "$sid")

    if [[ -z "$img" ]]; then
        return 1
    fi

    # 이미지 파일 삭제
    rm -f "$img"

    # 캐시에서 제거
    if [[ -f "$CACHE_FILE" ]]; then
        grep -v -xF "$img" "$CACHE_FILE" > "${CACHE_FILE}.tmp"
        mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    fi

    # 새 이미지 적용
    next_image
}

socket_id() {
    local socket_path="${KITTY_LISTEN_ON#unix:}"
    basename "$socket_path"
}

daemon_running() {
    local pid_file="$HOME/.cache/kitty-bg-daemon-$(socket_id).pid"

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

run_daemon() {
    local interval="${1:-$DEFAULT_INTERVAL}"

    # 즉시 1회 적용
    apply_by_mode

    # 이미 같은 소켓에 데몬이 돌고 있으면 종료
    if daemon_running; then
        exit 0
    fi

    local pid_file="$HOME/.cache/kitty-bg-daemon-$(socket_id).pid"
    echo $$ > "$pid_file"
    local current_file="${CURRENT_FILE}-$(socket_id).txt"
    trap 'rm -f "$pid_file" "$current_file"; exit' EXIT INT TERM HUP

    local socket_path="${KITTY_LISTEN_ON#unix:}"

    while true; do
        sleep 10

        # kitty 소켓이 사라졌으면 종료
        [[ -S "$socket_path" ]] || exit 0

        g_elapsed=$((g_elapsed + 10))
        if (( g_elapsed >= interval )); then
            g_elapsed=0
            apply_by_mode
        fi
    done
}

usage() {
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  -w, --wallpaper-path <경로>  배경화면 디렉토리 경로 (필수: --rebuild 시)"
    echo "  --rebuild                    유효한 이미지 캐시 재생성"
    echo "  --toggle                     모드 전환"
    echo "  --next                       즉시 다음 이미지로 교체"
    echo "  --delete                     현재 배경 이미지 삭제"
    echo "  --daemon                     데몬 모드 (자동 로테이션)"
    echo "  --interval <초>              로테이션 간격 (기본: 300초)"
    echo "  --dry-run                    설정 변경 없이 선택만"
    echo "  -h, --help                   이 도움말"
}

main() {
    local do_rebuild=false
    local do_toggle=false
    local do_next=false
    local do_delete=false
    local do_daemon=false
    local dry_run=false
    local interval=$DEFAULT_INTERVAL

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w|--wallpaper-path)
                WALLPAPER_DIR="$2"
                shift 2
                ;;
            --rebuild)
                do_rebuild=true
                shift
                ;;
            --toggle)
                do_toggle=true
                shift
                ;;
            --next)
                do_next=true
                shift
                ;;
            --delete)
                do_delete=true
                shift
                ;;
            --daemon)
                do_daemon=true
                shift
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Error: 알 수 없는 옵션: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if $do_rebuild; then
        if [[ -z "$WALLPAPER_DIR" ]]; then
            echo "Error: --wallpaper-path 옵션이 필요합니다." >&2
            usage
            exit 1
        fi

        if [[ ! -d "$WALLPAPER_DIR" ]]; then
            echo "Error: 디렉토리가 존재하지 않습니다: $WALLPAPER_DIR" >&2
            exit 1
        fi

        rebuild_cache
        exit 0
    fi

    if $do_toggle; then
        toggle_mode
        exit 0
    fi

    if $do_next; then
        next_image
        exit 0
    fi

    if $do_delete; then
        delete_current
        exit 0
    fi

    if $do_daemon; then
        run_daemon "$interval"
        exit 0
    fi

    # 기본: 1회 적용 (하위 호환)
    if [[ ! -f "$CACHE_FILE" ]] || [[ ! -s "$CACHE_FILE" ]]; then
        exit 0
    fi

    $dry_run && { select_random_image; exit 0; }

    apply_by_mode
}

main "$@"
