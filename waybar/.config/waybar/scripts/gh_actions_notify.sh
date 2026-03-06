#!/bin/bash
# GitHub Actions CI notification poller
# Checks for completed workflow runs and notifies on state changes.
# Usage: Run via cron or systemd timer every 2-5 minutes.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gh-actions-notify"
mkdir -p "$STATE_DIR"

# Repos to watch (owner/repo format)
REPOS=(
  # Add your repos here, e.g.:
  # "marshallku/my-project"
)

if ! command -v gh &>/dev/null; then
  exit 0
fi

if [ ${#REPOS[@]} -eq 0 ]; then
  exit 0
fi

for repo in "${REPOS[@]}"; do
  state_file="$STATE_DIR/$(echo "$repo" | tr '/' '_')"

  # Get the latest workflow run
  run_info=$(gh run list --repo "$repo" --limit 1 --json databaseId,status,conclusion,name,headBranch 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$run_info" ]; then
    continue
  fi

  run_id=$(echo "$run_info" | jq -r '.[0].databaseId // empty')
  status=$(echo "$run_info" | jq -r '.[0].status // empty')
  conclusion=$(echo "$run_info" | jq -r '.[0].conclusion // empty')
  name=$(echo "$run_info" | jq -r '.[0].name // empty')
  branch=$(echo "$run_info" | jq -r '.[0].headBranch // empty')

  if [ -z "$run_id" ]; then
    continue
  fi

  current_state="${run_id}:${status}:${conclusion}"

  if [ -f "$state_file" ]; then
    prev_state=$(cat "$state_file")
    if [ "$prev_state" = "$current_state" ]; then
      continue
    fi
  fi

  echo "$current_state" > "$state_file"

  # Only notify on completed runs
  if [ "$status" = "completed" ]; then
    repo_short=$(echo "$repo" | cut -d'/' -f2)
    if [ "$conclusion" = "success" ]; then
      notify-send -u normal -t 8000 \
        "CI Passed: $repo_short" \
        "$name on $branch"
    elif [ "$conclusion" = "failure" ]; then
      notify-send -u critical \
        "CI Failed: $repo_short" \
        "$name on $branch"
    fi
  fi
done
