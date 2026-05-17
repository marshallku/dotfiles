#!/bin/bash
# GPU stats for waybar.
# Optional config: ~/.config/waybar-gpu/config
#   GPU_TYPE=nvidia|amd|intel|none|auto   (default: auto)
#   GPU_INDEX=0                           (nvidia multi-GPU)
# Empty text → waybar hides the module.

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waybar-gpu/config"
GPU_TYPE="auto"
GPU_INDEX=0
[ -f "$CONFIG" ] && source "$CONFIG"

empty() { echo '{"text": "", "tooltip": ""}'; exit 0; }

if [ "$GPU_TYPE" = "auto" ]; then
  if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null; then
    GPU_TYPE=nvidia
  elif compgen -G "/sys/class/drm/card*/device/gpu_busy_percent" >/dev/null; then
    GPU_TYPE=amd
  else
    GPU_TYPE=none
  fi
fi

case "$GPU_TYPE" in
  nvidia)
    raw=$(nvidia-smi -i "$GPU_INDEX" \
      --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,name \
      --format=csv,noheader,nounits 2>/dev/null)
    [ -z "$raw" ] && empty
    IFS=',' read -r util mem_used mem_total temp power name <<< "$raw"
    util=$(echo "$util" | xargs); mem_used=$(echo "$mem_used" | xargs)
    mem_total=$(echo "$mem_total" | xargs); temp=$(echo "$temp" | xargs)
    power=$(echo "$power" | xargs); name=$(echo "$name" | xargs)
    vram=$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN { printf "%.1f / %.0f GiB", u/1024, t/1024 }')
    text="󰢮  ${util}% / ${temp}°C"
    tooltip=$(printf "%s\nUtil: %s%%\nVRAM: %s\nTemp: %s°C\nPower: %s W" \
      "$name" "$util" "$vram" "$temp" "$power")
    ;;
  amd)
    util_file=$(compgen -G "/sys/class/drm/card*/device/gpu_busy_percent" 2>/dev/null | head -1)
    [ -z "$util_file" ] && empty
    util=$(cat "$util_file" 2>/dev/null)
    temp_file=$(compgen -G "/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input" 2>/dev/null | head -1)
    temp=""
    [ -n "$temp_file" ] && temp=$(awk -v t="$(cat "$temp_file")" 'BEGIN { printf "%.0f", t/1000 }')
    text="󰢮  ${util}%"
    [ -n "$temp" ] && text="${text} / ${temp}°C"
    tooltip=$(printf "AMD GPU\nUtil: %s%%" "$util")
    [ -n "$temp" ] && tooltip="$(printf "%s\nTemp: %s°C" "$tooltip" "$temp")"
    ;;
  intel|none|*)
    empty
    ;;
esac

jq -c --null-input --arg text "$text" --arg tip "$tooltip" \
  '{text: $text, tooltip: $tip}'
