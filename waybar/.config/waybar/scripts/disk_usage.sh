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

echo "{\"text\": \"$icon  $usage%\", \"tooltip\": \"Disk: ${used}/${total} used (${usage}%)\", \"class\": \"$class\"}"

