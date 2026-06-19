#!/usr/bin/env bash
# PreToolUse hook: 위험 명령 탐지 + 결정론적 분류기
#
# 동작 (세 가지 판정):
#   - 파괴적(루트·홈·부모·cwd 전체 삭제 등)  → deny  (복구 불가, 차단)
#   - 안전(scratch/빌드 산출물/임시 경로)     → allow (조용히 통과)
#   - 그 외 위험                              → ask   (확인 프롬프트)
# allow/deny/ask 모두 --dangerously-skip-permissions에서도 유효하다.
#
# rm 판정은 명령 전체 substring이 아니라 "모든 인자 토큰"을 검사한다. rm은
# 인자를 여러 개 받고 파괴적/실제 대상이 어느 위치에든 섞일 수 있으므로
# (rm -rf /tmp/foo / , rm -rf build / , cd /tmp && rm -rf $HOME/.ssh),
# 토큰 단위 검사만이 다중 타겟 우회를 막는다.
#
# 과거에는 `claude -p --model haiku`로 LLM judge를 호출했으나, 중첩 claude는
# 인증 컨텍스트가 없어 항상 "Not logged in"을 반환 → `|| echo deny` fallback이
# 무조건 발동해 정당한 명령까지 전부 deny했다(193 deny / 0 allow). LLM 호출은
# PreToolUse마다 지연도 유발하므로, 빠르고 정직한 규칙 기반으로 대체했다.

set -euo pipefail

LOG="$HOME/.claude/hooks-debug.log"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && echo '{}' && exit 0

# 공백 정규화 + 토큰 판정용 정규화(인용부호·백슬래시·`--` argv 구분자 제거)
#   (rm -rf "$HOME" , \rm -rf / , rm -rf -- / 같은 회피를 정규화)
NORM=$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')
STRIPPED=$(printf '%s' "$NORM" | sed -e "s/[\"']//g" -e 's/\\//g' -e 's/ -- / /g')

# CMD에 따옴표/제어문자가 있어도 안전하도록 JSON은 jq로 생성한다
emit() {  # $1=category $2=permissionDecision $3=message-prefix
    jq -cn --arg cmd "$CMD" --arg cat "$1" --arg dec "$2" --arg pre "$3" \
        '{permissionDecision:$dec, message:("[careful] " + $pre + " " + $cat + ": " + $cmd)}'
}
logv() {  # $1=verdict $2=category
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] careful verdict: $1 ($2): $(echo "$CMD" | head -c 60)" >> "$LOG"
}

# ── 재귀 rm 처리 (상태기계: rm 자신의 operand만 분류) ─────────────────────────
# 명령 전체 토큰을 무차별 스캔하면 `find . -exec rm -rf {}`의 `.`나
# `ls * && rm ...`의 `*` 같은 "다른 명령의 인자"를 rm 타겟으로 오인한다.
# 그래서 rm 토큰을 만난 뒤 그 rm의 플래그/operand만 추적한다. 재귀 여부도
# rm 자신의 플래그 클러스터(-r/-R/-rf/-Rf, 분리된 -f -r, --recursive)에서만 본다.
case " $STRIPPED " in
*' rm '*|*'/rm '*)   # bare rm 또는 /bin/rm·/usr/bin/rm 등 경로 호출
    SCRATCH_CWD=0  # cwd가 scratch로 옮겨졌는지: 상대경로 타겟을 안전 취급할 근거
    printf '%s' "$STRIPPED" | grep -Eq 'cd +/(tmp|var/tmp|dev/shm)' && SCRATCH_CWD=1

    SCRATCH_RE='^(/tmp(/|$)|/var/tmp/|/dev/shm/)|(^|/)target(/|$)|(^|/)\.claude/state|\.(count|log|tmp)$'
    ARTIFACT_RE='(^|/)(node_modules|dist|build|\.next|coverage|__pycache__|\.cache|\.turbo)(/|$)'

    CATASTROPHIC=0; UNSAFE=0; SAFE=0; ENGAGED=0
    STATE=idle; REC=0

    set -f  # glob 확장 차단
    for t in $STRIPPED; do
        if [ "$STATE" = idle ]; then
            case "$t" in rm|*/rm) STATE=rmflags; REC=0 ;; esac
            continue
        fi
        if [ "$STATE" = rmflags ]; then
            case "$t" in
                --recursive) REC=1; continue ;;
                --*) continue ;;                              # 기타 long 플래그
                -*[rR]*) REC=1; continue ;;                   # r/R 포함 short 클러스터(-r,-R,-rf,-fr)
                -*) continue ;;                               # 기타 short 플래그(-f 등)
                '&&'|'||'|';'|'|'|'&') STATE=idle; continue ;; # operand 없이 segment 종료
                *) STATE=rmargs ;;                            # 첫 operand → 아래에서 분류
            esac
        elif [ "$STATE" = rmargs ]; then
            case "$t" in
                '&&'|'||'|';'|'|'|'&') STATE=idle; continue ;; # 이 rm 종료
                -*) continue ;;                                # 뒤따르는 플래그 무시
            esac
        fi
        # 여기 도달 = rm의 operand. 재귀 rm일 때만 분류(비재귀 rm은 디렉터리 삭제 불가)
        [ "$REC" = 1 ] || continue
        ENGAGED=1
        case "$t" in
            # 파괴적 대상: 루트/홈전체/부모/cwd전체/와일드카드 → deny
            /|/\*|'~'|'~/'|'~/*'|'$HOME'|'${HOME}'|'$HOME/'|'$HOME/*'|'${HOME}/'|'${HOME}/*'|.|./|..|../|'*')
                CATASTROPHIC=1; break ;;
        esac
        if printf '%s' "$t" | grep -Eq "$SCRATCH_RE"; then SAFE=1
        elif printf '%s' "$t" | grep -Eq "$ARTIFACT_RE"; then SAFE=1
        else
            case "$t" in
                '~'*|'$HOME'*|'${HOME}'*) UNSAFE=1 ;;  # 홈 경로
                /*) UNSAFE=1 ;;                         # 그 외 절대경로
                *) [ "$SCRATCH_CWD" = 1 ] && SAFE=1 || UNSAFE=1 ;;  # 상대경로: scratch cwd에서만 안전
            esac
        fi
    done
    set +f
    [ "$STATE" = rmflags ] && [ "$REC" = 1 ] && ENGAGED=1  # `rm -rf` (operand 없음)도 처리

    if [ "$ENGAGED" = 1 ]; then
        if [ "$CATASTROPHIC" = 1 ]; then
            logv deny "rm catastrophic"; emit "rm catastrophic" deny "Blocked likely-catastrophic"; exit 0
        fi
        if [ "$UNSAFE" = 0 ] && [ "$SAFE" = 1 ]; then
            logv allow "rm recursive"; echo '{}'; exit 0
        fi
        logv ask "rm recursive"; emit "rm recursive" ask "Confirm"; exit 0
    fi
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
