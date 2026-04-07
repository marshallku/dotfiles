---
name: debug
description: 5-Phase 구조화 디버깅 (3-strike + scope lock)
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
