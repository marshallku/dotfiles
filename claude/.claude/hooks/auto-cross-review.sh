#!/usr/bin/env bash
# Stop hook: review once per completed work unit, reusing content-bound approval.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
# Avoid recursive Stop loops after a failed review; the next user turn retries.
if [[ $(echo "$INPUT" | jq -r '.stop_hook_active // false') == true ]]; then
    echo '{}'
    exit 0
fi
# A clarification pause is not completion of the work unit.
LAST_MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if [[ "$LAST_MESSAGE" =~ \?[[:space:]]*$ ]]; then
    echo '{}'
    exit 0
fi
if ! PENDING=$(auto_review_pending_repos "$SESSION" "$CWD"); then
    echo '{}'
    exit 0
fi
# Once per unreviewed snapshot, at most once per cooldown (see review_stop_suppressed).
REPO=""
while IFS= read -r CANDIDATE; do
    TREE=$(review_snapshot "$CANDIDATE")
    if review_stop_suppressed "$CANDIDATE" "$SESSION" "$TREE"; then
        hook_event auto-cross-review skip reason=already_reminded repo="$CANDIDATE"
        continue
    fi
    REPO="$CANDIDATE"
    break
done <<< "$PENDING"
if [[ -z "$REPO" ]]; then
    echo '{}'
    exit 0
fi
review_stop_record "$REPO" "$SESSION" "$TREE"
hook_log auto-cross-review "BLOCK: unreviewed snapshot in $REPO"
hook_event auto-cross-review block repo="$REPO"
REASON="[auto-review] Before completing this work unit, run /cross-review for session $SESSION in $REPO after relevant tests pass. Follow the skill's evidence-first triage, response-file and three-round limit. Reuse approval only for unchanged reviewed content. If the baseline is missing, establish the starting commit explicitly with --base. Report errors or unresolved findings; do not claim approval."
jq -n --arg reason "$REASON" '{decision:"block", reason:$reason}'
