#!/bin/bash
# Waybar YouTube Music (MPRIS) module — now-playing indicator + panel launcher.
#
# Player preference (best wins; Playing beats Paused within a tier):
#   1. YouTube Music desktop app (th-ch/youtube-music) — richest MPRIS (art, position)
#   2. Browser tab on music.youtube.com
#   3. Any player currently Playing
# Emits empty text (module hidden) when nothing relevant is playing.
#
# Requires: playerctl, jq. playerctld recommended for reliable browser tracking.
#
# Flags:
#   --player         print the chosen MPRIS instance (used by the GTK panel)
#   --play-pause / --next / --previous   transport control (bound to scroll)
#   --toggle-panel   open/close the GTK control panel (bound to click)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANEL="$SCRIPT_DIR/ytmusic_panel.py"

hidden() { echo '{"text": "", "tooltip": "", "class": "hidden"}'; exit 0; }

# Panel toggle needs no target; handle it first.
if [ "$1" = "--toggle-panel" ]; then
  if pgrep -f "[y]tmusic_panel.py" >/dev/null 2>&1; then
    pkill -f "[y]tmusic_panel.py" >/dev/null 2>&1
  else
    # Pass the click location so the panel drops right under the bar widget.
    pos=$(hyprctl cursorpos 2>/dev/null | tr -d ',')
    setsid python3 "$PANEL" $pos >/dev/null 2>&1 &
  fi
  exit 0
fi

command -v playerctl >/dev/null 2>&1 || hidden

# Echo the best player instance to control (empty if none qualifies).
select_player() {
  local players p url status score best="" best_score=0
  players=$(playerctl -l 2>/dev/null) || return
  [ -z "$players" ] && return
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    score=0
    url=$(playerctl -p "$p" metadata xesam:url 2>/dev/null)
    status=$(playerctl -p "$p" status 2>/dev/null)
    # Stopped = playback ended; drop it (Paused stays visible on purpose).
    [ "$status" = "Stopped" ] && continue
    case "$p" in
      *[Yy]outube[-._]*[Mm]usic*|*[Yy]tmusic*|*[Yy]outubeMusic*) score=40 ;;  # desktop app
    esac
    case "$url" in
      *music.youtube.com*) [ "$score" -lt 20 ] && score=20 ;;                 # browser YTM
    esac
    if [ "$score" -eq 0 ]; then
      # generic media: only a candidate when it actually has a title
      [ -n "$(playerctl -p "$p" metadata xesam:title 2>/dev/null)" ] || continue
      score=1
    fi
    [ "$status" = "Playing" ] && score=$((score + 5))
    if [ "$score" -gt "$best_score" ]; then best_score=$score; best="$p"; fi
  done <<EOF
$players
EOF
  # Suppress a merely-paused generic player (score 1); YTM stays visible when paused.
  [ "$best_score" -ge 6 ] && printf '%s' "$best"
}

target=$(select_player)

case "$1" in
  --player)     printf '%s\n' "$target"; exit 0 ;;
  --play-pause) [ -n "$target" ] && playerctl -p "$target" play-pause >/dev/null 2>&1; exit 0 ;;
  --next)       [ -n "$target" ] && playerctl -p "$target" next        >/dev/null 2>&1; exit 0 ;;
  --previous)   [ -n "$target" ] && playerctl -p "$target" previous     >/dev/null 2>&1; exit 0 ;;
esac

[ -z "$target" ] && hidden

title=$(playerctl -p "$target" metadata xesam:title 2>/dev/null)
artist=$(playerctl -p "$target" metadata xesam:artist 2>/dev/null)
album=$(playerctl -p "$target" metadata xesam:album 2>/dev/null)
url=$(playerctl -p "$target" metadata xesam:url 2>/dev/null)
status=$(playerctl -p "$target" status 2>/dev/null)

[ -z "$title" ] && hidden

# nf-md glyphs (this Nerd Font lacks the old fa youtube glyph, so use md-range).
case "$target$url" in
  *[Yy]outube*[Mm]usic*|*music.youtube.com*) icon="󰗃" ;;  # nf-md-youtube
  *) icon="󰎈" ;;                                            # nf-md-music_note
esac

if [ "$status" = "Playing" ]; then class="playing"; state=""; else class="paused"; state="󰏤 "; fi

trunc() {
  local s="$1" n="$2"
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:$((n - 1))}"; else printf '%s' "$s"; fi
}
pango() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

text="${state}${icon}  $(pango "$(trunc "$title" 32)")"

tooltip="$(pango "$title")"
[ -n "$artist" ] && tooltip="$tooltip
$(pango "$artist")"
[ -n "$album" ] && tooltip="$tooltip
$(pango "$album")"
tooltip="$tooltip
Click: open panel  ·  Scroll: prev/next"

jq -cn --arg t "$text" --arg tt "$tooltip" --arg c "$class" \
  '{text: $t, tooltip: $tt, class: $c}'
