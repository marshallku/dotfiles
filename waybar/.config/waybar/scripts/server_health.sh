#!/bin/bash

SERVER_GROUPS=(
  "HomeLab:marshallku.com",
  "Cloud:cdn.marshallku.com/files/favicon.ico"
)

TIMEOUT=3

# Check if a server is up
check_server() {
  local domain=$1

  if [[ ! $domain =~ ^https?:// ]]; then
    domain="https://$domain"
  fi

  if curl -sSf --max-time $TIMEOUT "$domain" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

total=0
up=0
down=0
status_details=""
group_info=()

for group_def in "${SERVER_GROUPS[@]}"; do
  if [ -z "$group_def" ] || [[ "$group_def" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  group_def=$(echo "$group_def" | sed 's/,$//')
  group_name=$(echo "$group_def" | cut -d':' -f1)
  domains_str=$(echo "$group_def" | cut -d':' -f2-)

  # Count servers in this group (split by comma and count)
  IFS=',' read -ra DOMAINS <<< "$domains_str"
  group_count=0
  for domain in "${DOMAINS[@]}"; do
    domain=$(echo "$domain" | xargs)
    if [ -n "$domain" ]; then
      ((group_count++))
    fi
  done
  group_info+=("$group_name $group_count")

  status_details="${status_details}\n$group_name:\n"
  group_up=0
  group_down=0

  # Check each server in the group
  IFS=',' read -ra DOMAINS <<< "$domains_str"
  for domain in "${DOMAINS[@]}"; do
    domain=$(echo "$domain" | xargs)
    if [ -z "$domain" ]; then
      continue
    fi

    display_name=$(echo "$domain" | sed 's|https\?://||' | sed 's|/$||')
    ((total++))

    if check_server "$domain"; then
      ((up++))
      ((group_up++))
      status_details="${status_details}  ✓ $display_name\n"
    else
      ((down++))
      ((group_down++))
      status_details="${status_details}  ✗ $display_name\n"
    fi
  done
done

# Generate group display string with names and counts
group_display_str=""
for group_info_item in "${group_info[@]}"; do
  group_name=$(echo "$group_info_item" | cut -d' ' -f1)
  group_count=$(echo "$group_info_item" | cut -d' ' -f2)
  if [ -n "$group_display_str" ]; then
    group_display_str="${group_display_str}, ${group_name} = ${group_count}"
  else
    group_display_str="${group_name} = ${group_count}"
  fi
done

# Generate output
if [ $total -eq 0 ]; then
  echo "{\"text\": \"󰒍  No servers\", \"tooltip\": \"No servers configured\"}"
elif [ $down -eq 0 ]; then
  # All servers up
  icon=""
  text="Up"
  class="healthy"
else
  # Some servers down
  icon="󰃤"
  text="$up / $total Up"
  class="unhealthy"
fi

display_text="$icon  -  $text"
if [ -n "$group_display_str" ]; then
  display_text="$display_text($group_display_str)"
fi

echo "{\"text\": \"$display_text\", \"tooltip\": \"Servers Status:${status_details%\\n}\", \"class\": \"$class\"}"

