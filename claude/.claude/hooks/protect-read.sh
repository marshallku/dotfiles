#!/usr/bin/env bash
# @hook-event: PreToolUse
# PreToolUse hook: agent-deny-paths 안의 경로를 읽기·목록·검색하지 못하게 한다.
#
# 목록: ~/.claude/agent-deny-paths (git 밖, 선택). 한 줄에 `~/…` 또는 `/abs`, `*`·`?`·`**` glob.
# 목록이 git 밖이라 settings.json `Read(...)` 규칙으로 옮길 수 없고(그 규칙은 상위에서 도는
# `grep -r`도 못 막는다), 이 훅이 유일한 층이다.
# 판정은 _read_policy.py가 한다: 상대경로·cd·glob·`--opt=path`·`bash -c`까지 풀어서
# 보호 경로에 닿으면 deny, 상위에서 재귀로 도는 명령은 보호 디렉터리를 제외하지 않으면 deny.
# 도우미가 실패하면 deny — 판정 못 한 읽기를 통과시키지 않는다.
# `$VAR`로 만든 경로나 스크립트 안에서 트리를 도는 것은 못 본다(최선 노력). codex는 막지 못한다.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL=""
# 목록은 git에 넣지 않는다(무엇을 숨겼는지도 비공개). 없거나 비어 있으면 아무것도 막지 않는다.
DENY_LIST="$HOME/.claude/agent-deny-paths"
HELPER_FAILED="read policy helper (_read_policy.py) failed; repair ~/.claude/hooks"

if ! grep -qv '^[[:space:]]*\(#\|$\)' "$DENY_LIST" 2>/dev/null; then
    hook_event protect-read decision decision=allow tool="$TOOL" list=empty
    echo '{}'
    exit 0
fi

VERDICT=$(printf '%s' "$INPUT" | python3 "$(dirname "$0")/_read_policy.py" "$DENY_LIST" "$HOME" 2>/dev/null) \
    || VERDICT="deny $HELPER_FAILED"
[ -n "$VERDICT" ] || VERDICT="deny $HELPER_FAILED"

case "$VERDICT" in
    deny*)
        REASON="${VERDICT#deny }"
        hook_log protect-read "deny tool=$TOOL $REASON"
        hook_event protect-read decision decision=deny tool="$TOOL" reason="$REASON"
        hook_permission deny "[protect-read] Blocked: $REASON. These paths are off-limits to agents (hooks/agent-deny-paths); do not try another way to read them."
        ;;
    *)
        hook_event protect-read decision decision=allow tool="$TOOL"
        echo '{}'
        ;;
esac
