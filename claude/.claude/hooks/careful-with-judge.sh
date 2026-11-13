#!/usr/bin/env bash
# PreToolUse hook: 위험 명령 탐지 + 결정론적 분류기
#
# 동작 (세 가지 판정):
#   - 파괴적(루트·홈·부모·cwd 전체 삭제 등)  → deny  (복구 불가, 차단)
#   - 안전(scratch/빌드 산출물/임시 경로)     → allow (조용히 통과)
#   - 그 외 위험                              → ask   (확인 프롬프트)
# allow/deny/ask 모두 --dangerously-skip-permissions에서도 유효하다.
#
# rm 판정은 _rm_policy.py가 rm의 operand 하나하나를 실제 경로로 풀어서 한다.
# 하나라도 파괴적이면 deny, 하나라도 판단 불가·비-scratch면 ask이므로
# (rm -rf /tmp/foo / , cd /tmp && rm -rf $HOME/.ssh) 같은 다중 타겟도 막힌다.
#
# 과거에는 `claude -p --model haiku`로 LLM judge를 호출했으나, 중첩 claude는
# 인증 컨텍스트가 없어 항상 "Not logged in"을 반환 → `|| echo deny` fallback이
# 무조건 발동해 정당한 명령까지 전부 deny했다(193 deny / 0 allow). LLM 호출은
# PreToolUse마다 지연도 유발하므로, 빠르고 정직한 규칙 기반으로 대체했다.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

LOG="$HOME/.claude/hooks-debug.log"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$CMD" ] && echo '{}' && exit 0

# 공백 정규화 (force push 세그먼트 판정용)
NORM=$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')

# 결정은 반드시 hookSpecificOutput 형식(_lib.sh hook_permission). 예전의
# top-level {permissionDecision} 출력은 Claude Code가 무시해 이 훅은 2026-11-14까지
# 아무것도 막지 못했다(rm -rf / 포함).
emit() {  # $1=category $2=permissionDecision $3=message-prefix
    hook_permission "$2" "[careful] $3 $1: $(printf '%s' "$CMD" | head -c 300)"
}
logv() {  # $1=verdict $2=category
    hook_log careful-with-judge "verdict: $1 ($2): $(echo "$CMD" | head -c 60)"
    hook_event careful-with-judge verdict decision="$1" rule="$2"
}

# ── 재귀 rm 처리 ─────────────────────────────────────────────────────────────
# 판정은 _rm_policy.py가 한다: cd·변수 대입을 추적하고 bash -c / ssh / trap /
# $(...) / 셸로 들어가는 heredoc 안까지 따라가 operand를 실제 경로로 풀어 분류한다.
# (공백 split 방식은 heredoc 본문·원격 명령·find -exec까지 rm operand로 오인해
#  실제 세션 1,487건 중 deny 67·ask 1,242건이 대부분 scratch 경로 오판이었다.)
# 도우미가 실패하면 allow가 아니라 ask — 판정하지 못한 삭제는 묻는다.
case "$CMD" in
*rm*|*-delete*)  # rm, find -exec rm, find -delete
    RM_VERDICT=$(printf '%s' "$CMD" | python3 "$(dirname "$0")/_rm_policy.py" "$CWD" "$HOME" 2>/dev/null) \
        || RM_VERDICT="ask rm policy helper failed"
    [ -n "$RM_VERDICT" ] || RM_VERDICT="ask rm policy helper failed"
    case "$RM_VERDICT" in
        deny*) logv deny "rm catastrophic"; emit "rm catastrophic (${RM_VERDICT#deny })" deny "Blocked likely-catastrophic"; exit 0 ;;
        ask*)  logv ask "rm recursive"; emit "rm recursive (${RM_VERDICT#ask })" ask "Confirm"; exit 0 ;;
        allow) logv allow "rm recursive" ;;
    esac
    ;;
esac

# ── 그 외 위험 카테고리 (패턴 매칭 → 기본 ask) ──────────────────────────────
DANGEROUS=""
case "$CMD" in
    *'DROP TABLE'*|*'DROP DATABASE'*|*'TRUNCATE'*)
        DANGEROUS="sql destructive" ;;
    *'git push --force'*|*'git push -f'*)
        DANGEROUS="force push" ;;
    *'git reset --hard'*|*'git checkout .'*|*'git restore .'*)
        DANGEROUS="git discard" ;;
    *'kubectl delete'*)
        DANGEROUS="k8s delete" ;;
    *'docker system prune'*|*'docker rm -f'*)
        DANGEROUS="docker cleanup" ;;
esac

[ -z "$DANGEROUS" ] && echo '{}' && exit 0

VERDICT="ask"
case "$DANGEROUS" in
    "force push")
        # push 세그먼트 안에 plain --force/-f가 있으면 ask. lease 전용일 때만 allow.
        # (`&& echo force-with-lease` 같은 substring 회피를 막기 위해 push 세그먼트로 한정)
        if printf '%s' "$NORM" | grep -Eq 'git push[^&|;]*(--force([^-]|$)| -f( |$))'; then
            VERDICT="ask"
        elif printf '%s' "$NORM" | grep -Eq 'git push[^&|;]*force-with-lease'; then
            VERDICT="allow"
        fi ;;
    # sql destructive / git discard / k8s delete / docker cleanup → 기본 ask
esac

case "$VERDICT" in
    allow) logv allow "$DANGEROUS"; echo '{}' ;;
    *)     logv ask "$DANGEROUS"; emit "$DANGEROUS" ask "Confirm" ;;
esac
