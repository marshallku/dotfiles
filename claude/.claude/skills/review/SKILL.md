---
name: review
description: PR 사전 리뷰 (Fix-First 패턴)
user-invocable: true
allowed-tools: Bash,Read,Grep,Glob,Edit,Agent
---

## 워크플로우

1. `git diff main...HEAD` (또는 적절한 base branch) 읽기
2. **CRITICAL pass** 먼저:
   - SQL injection, 미검증 입력
   - Race condition, 공유 상태 동시성
   - Shell injection, 명령어 조합
   - LLM 신뢰 경계 (외부 입력을 신뢰하는지)
   - Enum/switch 완전성 (diff 밖 코드까지 확인)
   - 타입 안전성 (any, as 남용)
3. **INFORMATIONAL pass**:
   - async/sync 혼용
   - 에러 처리 누락
   - 성능 이슈 (불필요한 리렌더, N+1 쿼리)
4. 각 발견 사항을 분류:
   - **AUTO-FIX**: 시니어 엔지니어가 즉시 승인할 기계적 수정 → 즉시 수정 + atomic 커밋
   - **ASK**: 판단 필요 (아키텍처, 트레이드오프) → 단일 질문으로 번호 매겨서 일괄 제시
5. diff 밖 코드도 반드시 확인 (enum 완전성, 인터페이스 호환성)

## 억제 규칙 (리포트하지 않을 것)

- 스타일/포맷팅 (prettier, eslint가 처리)
- 이미 CI에서 잡는 것 (린트, 타입 체크)
- 주관적 네이밍 선호
- "추후 개선" 제안
- TODO/FIXME 코멘트
- 테스트 커버리지 부족 (별도 작업)
- import 순서

## 출력 형식

```
## CRITICAL
- [C1] (파일:줄) 설명 → AUTO-FIX / ASK

## INFORMATIONAL
- [I1] (파일:줄) 설명 → AUTO-FIX / ASK
```

AUTO-FIX 항목은 즉시 수정하고 커밋. ASK 항목은 마지막에 한번에 질문.
