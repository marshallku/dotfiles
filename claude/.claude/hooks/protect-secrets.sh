#!/bin/bash
# PreToolUse hook: 민감 파일 편집/쓰기 차단
# Edit, Write 도구에서 .env, .secrets, credentials 등 보호

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && echo '{}' && exit 0

BASENAME=$(basename "$FILE_PATH")

case "$BASENAME" in
    .env|.env.*|.secrets|.credentials*|credentials.json|*.pem|*.key|id_rsa*|id_ed25519*)
        printf '{"permissionDecision":"deny","message":"[protect] Blocked edit of sensitive file: %s"}\n' "$BASENAME"
        exit 0
        ;;
esac

# 경로에 secrets/credentials 디렉토리 포함 시 차단
case "$FILE_PATH" in
    */.secrets/*|*/credentials/*|*/.ssh/*)
        printf '{"permissionDecision":"deny","message":"[protect] Blocked edit in sensitive directory: %s"}\n' "$FILE_PATH"
        exit 0
        ;;
esac

echo '{}'
