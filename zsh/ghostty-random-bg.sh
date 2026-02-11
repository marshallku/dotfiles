#!/bin/bash

WALLPAPER_DIR=""
CACHE_FILE="$HOME/.cache/terminal-wallpapers.txt"
GHOSTTY_LOCAL="$HOME/.config/ghostty/local.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rebuild_cache() {
    go run "$SCRIPT_DIR/ghostty-random-bg/" "$WALLPAPER_DIR"
}

select_random_image() {
    if [[ ! -f "$CACHE_FILE" ]] || [[ ! -s "$CACHE_FILE" ]]; then
        echo "Error: 캐시 파일이 없습니다. --rebuild로 먼저 생성하세요." >&2
        exit 1
    fi

    shuf -n 1 "$CACHE_FILE"
}

update_local_config() {
    local image_path="$1"

    mkdir -p "$(dirname "$GHOSTTY_LOCAL")"

    if [[ ! -f "$GHOSTTY_LOCAL" ]]; then
        echo "background-image = $image_path" > "$GHOSTTY_LOCAL"
        return
    fi

    if grep -q "^background-image = " "$GHOSTTY_LOCAL"; then
        sed -i "s|^background-image = .*|background-image = $image_path|" "$GHOSTTY_LOCAL"
    else
        echo "background-image = $image_path" >> "$GHOSTTY_LOCAL"
    fi
}

reload_ghostty() {
    pkill -SIGUSR2 -x ghostty 2>/dev/null
}

usage() {
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  -w, --wallpaper-path <경로>  배경화면 디렉토리 경로 (필수)"
    echo "  --rebuild                    유효한 이미지 캐시 재생성"
    echo "  --dry-run                    설정 변경 없이 선택만"
    echo "  -h, --help                   이 도움말"
    echo ""
    echo "메인 config에 다음 줄을 추가하세요:"
    echo "  config-file = ?~/.config/ghostty/local.conf"
}

main() {
    local do_rebuild=false
    local dry_run=false

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

    if [[ ! -f "$CACHE_FILE" ]] || [[ ! -s "$CACHE_FILE" ]]; then
        exit 0
    fi

    local selected_image
    selected_image=$(select_random_image)

    $dry_run && exit 0

    update_local_config "$selected_image"
    reload_ghostty
}

main "$@"
