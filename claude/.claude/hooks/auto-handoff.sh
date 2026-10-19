#!/usr/bin/env bash
# Stop hook: 세션 종료 시 자동 핸드오프 저장
# git 상태를 캡처하여 다음 세션에서 참조 가능

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

HANDOFF_DIR="$HOME/.claude/handoffs"
mkdir -p "$HANDOFF_DIR"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# CWD가 없거나 git repo가 아니면 스킵
if [ -z "$CWD" ] || ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    echo '{}'
    exit 0
fi

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "detached")
DIFF_STAT=$(git -C "$CWD" diff --stat 2>/dev/null)
STAGED_STAT=$(git -C "$CWD" diff --cached --stat 2>/dev/null)
RECENT_LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null)
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

# 같은 내용을 repo 별 파일에도 둔다 — 다음 세션은 자기 repo 것만 주입받는다.
handoff_publish "$HANDOFF_TMP" "$CWD"

echo '{}'
