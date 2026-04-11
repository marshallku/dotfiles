---
name: cross-review
description: Codex를 외부 리뷰어로 사용해 현재 작업을 크로스체크. VERDICT 루프로 최대 3라운드 반복하며 유효한 피드백만 즉시 반영.
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

### Step 0: 작업 맥락 brief 작성 (필수)

Codex에게 diff만 던지면 "좋은 코드인지"는 판단해도 "사용자가 원한 걸 제대로 했는지"는 모른다. 작업 맥락을 짧게 요약해서 함께 전달해야 intent-vs-implementation 불일치(silent scope creep, 요구사항 누락 등)를 잡을 수 있다.

Claude 본인의 working memory에 있는 정보로 임시 파일에 brief 작성:

```bash
BRIEF=$(mktemp /tmp/codex-brief.XXXXXX.md)
cat > "$BRIEF" <<'EOF'
## User's request
<사용자가 원한 것, 1-2줄, 원문 그대로가 아니라 paraphrase>

## What was done
<실제로 구현한 것, 2-3줄. 주요 파일/함수 이름 포함>

## Key decisions
<의미있는 트레이드오프, 대안을 고려했다가 버린 이유, 범위에서 의도적으로 제외한 것. 없으면 "없음">
EOF
```

**원칙**:
- 전체 150단어 이하. 장황하면 codex가 신호를 못 찾음.
- 정직하게 써라. 구현 못한 부분/shortcut/TODO를 숨기면 codex가 잡을 기회를 뺏는 것.
- 대안을 검토하지 않았으면 "Key decisions: 없음"이라고 쓰라. 억지로 만들지 말 것.

### Round 1

1. 변경 범위 판단:
   - 커밋 전 상태 (uncommitted) → `bash ~/.claude/scripts/codex-review.sh --uncommitted --context-file "$BRIEF"`
   - 피쳐 브랜치 → `bash ~/.claude/scripts/codex-review.sh --context-file "$BRIEF"` (또는 `--base <branch>`)
   - 포커스 필요 → `--focus security` / `--focus performance` 추가
2. 스크립트 실행 후 exit code + 출력 확인:
   - exit 0 (APPROVED) → **즉시 종료**, 사용자에게 리포트
   - exit 1 (REVISE) → step 3
   - exit 2 (error) → 사용자에게 원인 보고 후 중단
3. 출력에서 CRITICAL / INFORMATIONAL 파싱. 특히 `[INTENT-MISMATCH]` 태그가 붙은 CRITICAL은 최우선.

### Fix-First 분류 (기존 `/review`와 동일)

각 finding을 둘 중 하나로 분류:

- **AUTO-FIX**: 시니어 엔지니어가 즉시 승인할 **기계적 수정** → 지금 바로 Edit으로 고친다
- **ASK**: 아키텍처/트레이드오프 판단이 필요 → 라운드 끝에 사용자에게 일괄 질문

### 억제 규칙 (무시)

codex가 다음을 지적하면 로그만 남기고 스킵:

- 스타일, 포맷팅, 네이밍 선호
- 이미 린터/prettier가 잡는 것
- "추후 개선" 류 추천
- TODO/FIXME 코멘트
- 테스트 커버리지 부족 (별도 작업)
- import 순서

### Round 2, 3

AUTO-FIX 항목을 반영한 뒤 스크립트 재실행. APPROVED가 나오거나 3라운드를 소진하면 루프 종료.

**같은 CRITICAL이 2라운드 연속 재등장**하면 Claude가 고치지 못하는 건이거나 codex가 잘못 짚은 것. 사용자에게 직접 판단을 요청한다.

## Codex와 의견이 갈릴 때

- **Codex는 ground truth가 아님**. 또 다른 LLM일 뿐이고 서로 다른 실수를 한다.
- Claude의 판단이 우선이지만, 명백히 유효한 지적은 반드시 반영한다.
- 판단이 갈리는 건은 사용자에게 둘의 의견을 모두 제시하고 결정을 맡긴다.

## 최종 리포트 포맷

```
## Codex Cross-Review

Round 1: REVISE (CRITICAL x2, INFO x1)
Round 2: APPROVED

### Auto-fixed
- path/to/file.ts:42 — null check added before dereference
- path/to/file.ts:99 — magic number extracted to constant

### Needs your decision
- [Q1] path/to/file.ts:55 — codex wants X, Claude thinks Y. 질문 요약

### Informational (not fixed, recorded)
- path/to/file.ts:120 — codex는 N+1을 지적했지만 실제 호출 빈도가 낮아 보류

Final verdict: APPROVED
```

## 주의 사항

- 루프 중 codex 피드백에 무조건 동의하지 말 것
- **AUTO-FIX**라고 판단한 건도 3개 이상 연속 나오면 한 번 멈춰서 사용자에게 전체 리포트 먼저 보여주는 게 안전
- Codex가 diff 밖 파일까지 읽어야 정확한 리뷰가 되므로, 작업 디렉토리가 올바른 git repo인지 먼저 확인
