#!/usr/bin/env bash
# @hook-event: Stop
# Stop hook: 세션 종료 시 자동 핸드오프 저장
# git 상태를 캡처하여 다음 세션에서 참조 가능

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

HANDOFF_DIR="$HOME/.claude/handoffs"
mkdir -p "$HANDOFF_DIR"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ] || ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    echo '{}'
    exit 0
fi

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "detached")
DIFF_STAT=$(git -C "$CWD" diff --stat 2>/dev/null)
STAGED_STAT=$(git -C "$CWD" diff --cached --stat 2>/dev/null)
RECENT_LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null || true)
REPO_NAME=$(basename "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

HANDOFF_TMP=$(mktemp "$HANDOFF_DIR/.handoff.XXXXXX")
cat > "$HANDOFF_TMP" << EOF
# Session Handoff

- **Time:** $TIMESTAMP
- **Repo:** $REPO_NAME
- **Branch:** $BRANCH
- **Session:** $SESSION_ID
- **Directory:** $CWD

## Recent Commits
\`\`\`
$RECENT_LOG
\`\`\`

## Unstaged Changes
\`\`\`
${DIFF_STAT:-No unstaged changes}
\`\`\`

## Staged Changes
\`\`\`
${STAGED_STAT:-No staged changes}
\`\`\`
EOF

# 시각 줄만 다르면 다시 쓰지 않는다 — 그러지 않으면 Stop마다 같은 파일을 덮어쓴다.
REPO_FILE=$(handoff_repo_path "$CWD" 2>/dev/null || true)
same_body() { [ -f "$2" ] && cmp -s <(grep -v '^- \*\*Time:\*\*' "$1") <(grep -v '^- \*\*Time:\*\*' "$2"); }
if [ -n "$REPO_FILE" ] && same_body "$HANDOFF_TMP" "$REPO_FILE" && same_body "$HANDOFF_TMP" "$HANDOFF_DIR/latest.md"; then
    rm -f "$HANDOFF_TMP"
    hook_log auto-handoff "skip: unchanged ($REPO_NAME)"
    echo '{}'
    exit 0
fi

# 같은 내용을 repo 별 파일에도 둔다 — 다음 세션은 자기 repo 것만 주입받는다.
handoff_publish "$HANDOFF_TMP" "$CWD"
hook_log auto-handoff "wrote ($REPO_NAME)"

echo '{}'
