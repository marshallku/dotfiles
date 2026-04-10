#!/bin/bash
# PreToolUse hook: 위험 명령 탐지 + LLM-as-judge
# deny는 --dangerously-skip-permissions에서도 유효

LOG="$HOME/.claude/hooks-debug.log"
INPUT=$(cat)
echo "[$(date +%H:%M:%S)] careful triggered: $(echo "$INPUT" | jq -r '.tool_input.command // empty' | head -c 80)" >> "$LOG"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && echo '{}' && exit 0

# 1단계: 위험 패턴 매칭 (비위험 명령은 즉시 통과)
DANGEROUS=""
case "$CMD" in
    *'rm -rf'*|*'rm -r'*)
        case "$CMD" in
            *node_modules*|*.next*|*dist*|*build*|*coverage*|*__pycache__*|*.cache*|*.turbo*) ;;
            *) DANGEROUS="rm recursive" ;;
        esac ;;
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

# 2단계: LLM judge (위험 패턴일 때만 호출)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
TASK_CTX=""
[ -f "$TRANSCRIPT" ] && TASK_CTX=$(tail -c 2000 "$TRANSCRIPT" | head -c 1000)

JUDGMENT=$(claude -p --bare --model haiku "Respond ONLY 'allow' or 'deny'.
Pattern: $DANGEROUS
Command: $CMD
Context: $TASK_CTX
Rules: allow if contextually necessary (disk cleanup, build artifacts, feature branch). deny if targets production data, main branch, or unclear context." 2>/dev/null || echo "deny")

case "$JUDGMENT" in
    *allow*) echo '{}' ;;
    *) printf '{"permissionDecision":"deny","message":"[careful] Blocked %s: %s"}\n' "$DANGEROUS" "$CMD" ;;
esac
