#!/usr/bin/env bash
# PreToolUse hook: 민감 파일 편집/쓰기 차단
# Edit, Write 도구에서 .env, .secrets, credentials 등 보호

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && echo '{}' && exit 0

BASENAME=$(basename "$FILE_PATH")

case "$BASENAME" in
    # Committed templates hold no secrets; blocking them only made agents route around the hook.
    .env.example|.env.sample|.env.template|.env.*.example) echo '{}'; exit 0 ;;
esac

case "$BASENAME" in
    .env|.env.*|.secrets|.credentials*|credentials.json|*.pem|*.key|id_rsa*|id_ed25519*)
        hook_permission deny "[protect] Blocked edit of sensitive file: $BASENAME"
        exit 0
        ;;
esac

# 경로에 secrets/credentials 디렉토리 포함 시 차단
case "$FILE_PATH" in
    */.secrets/*|*/credentials/*|*/.ssh/*)
        hook_permission deny "[protect] Blocked edit in sensitive directory: $FILE_PATH"
        exit 0
        ;;
esac

echo '{}'
