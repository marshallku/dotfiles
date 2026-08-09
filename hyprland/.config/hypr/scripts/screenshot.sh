#!/bin/bash

# grim failing must not be masked by wl-copy succeeding
set -o pipefail

# Screenshot helper. Everything lands on the clipboard.
#
# Modes:
#   screen       whole output
#   window       active window
#   region       free-draw selection
#   interactive  macOS-like: starts as free-draw, SPACE toggles window picking
#   toggle       (internal) flips interactive mode, bound inside the screenshot submap
#   abort        (internal) cancels interactive mode
#
# Window shots go through grim's foreign-toplevel capture (-T), so they contain the
# window's own buffer only: no notifications or other windows layered on top, and no
# desktop bleeding through the compositor's opacity rules. Hyprland rounds corners at
# composite time, so the rounding and the drop shadow are re-applied here instead.

TOGGLE_FLAG="${XDG_RUNTIME_DIR:-/tmp}/hypr-screenshot-toggle"
SUBMAP="screenshot"
SHADOW=${SCREENSHOT_SHADOW:-1}
TMPFILE=

# Only the scratch capture: the toggle flag is owned by the interactive loop, and a
# `toggle` invocation runs this same script, so clearing it here would eat the flag it
# had just written.
cleanup() {
    [ -n "$TMPFILE" ] && rm -f "$TMPFILE" "${TMPFILE%.png}-decorated.png"
    return 0
}

# Covers the direct modes too, so a signal mid-capture never leaves a temp PNG behind
trap cleanup EXIT

to_clipboard() {
    wl-copy -t image/png < "$1" && notify-send "Screenshot taken"
}

capture_region() {
    local geometry=$1

    if [ -z "$geometry" ]; then
        return 1
    fi

    grim -g "$geometry" - | wl-copy -t image/png && notify-send "Screenshot taken"
}

# Transparent rounded corners matching decoration:rounding, then an optional drop
# shadow on a larger transparent canvas. DstIn multiplies the mask into the existing
# alpha, so a window that is itself translucent stays translucent.
decorate() {
    local file=$1 rounded=$2 shadow=$3 radius width height work
    local -a ops=()

    radius=$(hyprctl getoption -j decoration:rounding | jq -r '.int')

    if [ "$rounded" = 1 ] && [ "$radius" -gt 0 ]; then
        read -r width height < <(magick identify -format "%w %h" "$file")
        ops+=(
            \( +clone -alpha transparent -background none -fill white
               -draw "roundrectangle 0,0,$((width - 1)),$((height - 1)),$radius,$radius" \)
            -compose DstIn -composite
        )
    fi

    if [ "$shadow" = 1 ]; then
        # -compose Over matters: the rounding step above leaves DstIn active, which
        # would otherwise make the merge mask the window away instead of stacking it
        ops+=(
            \( +clone -background black -shadow 55x18+0+10 \) +swap
            -compose Over -background none -layers merge +repage
        )
    fi

    if [ ${#ops[@]} -eq 0 ]; then
        return 0
    fi

    # Render to a scratch file so a failed run cannot leave a half-written capture
    work="${file%.png}-decorated.png"

    if ! magick "$file" "${ops[@]}" "$work"; then
        rm -f "$work"
        return 1
    fi

    mv "$work" "$file"
}

# $1 foreign-toplevel id, $2 fullscreen state, $3 geometry to fall back on
capture_toplevel() {
    local id=$1 fullscreen=$2 fallback=$3 rounded=1 shadow=$SHADOW

    if [ -z "$id" ] || [ "$id" = null ]; then
        capture_region "$fallback"
        return
    fi

    TMPFILE=$(mktemp --tmpdir screenshot-XXXXXX.png)

    # XWayland or a window that lost its handle mid-selection
    if ! grim -T "$id" "$TMPFILE" 2>/dev/null; then
        cleanup
        TMPFILE=
        capture_region "$fallback"
        return
    fi

    # A fullscreen window has no corners to round and nothing to lift off a canvas
    if [ "$fullscreen" != 0 ]; then
        rounded=0
        shadow=0
    fi

    if ! decorate "$TMPFILE" "$rounded" "$shadow"; then
        cleanup
        TMPFILE=
        notify-send "Screenshot failed"
        return 1
    fi

    to_clipboard "$TMPFILE"
    local copy_status=$?

    rm -f "$TMPFILE"
    TMPFILE=

    return $copy_status
}

# Every window visible right now (active workspace of each monitor) as
# "x,y wxh<TAB>id<TAB>fullscreen". slurp -r only ever sees the first field, and it
# hands back nothing but that box — so identical boxes would be ambiguous. Ordering by
# focus history puts the window the user actually sees first, and the dedupe drops the
# ones stacked underneath it.
window_boxes() {
    local visible
    visible=$(hyprctl -j monitors | jq -c '[.[].activeWorkspace.id]')

    hyprctl -j clients | jq -r --argjson visible "$visible" '
        [ .[] | select(.mapped and (.hidden | not) and (.workspace.id as $id | $visible | index($id))) ]
        | sort_by(.focusHistoryID)
        | .[]
        | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])\t\(.stableId)\t\(.fullscreen)"
    ' | awk -F'\t' '!seen[$1]++'
}

