#!/usr/bin/env bash
# Remind once per unreviewed snapshot; Stop and commit hooks enforce the policy.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if ! PENDING=$(auto_review_pending_repos "$SESSION" "$CWD"); then
    echo '{}'
    exit 0
fi
STATE="$HOME/.claude/state"
mkdir -p "$STATE"
REPO=""
while IFS= read -r CANDIDATE; do
    TREE=$(review_snapshot "$CANDIDATE")
    MARKER="$STATE/review-reminded-$(repo_hash "$CANDIDATE")-$(printf '%s' "$SESSION" | portable_md5)"
    [[ -f "$MARKER" && $(cat "$MARKER") == "$TREE" ]] && continue
    printf '%s\n' "$TREE" > "$MARKER"
    REPO="$CANDIDATE"
    break
done <<< "$PENDING"
if [[ -z "$REPO" ]]; then
    echo '{}'
    exit 0
fi
jq -n --arg context "[auto-review] This work unit has unreviewed implementation changes. After relevant tests pass, run /cross-review in $REPO before concluding or committing. Session: $SESSION. Apply evidence-first triage; resume for fix verification." \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}'
