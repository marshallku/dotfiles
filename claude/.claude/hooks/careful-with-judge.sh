#!/usr/bin/env bash
# @hook-event: PreToolUse
# PreToolUse hook: 위험 명령 탐지 + 결정론적 분류기
#
# 동작 (ask는 쓰지 않는다):
#   - deny    : 되돌릴 수 없고 에이전트에게 대안이 있는 것
#               (루트·홈·시스템 디렉터리·cwd 통째 삭제, lease 없는 force push).
#               이유를 읽은 에이전트가 다른 방법으로 계속 진행한다.
#   - flagged : 그 외 위험해 보이는 명령. 통과시키고 ledger에 남긴다
#               (harness-report의 "Flagged" 절에서 사후 확인).
#   - 안전(scratch/빌드 산출물/임시 경로)은 조용히 통과.
#
# ask가 없는 이유: 사람이 답할 때까지 긴 자율 루프가 멈춘다. 애매한 것까지 deny하면
# 에이전트가 훅이 못 보는 경로(python shutil.rmtree 등)로 돌아간다.
#
# rm 판정은 _rm_policy.py가 operand 하나하나를 실제 경로로 풀어서 한다(그쪽의 `ask`는
# 여기서 flagged). 하나라도 파괴적이면 deny라 `rm -rf /tmp/foo /` 같은 다중 타겟도 막힌다.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

LOG="$HOME/.claude/hooks-debug.log"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$CMD" ] && echo '{}' && exit 0

# 결정은 반드시 hookSpecificOutput 형식(_lib.sh hook_permission): top-level
# {permissionDecision}은 Claude Code가 무시하고 명령을 실행한다.
emit() {
    hook_permission "$2" "[careful] $3 $1: $(printf '%s' "$CMD" | head -c 300)"
}
logv() {
    hook_log careful-with-judge "verdict: $1 ($2${3:+: $3}): $(echo "$CMD" | head -c 60)"
    hook_event careful-with-judge verdict decision="$1" rule="$2" detail="${3:-}" \
        cmd="$(printf '%s' "$CMD" | head -c 200)"
}

# _rm_policy.py는 lease 없는 force push(`--force`, `-f`, `+ref`)도 판정한다: 문자열 매칭은
# 커밋 메시지·heredoc 안의 "git push --force"까지 막는다.
# 도우미가 실패하면 deny — 판정하지 못한 삭제를 조용히 통과시키지 않는다(설치 고장은
# tripwire가 잡는다).
RM_HELPER_FAILED="deny rm/push policy helper (_rm_policy.py) failed; repair ~/.claude/hooks"
case "$CMD" in
*rm*|*-delete*|*push*)  # rm, find -exec rm, find -delete, git push
    RM_VERDICT=$(printf '%s' "$CMD" | python3 "$(dirname "$0")/_rm_policy.py" "$CWD" "$HOME" 2>/dev/null) \
        || RM_VERDICT="$RM_HELPER_FAILED"
    [ -n "$RM_VERDICT" ] || RM_VERDICT="$RM_HELPER_FAILED"
    case "$RM_VERDICT" in
        deny*)
            DETAIL="${RM_VERDICT#deny }"
            case "$DETAIL" in *"force push"*) RULE="force push" ;; *) RULE="rm catastrophic" ;; esac
            logv deny "$RULE" "$DETAIL"
            emit "$RULE ($DETAIL)" deny "Blocked irreversible change -"
            exit 0 ;;
        ask*)  logv flagged "rm recursive" "${RM_VERDICT#ask }" ;;
        allow) logv allow "rm recursive" ;;
    esac
    ;;
esac

DANGEROUS=""
case "$CMD" in
    *'DROP TABLE'*|*'DROP DATABASE'*|*'TRUNCATE'*)
        DANGEROUS="sql destructive" ;;
    *'git reset --hard'*|*'git checkout .'*|*'git restore .'*)
        DANGEROUS="git discard" ;;
    *'kubectl delete'*)
        DANGEROUS="k8s delete" ;;
    *'docker system prune'*|*'docker rm -f'*)
        DANGEROUS="docker cleanup" ;;
esac

[ -z "$DANGEROUS" ] && echo '{}' && exit 0
logv flagged "$DANGEROUS"
echo '{}'
