#!/bin/bash

case $1 in
    screen)
        # Capture entire screen
        grim - | wl-copy
        ;;
    window)
        # Capture active window
        hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | grim -g - - | wl-copy
        ;;
    region)
        # Capture selected region
        grim -g "$(slurp)" - | wl-copy
        ;;
esac