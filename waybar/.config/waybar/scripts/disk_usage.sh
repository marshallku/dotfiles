#!/bin/bash

usage=$(df -h /home | awk 'NR==2 {print $5}' | sed 's/%//')
used=$(df -h /home | awk 'NR==2 {print $3}')
total=$(df -h /home | awk 'NR==2 {print $2}')

if [ $usage -ge 90 ]; then
    icon="󰍜"
    class="critical"
elif [ $usage -ge 75 ]; then
    icon="󰍛"
    class="warning"
else
    icon=""
    class="normal"
fi

text="$icon  $usage%"
tooltip="Disk: ${used}/${total} used (${usage}%)"

if command -v sensors &>/dev/null; then
  first_temp=""
  nvme_temps=$(sensors 2>/dev/null | awk '
    /^nvme-/ { chip=$0; next }
    /^$/ { chip="" }
    chip && /^Composite:/ {
      match($0, /\+[0-9]+\.[0-9]+/)
      if (RSTART > 0) {
        t = substr($0, RSTART+1, RLENGTH-1)
        printf "\\n%s: %s°C", chip, t
      }
    }
  ')
  if [ -n "$nvme_temps" ]; then
    first_temp=$(echo -e "$nvme_temps" | awk -F': ' 'NF>=2 { print $2; exit }')
    text="$text  ${first_temp}"
    tooltip="${tooltip}${nvme_temps}"
  fi
fi

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"

