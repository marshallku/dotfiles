#!/usr/bin/env bash
# PostToolUse Bash hook — sets the per-session SSoT-consulted marker whenever a
# `dn search`/`dn tag`/`dn related` query runs. The marker is what
# plan-ssot-gate.sh checks before allowing ExitPlanMode, so consulting ~/docs
# at any point in the session clears the plan gate.
#
# Pure marker-setter, never blocks. Mirrors track-edit.sh's shape.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')

[ -z "$CMD" ] && { echo '{}'; exit 0; }

# Match a `dn` retrieval subcommand anywhere in the command (handles pipes,
# env prefixes, and the absolute ~/docs/scripts/dn form). Only the read
# subcommands count as an SSoT consult — save-debug-saga etc. do not.
if echo "$CMD" | grep -qE '(^|[^[:alnum:]_/])(dn|[^[:space:]]*/dn)[[:space:]]+(search|tag|related)([[:space:]]|$)'; then
    STATE_DIR="$HOME/.claude/state"
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/ssot-checked-${SESSION}"
fi

echo '{}'
