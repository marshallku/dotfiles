#!/usr/bin/env bash
# @hook-event: SessionStart
# SessionStart hook: state GC, ledger/log rotation, and post-compaction re-injection.
# The previous-session handoff is no longer injected: it repeated the gitStatus Claude
# Code already provides (672 injections × ~1.4 KB in 30 days). auto-handoff.sh still
# writes it for /catchup.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat 2>/dev/null || echo '{}')
SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || echo "")
SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# 부수 작업: 1일 이상 된 ephemeral 세션 마커 청소.
# 승인·delegate 마커는 긴 세션에서도 필요하므로 나이 기준 삭제에서 제외한다.
STATE_DIR="$HOME/.claude/state"

if [ -d "$STATE_DIR" ]; then
    find "$STATE_DIR" -maxdepth 1 -type f \( \
        -name "dirty-*.log" -o -name "dirty-*.log.resolved" -o -name "stop-blocked-*" -o -name "verify-blocked-*" \
        -o -name "ssot-checked-*" -o -name "compact-reinject-*" -o -name "bash-mark-*" \
        -o -name "review-reminded-*" -o -name "review-stop-*" \
        \) -mtime +1 -delete 2>/dev/null || true

    # codex-exec.sh keeps each run's event stream and status for codex-tail / a live view.
    # A week is enough to look back at a review; older runs are only disk.
    if [ -d "$STATE_DIR/codex-live" ]; then
        find "$STATE_DIR/codex-live" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
    fi

    # intent-active-* 는 원래 live enforcement 상태라 나이 기준 삭제에서
    # 빼 두었는데, intent-capture 훅이 2026-06-30 에 비활성화되면서 아무도
    # 새로 만들지 않고 아무도 읽지 않는 잔해가 되었다 (2026-08-31 기준 49개,
    # 최신 것이 6월). 하루가 아니라 7일 창을 쓰는 이유는 훅을 다시 켰을 때
    # 장기 세션의 진짜 마커를 지우지 않기 위해서다.
    find "$STATE_DIR" -maxdepth 1 -type f -name "intent-active-*" \
        -mtime +7 -delete 2>/dev/null || true

    # 승인은 스테이징된 tree마다 하나씩 쌓인다 (reviewed-<repo>-<tree>).
    # 커밋되면 쓸모없어지므로 7일 지난 것은 지운다. 미커밋 승인이 지워져도 재리뷰면 된다.
    find "$STATE_DIR" -maxdepth 1 -type f -name "reviewed-*" \
        -mtime +7 -delete 2>/dev/null || true
fi

# 부수 작업: 관측 원장 로테이션. hooks-debug.log 와 같은 이유로 무한 증가하고,
# 이쪽은 append-only JSONL 이라 더 빨리 큰다. 한 세대만 보관.
for LEDGER in "$STATE_DIR/hook-events.jsonl" "$STATE_DIR/codex-usage.jsonl"; do
    [ -f "$LEDGER" ] || continue
    LSIZE=$(stat -c%s "$LEDGER" 2>/dev/null || stat -f%z "$LEDGER" 2>/dev/null || echo 0)
    if [ "${LSIZE:-0}" -gt "${HARNESS_LEDGER_MAX_BYTES:-10485760}" ]; then
        mv -f "$LEDGER" "$LEDGER.1" 2>/dev/null || true
    fi
done

# 부수 작업: hooks-debug.log 로테이션 (모든 훅이 append 하는 단일 로그라 무한 증가).
# 5MB 초과 시 .1 로 한 세대만 회전. best-effort — 실패해도 세션 시작을 막지 않는다.
LOG_FILE="$HOME/.claude/hooks-debug.log"
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "${LOG_SIZE:-0}" -gt 5242880 ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
    fi
fi

# compaction 직후(SessionStart source=compact) pre-compact.sh 가 남긴 재주입
# 스냅샷이 있으면 그걸 우선 주입한다. 삭제하지 않고 GC에 맡겨 crash-safe 유지.
REINJECT="$STATE_DIR/compact-reinject-${SESSION}.md"
if [ "$SOURCE" = "compact" ] && [ -n "$SESSION" ] && [ -f "$REINJECT" ]; then
    RE_MTIME=$(portable_mtime "$REINJECT")
    RE_AGE=$(( $(date +%s) - RE_MTIME ))
    if [ "$RE_AGE" -ge 0 ] && [ "$RE_AGE" -le 86400 ]; then
        RCONTENT=$(cat "$REINJECT")
        echo "[compact] Re-injected preserved context after compaction" >&2
        jq -nc --arg content "$RCONTENT" '{
          "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": $content
          }
        }'
        exit 0
    fi
fi

echo '{}'
