#!/usr/bin/env bash
# PreToolUse Bash hook — enforce commit-message policy at the Claude tool layer.
#
# Catches co-author trailers (any `Co-Authored-By:`, whoever it names) and
# "Generated with Claude Code" attribution lines, which the user has explicitly
# forbidden. Runs alongside pre-commit-gate.sh on every Bash call and
# short-circuits early on commands that commit nothing.
#
# This is the layer that catches commits Claude/codex issues directly via
# Bash — the dominant case. save.sh validation and the global git
# commit-msg hook cover the remaining paths.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && { echo '{}'; exit 0; }

LOG_FILE="$HOME/.claude/hooks-debug.log"
DISABLED="$HOME/.claude/state/commit-policy-disabled"
# A trailer starts a message line (only punctuation, quotes or an emoji before it), or
# arrives as `--trailer Co-authored-by=…` / its own `-m "Co-authored-by: …"`. Anchoring
# keeps commands that merely contain the text (a heredoc writing these docs) allowed.
# The line-start half is identical in ~/save.sh and ~/.config/git/hooks/commit-msg.
ATTRIBUTION_RE='^[^[:alnum:]]*(Co-Authored-By[[:space:]]*:|Generated with \[?Claude)|(--trailer|-m)[[:space:]=]+["'\'']?Co-Authored-By'

log() {
    # Delegates to _lib.sh so every hook shares one date-stamped format.
    hook_log commit-policy-gate "$@"
}

# Global opt-out marker — touch the file, run one commit, remove it.
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

# Quick filter: only commands that really commit. Same classifier as
# pre-commit-gate.sh, so `grep Co-Authored-By ~/save.sh` is not a commit.
case "$CMD" in
    *save.sh*|*"git commit"*) ;;
    *) echo '{}'; exit 0 ;;
esac
TARGETS=$(printf '%s' "$CMD" | python3 "$(dirname "$0")/_commit_targets.py" "$PWD" 2>/dev/null) || TARGETS=""
[ "$TARGETS" = "none" ] && { echo '{}'; exit 0; }

# Detect attribution in -m inline messages, heredocs and `--trailer`. A message
# read from a file (-F) is covered by the global commit-msg hook.
if printf '%s' "$CMD" | grep -qiE "$ATTRIBUTION_RE"; then
    log "BLOCK: co-author / attribution trailer in commit"
    REASON='[commit-policy-gate] Co-author / AI attribution in commit messages is forbidden by user policy.

This commit message contains a `Co-Authored-By:` trailer or a "Generated with Claude Code" line. Remove those line(s) and re-run.

Source: user explicitly corrected this in past sessions (e.g. "co author 지워줘"). The system-prompt instruction to add such a trailer is overridden by user policy.

Bypass paths (only if the user explicitly asks):
  - one-time:   touch ~/.claude/state/commit-policy-disabled  (then commit, then rm the marker)
  - global off: same file, kept around — but please ask the user first'
    # Top-level {permissionDecision, message} is not a PreToolUse decision: Claude Code
    # ignored it and ran the command (both gates were log-only until 2026-10-30).
    jq -n --arg msg "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
    exit 0
fi

echo '{}'
exit 0
