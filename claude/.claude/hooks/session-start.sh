#!/bin/bash
# SessionStart hook: 이전 세션 handoff 자동 로드
# auto-handoff.sh가 저장한 latest.md를 읽어서 시스템 프롬프트에 주입

HANDOFF_FILE="$HOME/.claude/handoffs/latest.md"

# handoff 파일이 없으면 스킵
if [ ! -f "$HANDOFF_FILE" ]; then
    echo '{}'
    exit 0
fi

# 24시간 이상 지난 handoff는 무시
FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$HANDOFF_FILE" 2>/dev/null || echo 0) ))
if [ "$FILE_AGE" -gt 86400 ]; then
    echo '{}'
    exit 0
fi

CONTENT=$(cat "$HANDOFF_FILE")

# handoff 내용을 stderr로 출력 (사용자에게 보임)
cat >&2 << EOF
[handoff] Previous session context loaded ($(stat -c %Y "$HANDOFF_FILE" | xargs -I{} date -d @{} +"%Y-%m-%d %H:%M"))
EOF

# systemPrompt로 주입
jq -nc --arg content "$CONTENT" '{
  "hookSpecificOutput": {
    "systemPrompt": ("## Previous Session Context\n\nThe following handoff was saved from the previous session. Use this to understand what was being worked on. Do not repeat this information unless asked.\n\n" + $content)
  }
}'
