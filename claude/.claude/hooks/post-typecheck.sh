#!/bin/bash
# PostToolUse hook: 파일 변경 후 자동 타입 체크
# Edit/Write 도구 사용 후 해당 프로젝트의 타입 체커 실행

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && echo '{}' && exit 0

# 확장자 추출
EXT="${FILE_PATH##*.}"

# 프로젝트 루트 탐색 (file_path에서 위로 올라가며 탐색)
find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        [ -f "$dir/tsconfig.json" ] || [ -f "$dir/Cargo.toml" ] || [ -f "$dir/go.mod" ] && echo "$dir" && return
        dir=$(dirname "$dir")
    done
}

PROJECT_ROOT=$(find_project_root "$(dirname "$FILE_PATH")")
[ -z "$PROJECT_ROOT" ] && echo '{}' && exit 0

case "$EXT" in
    ts|tsx)
        if [ -f "$PROJECT_ROOT/tsconfig.json" ]; then
            ERRORS=$(cd "$PROJECT_ROOT" && npx tsc --noEmit --pretty false 2>&1 | grep -c "error TS" || true)
            if [ "$ERRORS" -gt 0 ]; then
                DETAIL=$(cd "$PROJECT_ROOT" && npx tsc --noEmit --pretty false 2>&1 | grep "error TS" | head -5)
                printf '{"hookSpecificOutput":{"message":"[typecheck] %s TypeScript errors:\\n%s"}}\n' "$ERRORS" "$DETAIL"
                exit 0
            fi
        fi
        ;;
    rs)
        if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
            ERRORS=$(cd "$PROJECT_ROOT" && cargo check --message-format short 2>&1 | grep -c "^error" || true)
            if [ "$ERRORS" -gt 0 ]; then
                DETAIL=$(cd "$PROJECT_ROOT" && cargo check --message-format short 2>&1 | grep "^error" | head -5)
                printf '{"hookSpecificOutput":{"message":"[typecheck] %s Rust errors:\\n%s"}}\n' "$ERRORS" "$DETAIL"
                exit 0
            fi
        fi
        ;;
    go)
        if [ -f "$PROJECT_ROOT/go.mod" ]; then
            ERRORS=$(cd "$PROJECT_ROOT" && go vet ./... 2>&1 | grep -c ":" || true)
            if [ "$ERRORS" -gt 0 ]; then
                DETAIL=$(cd "$PROJECT_ROOT" && go vet ./... 2>&1 | head -5)
                printf '{"hookSpecificOutput":{"message":"[typecheck] %s Go errors:\\n%s"}}\n' "$ERRORS" "$DETAIL"
                exit 0
            fi
        fi
        ;;
esac

echo '{}'
