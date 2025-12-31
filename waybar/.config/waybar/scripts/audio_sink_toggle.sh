#!/bin/bash

# Get all sink IDs from wpctl status
sinks=($(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -oP '\s+\*?\s+\K[0-9]+(?=\.)'))

if [ ${#sinks[@]} -eq 0 ]; then
    notify-send "Audio" "No sinks found"
    exit 1
fi

if [ ${#sinks[@]} -eq 1 ]; then
    notify-send "Audio" "Only one sink available"
    exit 0
fi

# Find current default sink (marked with *)
current_id=$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep '\*' | grep -oP '\*\s+\K[0-9]+(?=\.)')

# Find index of current sink and get next one
current_index=0
for i in "${!sinks[@]}"; do
    if [ "${sinks[$i]}" = "$current_id" ]; then
        current_index=$i
        break
    fi
done

# Calculate next index (rotate)
next_index=$(( (current_index + 1) % ${#sinks[@]} ))
next_id="${sinks[$next_index]}"

# Set new default sink
wpctl set-default "$next_id"

# Get the name of the new sink for notification
sink_name=$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -P "\*\s+${next_id}\." | sed -E 's/.*[0-9]+\.\s+(.*)\s+\[vol:.*/\1/' | xargs)

notify-send "Audio Output" "Switched to: $sink_name"
