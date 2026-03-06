#!/bin/bash
# Clipboard history using cliphist + wofi

if ! command -v cliphist &>/dev/null; then
  notify-send -u normal "Clipboard History" "cliphist not installed.\nInstall with: pacman -S cliphist"
  exit 1
fi

selected=$(cliphist list | wofi --dmenu --prompt "Clipboard" --cache-file /dev/null --width 600 --height 400)

if [ -n "$selected" ]; then
  echo "$selected" | cliphist decode | wl-copy
fi
