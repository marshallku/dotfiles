#!/usr/bin/env bash
# Set / rotate the hyprpaper + hyprlock wallpaper.
#
# Both hyprpaper.conf and hyprlock.conf point at a stable symlink
# ($WALLPAPER_DIR/.current). Repointing that link updates hyprlock on the
# next lock; hyprpaper is switched live over IPC while its daemon stays up.
#
# Usage:
#   wallpaper.sh <image>     set a specific image (bare name in dir or full path)
#   wallpaper.sh set <image> explicit form of the above
#   wallpaper.sh random      pick a random image from the folder
#   wallpaper.sh next        cycle to the next image (sorted)
#   wallpaper.sh prev        cycle to the previous image
#   wallpaper.sh list        list candidate images
#   wallpaper.sh current     print the current image
#   wallpaper.sh ensure      point .current at a real file if missing (boot)
set -euo pipefail

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
CURRENT_LINK="$WALLPAPER_DIR/.current"

die() { echo "wallpaper: $*" >&2; exit 1; }

# All candidate images (real files, sorted, excluding dotfiles/.current).
candidates() {
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        ! -name '.*' | sort
}

current_target() {
    [ -L "$CURRENT_LINK" ] && readlink -f "$CURRENT_LINK" || true
}

apply() {
    local img
    img="$(readlink -f "$1")" || die "cannot resolve: $1"
    [ -f "$img" ] || die "not a file: $img"

    # Stable link drives hyprpaper boot + hyprlock (read at lock time).
    ln -sfn "$img" "$CURRENT_LINK"

    # Live switch hyprpaper if its daemon is up in this session. `listactive` is
    # the portable probe (hyprpaper v0.8.x dropped `listloaded`); guarding on it
    # also means we no-op cleanly outside a live session.
    #
    # Set each active monitor explicitly: the empty-monitor (",path") form only
    # fills monitors with NO prior assignment, so it would not update the
    # per-monitor entries declared in hyprpaper.conf. Iterating guarantees every
    # output is refreshed (matches the "all monitors identical" intent).
    #
    # preload/unload are best-effort: older hyprpaper requires preload before
    # wallpaper, while v0.8.x rejects both and auto-loads on `wallpaper`. We
    # ignore their result so the switch works on either generation.
    if command -v hyprctl >/dev/null && hyprctl hyprpaper listactive >/dev/null 2>&1; then
        local mon
        hyprctl hyprpaper preload "$img" >/dev/null 2>&1 || true
        while IFS= read -r mon; do
            [ -n "$mon" ] && hyprctl hyprpaper wallpaper "$mon,$img" >/dev/null
        done < <(hyprctl monitors -j | jq -r '.[].name')
        hyprctl hyprpaper unload unused >/dev/null 2>&1 || true
    fi
    echo "wallpaper -> $img"
}

resolve_name() {
    # Accept a full path, or a bare filename inside WALLPAPER_DIR.
    local arg="$1"
    [ -f "$arg" ] && { echo "$arg"; return; }
    [ -f "$WALLPAPER_DIR/$arg" ] && { echo "$WALLPAPER_DIR/$arg"; return; }
    die "image not found: $arg"
}

cycle() {
    local dir="$1" cur idx i
    local -a list
    mapfile -t list < <(candidates)
    [ "${#list[@]}" -gt 0 ] || die "no images in $WALLPAPER_DIR"
    cur="$(current_target)"
    idx=-1
    for i in "${!list[@]}"; do
        [ "${list[$i]}" = "$cur" ] && { idx=$i; break; }
    done
    if [ "$idx" -lt 0 ]; then idx=0; else idx=$(( (idx + dir + ${#list[@]}) % ${#list[@]} )); fi
    apply "${list[$idx]}"
}

cmd="${1:-current}"
case "$cmd" in
    random)
        mapfile -t list < <(candidates)
        [ "${#list[@]}" -gt 0 ] || die "no images in $WALLPAPER_DIR"
        apply "${list[RANDOM % ${#list[@]}]}"
        ;;
    set)     [ $# -ge 2 ] || die "usage: wallpaper.sh set <image>"; img="$(resolve_name "$2")" && apply "$img" ;;
    next)    cycle 1 ;;
    prev)    cycle -1 ;;
    list)    candidates ;;
    current) current_target ;;
    ensure)
        # First boot / fresh stow: configs reference .current, so make sure it
        # resolves to a real file before hyprpaper/hyprlock read it.
        cur="$(current_target)"
        if [ -z "$cur" ] || [ ! -f "$cur" ]; then
            mapfile -t list < <(candidates)
            [ "${#list[@]}" -gt 0 ] && ln -sfn "${list[0]}" "$CURRENT_LINK" \
                && echo "wallpaper -> ${list[0]} (initialized)"
        fi
        ;;
    -h|--help|help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)       img="$(resolve_name "$cmd")" && apply "$img" ;;
esac
