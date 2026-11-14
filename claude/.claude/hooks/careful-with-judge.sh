#!/usr/bin/env bash
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
# 왜 ask가 없나: ask는 사람이 답할 때까지 세션을 멈춘다. 이 하네스는 긴 자율
# 루프(/goal, /loop, 리드+서브에이전트)로 돌기 때문에, rm 명령의 약 20%에서
# 루프가 서 버리는 정책은 막는 것보다 비용이 크다. 애매한 것까지 deny하면
# 에이전트가 훅이 못 보는 경로(python shutil.rmtree 등)로 돌아가므로 그것도 아니다.
#
# rm 판정은 _rm_policy.py가 rm의 operand 하나하나를 실제 경로로 풀어서 한다
# (그쪽 출력의 `ask`는 이 훅에서 flagged가 된다). 하나라도 파괴적이면 deny이므로
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

# 결정은 반드시 hookSpecificOutput 형식(_lib.sh hook_permission). 예전의
# top-level {permissionDecision} 출력은 Claude Code가 무시해 이 훅은 2026-11-14까지
# 아무것도 막지 못했다(rm -rf / 포함).
emit() {  # $1=category $2=permissionDecision $3=message-prefix
    hook_permission "$2" "[careful] $3 $1: $(printf '%s' "$CMD" | head -c 300)"
}
logv() {  # $1=verdict $2=category [$3=detail]
    hook_log careful-with-judge "verdict: $1 ($2${3:+: $3}): $(echo "$CMD" | head -c 60)"
    hook_event careful-with-judge verdict decision="$1" rule="$2" detail="${3:-}" \
        cmd="$(printf '%s' "$CMD" | head -c 200)"
}

# ── 재귀 rm 처리 ─────────────────────────────────────────────────────────────
# 판정은 _rm_policy.py가 한다: cd·변수 대입을 추적하고 bash -c / ssh / trap /
# $(...) / 셸로 들어가는 heredoc 안까지 따라가 operand를 실제 경로로 풀어 분류한다.
# (공백 split 방식은 heredoc 본문·원격 명령·find -exec까지 rm operand로 오인해
#  실제 세션 1,487건 중 deny 67·ask 1,242건이 대부분 scratch 경로 오판이었다.)
# 도우미가 실패하면 deny — 판정하지 못한 삭제를 조용히 통과시키지 않는다(설치 고장은
# tripwire가 잡는다).
# 같은 워커가 lease 없는 force push(`--force`, `-f`, `+ref`)도 판정한다. 문자열 매칭은
# 커밋 메시지·프롬프트·heredoc 안의 "git push --force"까지 막았다.
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

# ── 그 외 위험 카테고리 (패턴 매칭 → flagged: 통과 + 기록) ──────────────────
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
