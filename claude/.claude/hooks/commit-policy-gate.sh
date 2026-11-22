#!/usr/bin/env bash
# @hook-event: PreToolUse
# PreToolUse Bash hook — deny commit messages with a co-author trailer (whoever it names) or a
# "Generated with Claude Code" line, and gh merges/PR text that would carry them
# (_gh_merge_policy.py; GitHub-side merge commits pass no git hook). save.sh and the global
# commit-msg hook cover commits made outside the Bash tool.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -d "$CWD" ] || CWD=$PWD

[ -z "$CMD" ] && { echo '{}'; exit 0; }

LOG_FILE="$HOME/.claude/hooks-debug.log"
DISABLED="$HOME/.claude/state/commit-policy-disabled"
# A trailer starts a message line (only punctuation, quotes or an emoji before it), or
# arrives as `--trailer Co-authored-by=…` / its own `-m "Co-authored-by: …"`. Anchoring
# keeps commands that merely contain the text (a heredoc writing these docs) allowed.
# The line-start half is identical in ~/save.sh and ~/.config/git/hooks/commit-msg.
ATTRIBUTION_RE='^[^[:alnum:]]*(Co-Authored-By[[:space:]]*:|Generated with \[?Claude)|(--trailer|-m)[[:space:]=]+["'\'']?Co-Authored-By'

log() {
    hook_log commit-policy-gate "$@"
}

# Global opt-out marker — touch the file, run one commit, remove it.
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

# GitHub-side commits: `gh pr merge` (GitHub writes the squash message and appends
# co-author trailers unless a body is given), PR text, and `gh api .../merge`.
case "$CMD" in
    *gh*)
        # Fail closed: a missing or crashing checker must not read as "no reason" and allow.
        if ! GH_REASON=$(printf '%s' "$CMD" | python3 "$(dirname "$0")/_gh_merge_policy.py" "$CWD" 2>/dev/null); then
            GH_REASON=""
            if [[ $CMD =~ gh[[:space:]].*(merge|create|edit|api) ]]; then
                GH_REASON="The attribution checker (hooks/_gh_merge_policy.py) is missing or failed, so this gh write cannot be checked. Repair the hooks install (~/.claude/hooks must link the whole dotfiles hooks directory)."
            fi
        fi
        if [ -n "$GH_REASON" ]; then
            log "BLOCK: gh attribution/default merge message"
            jq -n --arg msg "[commit-policy-gate] $GH_REASON

Co-author / AI attribution is forbidden by user policy, including in GitHub merge commits.
Bypass (only if the user explicitly asks): touch ~/.claude/state/commit-policy-disabled" \
                '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
            exit 0
        fi
        ;;
esac

# Quick filter: only commands that really commit. Same classifier as
# pre-commit-gate.sh, so `grep Co-Authored-By ~/save.sh` is not a commit.
case "$CMD" in
    *save.sh*|*"git commit"*) ;;
    *) echo '{}'; exit 0 ;;
esac
TARGETS=$(printf '%s' "$CMD" | python3 "$(dirname "$0")/_commit_targets.py" "$CWD" 2>/dev/null) || TARGETS=""
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
    # Claude Code ignores a top-level {permissionDecision}; only hookSpecificOutput decides.
    jq -n --arg msg "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
    exit 0
fi

echo '{}'
exit 0
