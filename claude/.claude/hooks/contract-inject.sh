#!/usr/bin/env bash
# UserPromptSubmit hook — auto-inject the autonomous work-unit contract when an
# autonomous loop is being started, so the user no longer has to retype the
# "plan -> review -> code -> test -> e2e -> cross-review -> save.sh" sequence
# into every /goal or /loop (which they were doing on nearly every invocation).
#
# Trigger (any of):
#   - the harness activation string for /goal and /loop:
#       "session-scoped Stop hook is now active"
#   - a literal leading /goal or /loop (in case a flow passes it raw)
#
# Output is additionalContext only — never blocks. Worst case on a false
# positive is one extra paragraph of context; on a false negative, status quo.
#
# Opt-out: touch ~/.claude/state/contract-inject-disabled

set -euo pipefail

LOG_FILE="$HOME/.claude/hooks-debug.log"
log() {
    echo "[$(date +%H:%M:%S)] contract-inject: $*" >> "$LOG_FILE"
}

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

DISABLED="$HOME/.claude/state/contract-inject-disabled"
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }
[ -z "$PROMPT" ] && { echo '{}'; exit 0; }

if ! echo "$PROMPT" | grep -qiE 'session-scoped Stop hook is now active|(^|[[:space:]])/(goal|loop)([[:space:]]|$)'; then
    echo '{}'; exit 0
fi

log "INJECT: autonomous-loop contract"

CONTRACT="[work-unit contract] You are driving an autonomous loop. Apply this gate PER work-unit (one coherent change), not once at the end — and you do NOT need the user to restate it:

  plan (if non-trivial) -> codex review of plan -> implement -> unit test -> e2e test (if applicable) -> codex cross-review -> ~/save.sh

Rules:
  - Skip a step only with a stated reason (e.g. 'e2e skipped: library-internal change, unit tests suffice'). Never skip silently.
  - The final commit ALWAYS goes through ~/save.sh, never raw git commit/push.
  - Only pause for the user at planning checkpoints; otherwise run to completion.
  - Long codex review/plan steps run foreground with an explicit timeout (600000ms); never Monitor-poll a local codex job.
This mirrors /iterate. Opt-out: touch ~/.claude/state/contract-inject-disabled"

jq -n --arg ctx "$CONTRACT" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
