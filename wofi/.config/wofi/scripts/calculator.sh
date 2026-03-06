#!/bin/bash
# Quick calculator using wofi + python3

result=""
while true; do
  if [ -n "$result" ]; then
    prompt="= $result | New expression"
  else
    prompt="Expression (e.g. 2+2, sqrt(16), sin(pi/2))"
  fi

  expr=$(echo "" | wofi --dmenu --prompt "$prompt" --cache-file /dev/null --width 500 --height 50)

  if [ -z "$expr" ]; then
    break
  fi

  result=$(python3 -c "
from math import *
try:
    r = eval('$expr')
    if isinstance(r, float) and r == int(r):
        print(int(r))
    else:
        print(r)
except Exception as e:
    print(f'Error: {e}')
" 2>&1)

  echo -n "$result" | wl-copy
  notify-send -t 3000 "Calculator" "$expr = $result (copied)"
done
