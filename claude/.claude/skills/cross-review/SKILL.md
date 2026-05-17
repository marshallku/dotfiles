---
name: cross-review
description: Codex를 외부 리뷰어로 사용해 현재 작업을 크로스체크. VERDICT 루프로 최대 3라운드 반복하며 유효한 피드백만 즉시 반영. 세션에 intent 파일이 있으면 code-vs-intent 비교 모드로 자동 전환.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Edit, Agent
effort: high
---

## 언제 사용하나

- 구현성 변경이 있는 작업을 **끝내기 직전** (커밋/`/ship` 전)
- 복잡하거나 보안 민감한 수정
- Claude 본인이 판단에 확신이 없을 때

작은 한 줄 수정이나 문서만 고친 작업은 스킵해도 됩니다.

## 워크플로우 (VERDICT 루프)

### Step 0: 컨텍스트 결정

리뷰어가 의도와 코드를 함께 봐야 silent scope creep / 요구사항 누락을 잡을 수 있다. 두 가지 컨텍스트 옵션이 있고 **intent 파일이 있으면 항상 그쪽이 우선**:

**옵션 A — Intent 파일 (선호)**

이번 세션의 intent-capture.sh hook이 발동했거나 사용자가 미리 intent를 작성해뒀다면, 활성 intent 파일이 다음 경로에 있다:

```bash
REPO_HASH=$(git rev-parse --show-toplevel | md5sum | head -c 12)
INTENT_MARKER="$HOME/.claude/state/intent-active-${SESSION_ID}-${REPO_HASH}.path"
if [[ -f "$INTENT_MARKER" ]]; then
    INTENT_FILE=$(cat "$INTENT_MARKER")
fi
```

이게 있으면 review가 **code-vs-intent 비교 모드**로 전환됨 — 각 acceptance_criteria 항목이 diff에서 verifiable한지 / out_of_scope를 침범하지 않았는지를 codex가 직접 검사.

**옵션 B — Inline brief (fallback)**

intent 파일이 없으면 종전대로 임시 brief 작성:

```bash
BRIEF=$(mktemp /tmp/codex-brief.XXXXXX.md)
cat > "$BRIEF" <<'EOF'
## User's request
<paraphrase, 1-2줄>

## What was done
<2-3줄, 주요 파일/함수 이름 포함>

## Key decisions
<트레이드오프, 의도적 제외, 또는 "없음">
EOF
```

원칙: 150단어 이하, 정직하게 (구현 못한 부분 / shortcut / TODO 숨기지 말 것). 대안 검토 안 했으면 "없음"으로 명시.

### Round 1

iteration 카운터를 state 파일로 추적 (escalation rule이 이 카운트에 의존):

```bash
ITER_FILE="$HOME/.claude/state/intent-iter-${SESSION_ID}-${REPO_HASH}.count"
ITER=$(cat "$ITER_FILE" 2>/dev/null || echo 0)
echo $((ITER + 1)) > "$ITER_FILE"
```

리뷰 실행:

```bash
# Intent 파일 모드
bash ~/.claude/scripts/codex-review.sh --session "$SESSION_ID" --intent-file "$INTENT_FILE"

# Inline brief fallback
bash ~/.claude/scripts/codex-review.sh --session "$SESSION_ID" --context-file "$BRIEF"

# 포커스 필요 시
bash ~/.claude/scripts/codex-review.sh --session "$SESSION_ID" --intent-file "$INTENT_FILE" --focus security
```

스크립트 exit code 처리:
- **0 (APPROVED)** → 즉시 종료, 사용자에게 리포트, iter 카운터 리셋 (`rm -f "$ITER_FILE"`)
- **1 (REVISE)** → step "분류 + Fix-First"로
- **2 (error)** → 사용자에게 원인 보고 후 중단

### 분류 + Fix-First

codex 출력의 각 CRITICAL은 `[INTENT-MISMATCH]` 또는 `[CODE-DEFECT]` 태그가 달림 (intent 파일 모드에서 강제). 처리 우선순위:

