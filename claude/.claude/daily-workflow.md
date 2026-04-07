# Claude Code Daily Workflow

실제 하루 작업 흐름에 hooks, skills, agents를 자연스럽게 녹이는 가이드.

---

## 세션 시작

별도 행동 불필요. **SessionStart hook**이 자동으로:

- 이전 세션의 handoff(`~/.claude/handoffs/latest.md`)를 읽어 system prompt에 주입
- 24시간 이상 지난 handoff는 무시
- 어제 작업 흐름이 자동으로 이어짐

수동으로 더 상세한 맥락이 필요하면:

```
claude --resume          # 이전 세션 자체를 이어서
```

---

## 코딩 중 (자동으로 동작하는 것들)

코드를 작성하는 동안 의식할 필요 없이 작동:

| Hook | 동작 | 트리거 |
|------|------|--------|
| **post-typecheck** | `tsc --noEmit` / `cargo check` / `go vet` 자동 실행 | 파일 편집 후 |
| **careful-with-judge** | `rm -rf`, `git push --force` 등 위험 명령 감지 → LLM 판단 | Bash 실행 전 |
| **protect-secrets** | `.env`, `*.key` 등 민감 파일 편집 차단 | 파일 편집 전 |

타입 에러가 나면 Claude가 즉시 알고 수정을 제안한다.

---

## 버그 수정

```
/debug 로그인 후 리다이렉트가 무한 루프에 빠짐
```

5-Phase 프로세스가 자동 적용:
1. 로그, 스택 트레이스, 최근 git 변경 수집
2. 패턴 매칭 (race condition, stale state 등)
3. 가설 검증 — **3번 연속 실패 시 자동 중단 + 보고**
4. 최소 diff로 근본 원인 수정
5. 테스트 실행 + 디버그 리포트

---

## 코드 리뷰

### 셀프 리뷰 (커밋 전)

```
/review
```

- main 대비 diff를 CRITICAL → INFORMATIONAL 순으로 분석
- SQL injection, race condition 등 보안 이슈 우선
- 기계적 수정(AUTO-FIX)은 즉시 적용, 판단 필요한 건 질문으로 제시
- 스타일, 린트, 네이밍 같은 잡음은 자동 억제

### 팀원에게 리뷰 맡기기

```
@code-reviewer     # 일반 리뷰 (worktree 격리)
@security-reviewer # 보안 전용 (OWASP 포커스, 읽기 전용)
```

에이전트는 별도 worktree에서 독립 실행. 메인 작업을 방해하지 않음.

---

## 프론트엔드 검증

```
/verify http://localhost:3000/dashboard
```

브라우저 스크린샷을 찍고 비전으로 직접 분석:
- 레이아웃 깨짐, 텍스트 겹침, 빈 영역 체크
- 콘솔 에러 확인
- 요청 시 반응형 검증 (375/768/1440px)
- 레퍼런스 이미지가 있으면 diff 비교

**전제:** 브라우저에 browser-control 익스텐션 설치 + 브라우저 열려있어야 함.

---

## 커밋 + PR

```
/ship
```

한 명령으로:
1. 테스트 실행 (프로젝트 타입 자동 감지)
2. 실패 시 분석 + 수정 시도
3. conventional commit 메시지 생성 + 커밋
4. PR 생성 (`gh pr create`)

수동으로 하고 싶으면 각 단계를 직접 요청하면 됨.

---

## 문서 업데이트

코드를 바꾼 후 관련 문서가 걱정되면:

```
@doc-updater
```

- git diff 기반으로 영향받는 기존 문서만 찾아서 업데이트
- 새 파일 생성 안 함 (기존 문서 수정만)
- worktree 격리 실행

---

## 야간 / 장시간 자율 작업

작업 전 편집 범위를 제한:

```bash
# 터미널에서
freeze ~/dev/my-project        # 이 디렉토리만 편집 허용
freeze-status                   # 현재 상태 확인
```

Claude Code가 다른 프로젝트 파일을 건드리려 하면 hook이 자동 차단.

작업 완료 후:

```bash
unfreeze                        # 제한 해제
```

**야간 자율 실행 예시:**

```bash
freeze ~/dev/my-project
claude -p "TODO.md에 있는 작업들을 순서대로 구현해줘" \
  --max-turns 50 \
  --permission-mode acceptEdits
# 다음 날 아침 — 세션 시작하면 handoff가 자동 로드됨
```

---

## 세션 종료

### 자동 (기본)

세션을 끝내면 **Stop hook**이 자동으로:
- 현재 branch, 최근 커밋 5개, staged/unstaged 변경 사항 캡처
- `~/.claude/handoffs/latest.md`에 저장
- 다음 세션에서 자동 복원

### 수동 (상세 핸드오프가 필요할 때)

```
/handoff
```

자동 핸드오프보다 더 풍부한 맥락 저장:
- 완료/미완료 항목
- 다음 단계
- 주의사항
- 관련 파일 목록

장기 작업이나 다른 사람에게 인수인계할 때 유용.

---

## 시나리오별 조합

### "버그 잡고 바로 배포"

```
/debug 결제 API에서 409 에러 발생
# ... 수정 완료 후
/review
/ship
```

### "프론트엔드 피처 개발"

```
# 코드 작성 (typecheck hook이 자동으로 에러 잡아줌)
/verify http://localhost:3000/new-feature
# 문제 있으면 수정 반복
/review
@security-reviewer
/ship
```

### "대규모 리팩토링"

```
# 계획 수립
# 코드 수정
@code-reviewer              # 일반 리뷰
@security-reviewer          # 보안 리뷰
@doc-updater                # 문서 반영
/ship
```

### "야간에 맡기고 퇴근"

```bash
freeze ~/dev/project
claude -p "이 프로젝트의 테스트 커버리지를 80%로 올려줘" \
  --max-turns 100 \
  --permission-mode acceptEdits
```

---

## 전체 인벤토리

### Hooks (6개, 자동 실행)

| Hook | 타이밍 | 역할 |
|------|--------|------|
| session-start | SessionStart | 이전 handoff 자동 로드 |
| careful-with-judge | PreToolUse (Bash) | 위험 명령 LLM 판단 |
| protect-secrets | PreToolUse (Edit/Write) | 민감 파일 보호 |
| freeze | PreToolUse (Edit/Write) | 편집 범위 제한 |
| post-typecheck | PostToolUse (Edit/Write) | 자동 타입 체크 |
| auto-handoff | Stop | 세션 상태 저장 |

### Skills (5개, 수동 호출)

| Skill | 명령 | 용도 |
|-------|------|------|
| debug | `/debug <증상>` | 구조화 디버깅 |
| review | `/review` | PR 사전 리뷰 |
| ship | `/ship` | 테스트 → 커밋 → PR |
| verify | `/verify <URL>` | 프론트엔드 시각 검증 |
| handoff | `/handoff` | 수동 세션 인수인계 |

### Agents (3개, @로 호출)

| Agent | 호출 | 특성 |
|-------|------|------|
| code-reviewer | `@code-reviewer` | worktree 격리, 읽기 전용 |
| security-reviewer | `@security-reviewer` | OWASP 포커스, 읽기 전용 |
| doc-updater | `@doc-updater` | worktree 격리, 문서만 수정 |

### Shell 함수 (3개)

| 함수 | 용도 |
|------|------|
| `freeze <dir>` | 편집 범위 제한 |
| `unfreeze` | 제한 해제 |
| `freeze-status` | 현재 상태 확인 |
