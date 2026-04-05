#!/bin/bash
# PreToolUse hook: freeze 디렉토리 외 편집 차단
# 야간 에이전트 편집 범위 제한용

INPUT=$(cat)
FREEZE_FILE="$HOME/.claude/freeze-dir.txt"

# freeze 설정이 없으면 즉시 통과
[ ! -f "$FREEZE_FILE" ] && echo '{}' && exit 0

FREEZE_DIR=$(cat "$FREEZE_FILE")
[ -z "$FREEZE_DIR" ] && echo '{}' && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && echo '{}' && exit 0

# 경로 정규화
REAL_FILE=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# trailing / 보장하여 /src ↔ /src-old 오매칭 방지
case "$FREEZE_DIR" in
    */) ;;
    *) FREEZE_DIR="$FREEZE_DIR/" ;;
esac

# freeze 디렉토리 하위인지 검사
case "$REAL_FILE/" in
    "$FREEZE_DIR"*)
        echo '{}'
        ;;
    *)
        printf '{"permissionDecision":"deny","message":"[freeze] Blocked edit outside frozen directory: %s (allowed: %s)"}\n' "$REAL_FILE" "$FREEZE_DIR"
        ;;
esac
