#!/bin/bash
# ~/.config/waybar/scripts/system_graph.sh

# Get CPU usage
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')

# Get memory usage
mem_usage=$(free | grep Mem | awk '{printf "%d", ($3/$2) * 100}')

# Generate bar graphs
blocks="▁▂▃▄▅▆▇█"

# CPU bar
cpu_index=$((cpu_usage / 13))
[ $cpu_index -gt 7 ] && cpu_index=7
cpu_bar="${blocks:$cpu_index:1}"

# Memory bar
mem_index=$((mem_usage / 13))
[ $mem_index -gt 7 ] && mem_index=7
mem_bar="${blocks:$mem_index:1}"

# Get memory values for tooltip
mem_used=$(free -h | grep Mem | awk '{print $3}')
mem_total=$(free -h | grep Mem | awk '{print $2}')

# Output with gaps between elements
echo "{\"text\": \"$cpu_bar $mem_bar\", \"tooltip\": \"CPU: ${cpu_usage}%\\nRAM: ${mem_used} / ${mem_total} (${mem_usage}%)\"}"