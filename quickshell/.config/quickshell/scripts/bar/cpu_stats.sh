#!/bin/bash

cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')

#blocks="▁▂▃▄▅▆▇█"
#cpu_index=$((cpu_usage / 13))
#[ $cpu_index -gt 7 ] && cpu_index=7
#cpu_bar="${blocks:$cpu_index:1}"


#text="   $cpu_bar ${cpu_usage}%"
text="  ${cpu_usage}%"
tooltip="CPU: ${cpu_usage}%"

if command -v sensors &>/dev/null; then
  cpu_temp=$(sensors 2>/dev/null | grep -E '^(Tctl|Tdie|Package id 0):' | head -1 | grep -oE '\+[0-9]+\.[0-9]+' | head -1 | tr -d '+')
  if [ -n "$cpu_temp" ]; then
    text="$text / ${cpu_temp}°C"
    tooltip="$tooltip\nCPU Temp: ${cpu_temp}°C"
  fi
fi

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\"}"
