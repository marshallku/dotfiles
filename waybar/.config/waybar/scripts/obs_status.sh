#!/bin/bash
# Waybar OBS module — REC/LIVE indicator, visible only while OBS records or streams.
#
# Emits empty text (module hidden) when OBS is not running, websocket is off, or idle.
# Connection info is read from OBS's own obs-websocket config so no secret is duplicated.
#
# Requires: obs-cmd (AUR: obs-cmd-bin), jq, and obs-websocket enabled in OBS.
#
# Flags:
#   --toggle-record   toggle recording (bound to on-click)

WS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/obs-studio/plugin_config/obs-websocket/config.json"

idle() { echo '{"text": "", "tooltip": "", "class": "idle"}'; exit 0; }

command -v obs-cmd >/dev/null 2>&1 || idle
pgrep -x obs >/dev/null 2>&1 || idle
[ -f "$WS_CONFIG" ] || idle

enabled=$(jq -r '.server_enabled // false' "$WS_CONFIG" 2>/dev/null)
[ "$enabled" = "true" ] || idle

port=$(jq -r '.server_port // 4455' "$WS_CONFIG" 2>/dev/null)
auth=$(jq -r '.auth_required // false' "$WS_CONFIG" 2>/dev/null)
pass=$(jq -r '.server_password // ""' "$WS_CONFIG" 2>/dev/null)

if [ "$auth" = "true" ] && [ -n "$pass" ]; then
  URL="obsws://localhost:${port}/${pass}"
else
  URL="obsws://localhost:${port}/"
fi

# Action handler (on-click): toggle recording
if [ "$1" = "--toggle-record" ]; then
  obs-cmd -w "$URL" recording toggle >/dev/null 2>&1
  exit 0
fi

# Extract "<key> <value>" from obs-cmd's "  Key: value" status lines.
# Uses the first ": " as separator so timecode colons stay intact.
field() {
  printf '%s\n' "$1" | sed -n "s/.*${2}[[:space:]]*//p" | head -n1 | sed 's/[[:space:]]*$//'
}

# HH:MM:SS.mmm -> drop ms, drop leading zero hour group (00:12:34 -> 12:34).
fmt_tc() {
  local tc="${1%%.*}"
  case "$tc" in
    "")      echo "" ;;
    00:*:*)  echo "${tc#00:}" ;;
    0*:*:*)  echo "${tc#0}" ;;
    *)       echo "$tc" ;;
  esac
}

rec_out=$(obs-cmd -w "$URL" recording status 2>/dev/null)
stream_out=$(obs-cmd -w "$URL" streaming status 2>/dev/null)

rec_active=$(field "$rec_out" "Active:" | tr '[:upper:]' '[:lower:]')
stream_active=$(field "$stream_out" "Active:" | tr '[:upper:]' '[:lower:]')

rec_tc=$(fmt_tc "$(field "$rec_out" "Timecode:")")
stream_tc=$(fmt_tc "$(field "$stream_out" "Timecode:")")

if [ "$stream_active" = "true" ]; then
  class="streaming"
  text="󰕧 LIVE"
  [ -n "$stream_tc" ] && text="$text ${stream_tc}"
  tooltip="Streaming${stream_tc:+  $stream_tc}"
  if [ "$rec_active" = "true" ]; then
    text="$text  󰻃 REC"
    [ -n "$rec_tc" ] && text="$text ${rec_tc}"
    tooltip="$tooltip\nRecording${rec_tc:+  $rec_tc}"
  fi
  tooltip="$tooltip\nClick: toggle recording"
elif [ "$rec_active" = "true" ]; then
  class="recording"
  text="󰻃 REC"
  [ -n "$rec_tc" ] && text="$text ${rec_tc}"
  tooltip="Recording${rec_tc:+  $rec_tc}\nClick: stop recording"
else
  idle
fi

printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$class"
