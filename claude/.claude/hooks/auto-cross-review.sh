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
if ! auto_review_would_block "$SESSION" "$CWD" ""; then
    echo '{}'
    exit 0
fi
REASON="[auto-review] Before completing this work unit, run /cross-review for session $SESSION in $CWD after relevant tests pass. Follow the skill's evidence-first triage, response-file and three-round limit. Reuse approval only for unchanged reviewed content. If the baseline is missing, establish the starting commit explicitly with --base. Report errors or unresolved findings; do not claim approval."
jq -n --arg reason "$REASON" '{decision:"block", reason:$reason}'
