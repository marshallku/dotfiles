#!/usr/bin/env bash
# SessionStart hook: 이전 세션 handoff 자동 로드
# auto-handoff.sh가 저장한 latest.md를 읽어서 시스템 프롬프트에 주입

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

# 부수 작업: auto-cross-review state 파일 중 1일 이상 된 것 청소
STATE_DIR="$HOME/.claude/state"
if [ -d "$STATE_DIR" ]; then
    find "$STATE_DIR" -maxdepth 1 -type f \( -name "dirty-*.log" -o -name "stop-blocked-*" \) -mtime +1 -delete 2>/dev/null || true
fi

HANDOFF_FILE="$HOME/.claude/handoffs/latest.md"

# handoff 파일이 없으면 스킵
if [ ! -f "$HANDOFF_FILE" ]; then
    echo '{}'
    exit 0
fi

# 24시간 이상 지난 handoff는 무시
HANDOFF_MTIME=$(portable_mtime "$HANDOFF_FILE")
FILE_AGE=$(( $(date +%s) - HANDOFF_MTIME ))
if [ "$FILE_AGE" -gt 86400 ]; then
    echo '{}'
    exit 0
fi

CONTENT=$(cat "$HANDOFF_FILE")

# handoff 내용을 stderr로 출력 (사용자에게 보임)
cat >&2 << EOF
[handoff] Previous session context loaded ($(portable_fmtdate "$HANDOFF_MTIME"))
EOF

# additionalContext로 주입 (SessionStart는 hookEventName 필수)
jq -nc --arg content "$CONTENT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ("## Previous Session Context\n\nThe following handoff was saved from the previous session. Use this to understand what was being worked on. Do not repeat this information unless asked.\n\n" + $content)
  }
}'
