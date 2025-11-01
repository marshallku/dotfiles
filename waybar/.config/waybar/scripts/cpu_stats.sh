#!/bin/bash

cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')

blocks="▁▂▃▄▅▆▇█"
cpu_index=$((cpu_usage / 13))
[ $cpu_index -gt 7 ] && cpu_index=7
cpu_bar="${blocks:$cpu_index:1}"

echo "{\"text\": \"   $cpu_bar ${cpu_usage}%\", \"tooltip\": \"CPU: ${cpu_usage}%\"}"