1. **[INTENT-MISMATCH]** — intent와 코드가 다름
   - acceptance_criteria 미충족 → AUTO-FIX (즉시 Edit으로 구현)
   - out_of_scope 침범 → AUTO-FIX (해당 변경 revert)
   - assumption 위반 → 판단 필요 → ASK
2. **[CODE-DEFECT]** — 실제 코드 결함
   - security/correctness 명백한 버그 → AUTO-FIX
   - 아키텍처/트레이드오프 판단 → ASK

### 억제 규칙 (무시)

- 스타일, 포맷팅, 네이밍 선호 (린터/prettier 영역)
- "추후 개선" / "consider refactoring" 류
- TODO/FIXME 코멘트
- 테스트 커버리지 부족 (별도 작업)
- import 순서

### Round 2, 3 — 반복 + escalation 룰

AUTO-FIX 적용 후 동일 명령 재실행. **같은 CRITICAL 항목이 2 라운드 연속 재등장**하면:
- Claude가 못 고치는 건이거나
- codex가 잘못 짚은 것

이때 즉시 루프 중단하고 사용자에게 **두 의견 모두 제시**해서 결정 요청.

3라운드까지 진행해도 APPROVED가 안 나오면 종료하고 사용자 escalation:

```bash
if [[ $ITER -ge 3 ]]; then
    echo "[cross-review] Reached 3-iteration cap without APPROVED — escalating to user"
    # ITER 파일은 의도적으로 안 지움 — 다음 라운드에서 user가 강제 진행 결정하면
    # codex-review.sh를 직접 호출, 이 skill을 다시 invoke하지 않는다.
    exit 1
fi
```

## Codex와 의견이 갈릴 때

- **Codex는 ground truth가 아님**. 다른 LLM이고 서로 다른 실수를 한다.
- Claude의 판단이 우선이지만, 명백히 유효한 지적은 반드시 반영한다.
- 판단이 갈리는 건은 사용자에게 둘 다 제시하고 결정을 맡긴다 — 침묵하지 말 것.

## 최종 리포트 포맷

intent 파일 모드:

```
## Codex Cross-Review (intent-aware)

Round 1: REVISE (CRITICAL x3, INFO x1)
Round 2: APPROVED

Intent: ~/docs/sources/sessions/<repo>/<date>-session-<id>.md

### Auto-fixed [INTENT-MISMATCH]
- AC1 (login retry shows toast) — 구현 추가 (path/to/file.ts:42)
- OOS#2 (don't touch SessionManager) — 변경 revert

### Auto-fixed [CODE-DEFECT]
- path/to/file.ts:99 — null check added

### Needs your decision
- [Q1] AC3 vs Assumption#2 충돌: codex는 X 권장, Claude는 Y 선호. 차이점: ...

### Informational (not fixed, recorded)
- path/to/file.ts:120 — N+1 지적이지만 호출 빈도 낮음

Final verdict: APPROVED
```

Inline brief 모드는 위와 동일하되 `Intent:` 줄 제거하고 `Context:` 줄 1줄로 대체.

## 주의 사항

- 무조건 동의하지 말 것 — 시그널 vs 노이즈 판단은 Claude의 일.
- AUTO-FIX가 3개 이상 연속 나오면 한 번 멈춰서 전체 리포트를 사용자에게 먼저 보여주는 게 안전.
- intent 파일이 있는데도 review가 "intent 무관" 발견만 쏟아낸다면 `--focus` 적용 검토.
- 작업 디렉토리가 올바른 git repo인지 먼저 확인 (codex가 diff 밖 파일까지 읽어야 정확함).

## 사용자 응답 언어 (강함)

사용자에게 보내는 리포트는 **사용자의 가장 최근 메시지 언어**와 일치. codex output을 quote할 때 file path/function name/error string은 verbatim 유지하되 산문은 번역.
