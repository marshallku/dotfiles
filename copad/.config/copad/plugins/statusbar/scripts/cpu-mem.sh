#!/usr/bin/env bash
# copad statusbar module: 1-min load average + used memory.
# Pure /proc + coreutils, no external deps.
set -u

read -r load1 _ < /proc/loadavg

mem=$(free -b | awk '/^Mem:/ { printf "%.1fG", $3 / 1073741824 }')

# U+F2DB microchip glyph for load,  for memory — trailing spaces guard
# against wide-glyph overdraw.
printf ' %s   %s\n' "$load1" "$mem"
