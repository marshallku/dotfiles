#!/bin/bash

WALLPAPER_DIR=""
MIN_WIDTH=1500
MIN_RATIO_NUM=2
MIN_RATIO_DEN=2
CACHE_FILE="$HOME/.cache/ghostty-wallpapers.txt"
GHOSTTY_LOCAL="$HOME/.config/ghostty/local.conf"

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
