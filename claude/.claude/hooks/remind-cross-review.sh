#!/usr/bin/env bash
# Remind once per unreviewed snapshot; Stop and commit hooks enforce the policy.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if ! auto_review_would_block "$SESSION" "$CWD" ""; then
    echo '{}'
    exit 0
fi
REPO=$(git -C "$CWD" rev-parse --show-toplevel)
TREE=$(review_snapshot "$REPO")
STATE="$HOME/.claude/state"
mkdir -p "$STATE"
MARKER="$STATE/review-reminded-$(repo_hash "$REPO")-$(printf '%s' "$SESSION" | portable_md5)"
if [[ -f "$MARKER" && $(cat "$MARKER") == "$TREE" ]]; then
    echo '{}'
    exit 0
fi
printf '%s\n' "$TREE" > "$MARKER"
jq -n --arg context "[auto-review] This work unit has unreviewed implementation changes. After relevant tests pass, run /cross-review before concluding or committing. Session: $SESSION. Apply evidence-first triage; resume for fix verification." \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}'
