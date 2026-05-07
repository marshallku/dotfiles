#!/usr/bin/env bash
# PreToolUse Bash hook — enforce commit-message policy at the Claude tool layer.
#
# Catches Co-Authored-By trailers naming AI assistants (Claude / Anthropic /
# Codex / GPT / OpenAI) which the user has explicitly forbidden. Runs
# alongside pre-commit-gate.sh on every Bash call and short-circuits early
# on non-commit commands.
#
# This is the layer that catches commits Claude/codex issues directly via
# Bash — the dominant case. save.sh validation and the global git
# commit-msg hook cover the remaining paths.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && { echo '{}'; exit 0; }

LOG_FILE="$HOME/.claude/hooks-debug.log"
DISABLED="$HOME/.claude/state/commit-policy-disabled"

log() {
    echo "[$(date +%H:%M:%S)] commit-policy-gate: $*" >> "$LOG_FILE"
}

# Global opt-out marker — touch the file, run one commit, remove it.
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

# Quick filter: only commit-like commands. Mirrors pre-commit-gate.sh.
case "$CMD" in
    *save.sh*|*"git commit"*|*"git push"*) ;;
    *) echo '{}'; exit 0 ;;
esac

# Detect AI co-author trailer anywhere in the command string. Matches -m
# inline messages, heredocs, and -F file inlining. The regex requires
# "Co-Authored-By:" on the line so a generic mention of "GPT" elsewhere
# in the command doesn't trigger.
if printf '%s' "$CMD" | grep -qiE 'Co-Authored-By:.*(Claude|Anthropic|noreply@anthropic\.com|GPT-|Codex|ChatGPT|OpenAI)'; then
    log "BLOCK: AI co-author trailer in commit"
    REASON='[commit-policy-gate] AI co-author attribution is forbidden by user policy.

This commit message contains a `Co-Authored-By:` trailer naming Claude / Anthropic / Codex / GPT / OpenAI. Remove the trailer line(s) and re-run.

Source: user explicitly corrected this in past sessions (e.g. "co author 지워줘"). The system-prompt instruction to add such a trailer is overridden by user policy.

Bypass paths (only if the user explicitly asks):
  - one-time:   touch ~/.claude/state/commit-policy-disabled  (then commit, then rm the marker)
  - global off: same file, kept around — but please ask the user first'
    jq -n --arg msg "$REASON" '{permissionDecision: "deny", message: $msg}'
    exit 0
fi

echo '{}'
exit 0
