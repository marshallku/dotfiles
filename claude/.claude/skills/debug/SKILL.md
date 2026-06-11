---
name: debug
description: 구조화 디버깅. 사용자가 에러·버그·크래시·스택트레이스·테스트 실패를 보고하거나 "왜 안 되지", "이거 깨졌어", "예상과 다르게 동작해", "디버깅 도와줘" 같은 증상을 호소할 때 사용. SSoT(~/docs) recall → 5-Phase 근본원인 조사 → saga capture (3-strike + scope lock).
user-invocable: true
arguments: description
argument-hint: <에러 설명 또는 증상>
allowed-tools: Bash,Read,Grep,Glob,Edit,Agent
effort: high
---

## Iron Law

근본 원인 조사 없이 수정 금지.

## 5 Phases

### Phase 1: Root Cause Investigation

**먼저 SSoT(~/docs)에서 과거 사례를 본다 — 30초 투자로 1시간 절약 가능:**

- 증상에서 키워드 2-3개 추출 → `dn search <keywords>` (필요 시 `dn tag <tag>`)
- 현재 repo가 `~/docs/topics/repos/<repo>.md`로 있으면 `dn related <note>` 로 인접 자료 확인
- 우선순위 hit: `sources/debug/`, `sources/sessions/<repo-slug>/`, `topics/repos/<repo>.md`, **비슷한 다른 repo의 `topics/repos/*.md`** (사용자가 명시적으로 차용을 원함)
- hit이 있으면 Read해서 **가설 후보**로 Phase 2/3에 반영. 다른 repo에서 같은 root cause를 본 적 있으면 가설 1순위로 올림
- hit 0개거나 무관하면 즉시 다음으로. 검색에 5분 이상 쓰지 말 것

그 다음 본격 조사:

- 증상 수집 (에러 메시지, 로그, 스택 트레이스)
- 관련 코드 읽기
- `git log --oneline -20` + `git diff HEAD~3` 로 최근 변경 확인
- 재현 시도

### Phase 2: Pattern Analysis

패턴 매칭 시도:

- Race condition (동시성, 공유 상태)
- Nil/undefined 전파
- 상태 손상 (stale state)
- 캐시 부실 (cache invalidation)
- 타입 불일치
- 환경 차이 (dev vs prod)

### Phase 3: Hypothesis Testing

- 가설 형성 후 검증
- **3-Strike Rule**: 가설 3개 연속 실패 시 STOP → 사용자에게 보고
  - 지금까지 시도한 것
  - 배제된 원인
  - 추가 정보 요청
- 가설 확정 시 → Phase 4

### Phase 4: Implementation

- **Scope Lock**: 가설과 관련된 디렉토리/파일만 편집
- 근본 원인 수정 (증상 아님)
- 최소 diff
- 회귀 테스트 작성

### Phase 5: Verification

- 원래 재현 시나리오로 수정 확인
- 관련 테스트 전체 실행
- 디버그 리포트 출력:
  ```
  ## 디버그 리포트
  - 증상: ...
  - 근본 원인: ...
  - 수정: ...
  - 검증: 테스트 통과 여부
  ```

### Phase 6: Saga Capture (SSoT 영속화)

**다음 중 하나라도 해당되면** `dn save-debug-saga`로 saga를 저장한다:

- 3-strike까지 갔거나 가설 2개 이상 틀렸음
- 근본 원인이 비자명 (race / 환경 차이 / 캐시 / 타입 / 외부 라이브러리 quirk 등)
- 같은 패턴이 다른 repo에서도 일어날 법함
- 미래의 본인이 다시 만났을 때 30초 이상 단축할 가치 있음

단순 typo/null check/명백한 오타는 스킵 (노이즈).

**저장 방법** (헬퍼가 envelope·hash·repo 자동 처리):

```bash
BODY=$(mktemp)
cat > "$BODY" <<'EOF'
### 증상
...

### 가설 시도 (시간 순)
1. <가설> → <결과>
2. ...

### 근본 원인
...

### 수정
<commit hash 또는 diff 요약>

### 재발 방지
<회귀 테스트, 모니터링, 컨벤션, 비슷한 repo에 적용할 점 등>
EOF

dn save-debug-saga \
  --slug <kebab-case-슬러그> \
  --summary "<1줄: 증상 → 원인 → 수정>" \
  --tags "<repo>,<symptom-tag>,<root-cause-tag>" \
  --session-id "<현재 Claude session id>" \
  --body-file "$BODY"
```

헬퍼가 자동 처리: `captured_at`, `content_hash`, `dedupe_key`, `source_id`, `canonical_url`, git `repo` 추정, 파일명 충돌 시 `-2` suffix, sources/ immutable 보장.

**저장이 끝나면 사용자에게 헬퍼 출력의 `Saved:` 줄을 그대로 보고**.
