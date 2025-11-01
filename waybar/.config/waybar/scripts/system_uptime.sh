#!/bin/bash

uptime_seconds=$(cat /proc/uptime | awk '{print int($1)}')
days=$((uptime_seconds / 86400))
hours=$(( (uptime_seconds % 86400) / 3600 ))

if [ $days -eq 0 ]; then
    minutes=$(( (uptime_seconds % 3600) / 60 ))
    if [ $hours -eq 0 ]; then
        uptime_text="${minutes}m"
    else
        uptime_text="${hours}h ${minutes}m"
    fi
elif [ $days -lt 7 ]; then
    uptime_text="${days}d ${hours}h"
fi

echo "{\"text\": \"󰅐  $uptime_text\", \"tooltip\": \"System uptime: $(uptime -p | sed 's/up //')\"}"