leave_submap() {
    cleanup
    rm -f "$TOGGLE_FLAG"
    hyprctl dispatch submap reset >/dev/null
}

# Loops so SPACE can switch between free-draw and window picking: the submap bind
# leaves a flag behind and kills slurp, and we simply restart it in the other mode.
interactive() {
    local mode=region geometry status boxes id fullscreen

    rm -f "$TOGGLE_FLAG"
    hyprctl dispatch submap "$SUBMAP" >/dev/null

    # Never strand Hyprland in the submap if we die mid-selection
    trap leave_submap EXIT
    trap 'exit 130' INT TERM HUP

    while true; do
        id=
        fullscreen=

        if [ "$mode" = region ]; then
            geometry=$(slurp)
            status=$?
        else
            boxes=$(window_boxes)
            geometry=$(cut -f1 <<< "$boxes" | slurp -r)
            status=$?
            IFS=$'\t' read -r id fullscreen < <(
                awk -F'\t' -v box="$geometry" '$1 == box { print $2 "\t" $3; exit }' <<< "$boxes"
            )
        fi

        # A completed selection always wins, even if SPACE landed at the same moment
        if [ "$status" -eq 0 ]; then
            break
        fi

        if [ ! -e "$TOGGLE_FLAG" ]; then
            break
        fi

        rm -f "$TOGGLE_FLAG"

        if [ "$mode" = region ]; then
            mode=window
        else
            mode=region
        fi
    done

    leave_submap
    trap cleanup EXIT
    trap - INT TERM HUP

    if [ "$status" -ne 0 ]; then
        return 0
    fi

    if [ -n "$id" ]; then
        capture_toplevel "$id" "$fullscreen" "$geometry"
    else
        capture_region "$geometry"
    fi
}

case $1 in
    screen)
        grim - | wl-copy -t image/png && notify-send "Screenshot taken"
        ;;
    window)
        active=$(hyprctl -j activewindow)
        capture_toplevel \
            "$(jq -r '.stableId' <<< "$active")" \
            "$(jq -r '.fullscreen' <<< "$active")" \
            "$(jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' <<< "$active")"
        ;;
    region)
        capture_region "$(slurp)"
        ;;
    interactive)
        interactive
        ;;
    toggle)
        if pgrep -x slurp >/dev/null; then
            touch "$TOGGLE_FLAG"
            pkill -x slurp
        fi
        ;;
    abort)
        rm -f "$TOGGLE_FLAG"
        pkill -x slurp
        hyprctl dispatch submap reset >/dev/null
        ;;
esac
