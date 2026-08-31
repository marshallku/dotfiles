#!/usr/bin/env bash
# SessionStart hook: 이전 세션 handoff 자동 로드
# auto-handoff.sh가 저장한 latest.md를 읽어서 시스템 프롬프트에 주입

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat 2>/dev/null || echo '{}')
SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || echo "")
SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# 부수 작업: 1일 이상 된 ephemeral 세션 마커 청소.
# reviewed-* 는 reviewed_marker_valid 의 TTL(기본 24h)로 이미 무효화되므로
# 여기서 지워도 의미 변화 없음(디스크 정리). codex-delegate-pending-* 는 하루
# 넘게 지속되는 세션의 live enforcement 상태일 수 있어 제외한다.
STATE_DIR="$HOME/.claude/state"
if [ -d "$STATE_DIR" ]; then
    find "$STATE_DIR" -maxdepth 1 -type f \( \
        -name "dirty-*.log" -o -name "stop-blocked-*" -o -name "verify-blocked-*" \
        -o -name "ssot-checked-*" -o -name "reviewed-*" -o -name "compact-reinject-*" \
        \) -mtime +1 -delete 2>/dev/null || true

    # intent-active-* 는 원래 live enforcement 상태라 나이 기준 삭제에서
    # 빼 두었는데, intent-capture 훅이 2026-06-30 에 비활성화되면서 아무도
    # 새로 만들지 않고 아무도 읽지 않는 잔해가 되었다 (2026-08-31 기준 49개,
    # 최신 것이 6월). 하루가 아니라 7일 창을 쓰는 이유는 훅을 다시 켰을 때
    # 장기 세션의 진짜 마커를 지우지 않기 위해서다.
    find "$STATE_DIR" -maxdepth 1 -type f -name "intent-active-*" \
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

HANDOFF_FILE="$HOME/.claude/handoffs/latest.md"

# handoff 파일이 없으면 스킵
if [ ! -f "$HANDOFF_FILE" ]; then
    echo '{}'
    exit 0
fi

# 24시간 이상 지난 handoff는 무시
HANDOFF_MTIME=$(portable_mtime "$HANDOFF_FILE")
FILE_AGE=$(( $(date +%s) - HANDOFF_MTIME ))
if [ "$FILE_AGE" -gt 86400 ]; then
    echo '{}'
    exit 0
fi

CONTENT=$(cat "$HANDOFF_FILE")

# handoff 내용을 stderr로 출력 (사용자에게 보임)
cat >&2 << EOF
[handoff] Previous session context loaded ($(portable_fmtdate "$HANDOFF_MTIME"))
EOF

# additionalContext로 주입 (SessionStart는 hookEventName 필수)
jq -nc --arg content "$CONTENT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ("## Previous Session Context\n\nThe following handoff was saved from the previous session. Use this to understand what was being worked on. Do not repeat this information unless asked.\n\n" + $content)
  }
}'
