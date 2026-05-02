---
name: codex-delegate
description: 하위 작업을 codex에게 위임. Background 실행 + write 권한이 기본이라 codex가 직접 코드 수정. status/result/cancel로 진행 관리.
user-invocable: true
allowed-tools: Bash, Read, Edit
effort: medium
---

## 언제 위임하나

위임 = **본인이 안 해도 되는 작업을 다른 모델에 넘기기**. 트레이드오프는 컨텍스트 단절 (codex가 우리 대화 맥락을 모름). 명확하게 떼낼 수 있는 작업만 위임한다.

**위임에 적합:**
- 명확한 **diagnostic**: "이 테스트가 왜 실패하는지 조사" / "이 함수에 N+1이 있는지 확인"
- 명확한 **mechanical**: "src/foo.ts:42에 null 체크 추가" / "deprecated API 콜 5군데 새 시그니처로 마이그레이트"
- 같은 시간이지만 **본인 컨텍스트를 안 흐리고 싶은** 작업: 큰 파일 디버깅, repetitive한 fix
- 본인이 막혔거나 다른 시각이 필요한 **rescue**: "이 버그 1시간째 못 잡겠는데 처음부터 다시 봐주라"

**위임 금지:**
- 사용자 의도를 해석해야 하는 **모호한** 작업 ("UI 좀 깔끔하게")
- 본 codebase의 컨벤션을 깊이 알아야 하는 작업 (codex는 AGENTS.md만 봄)
- 실시간 사용자 피드백이 필요한 작업
- security-sensitive 변경 (auth, crypto, secrets handling) — Claude가 직접 + 사용자 검토

위치 관계:
- `/codex-plan` — plan 검증 (read-only, 대화)
- `/codex-delegate` — 코드 작성 위임 (write, 백그라운드) ← **여기**
- `/cross-review` — codex가 작성한 코드도 cross-review로 다시 검증

## 워크플로우

### Step 1: Brief 작성

위임 task는 prompt 한 문장으로 부족하다. codex가 우리 대화 맥락을 모르기 때문. brief에 포함:

```
## Task
<한 문장 — 무엇을 한다>

## Where
<관련 파일/함수/라인. 본인이 이미 찾아낸 위치를 명시>

## Why
<이 변경이 필요한 이유 한 줄. codex가 "왜?" 헷갈리지 않게>

## Constraints
<반드시 지켜야 할 것: API 호환, 특정 패턴 사용, 건드리지 말 파일 등>

## Acceptance
<완료 판단 기준: "테스트 X가 통과", "lint clean", "function Y의 동작이 변하지 않음">
```

이걸 한 줄짜리 task argument로 넘기는 게 아니라, **여러 줄 prompt**로 넣는다. `--raw`를 쓰지 않으면 스크립트가 operating rules를 추가로 붙여줌 (smallest viable change, summary section 강제 등).

### Step 2: 위임 실행 (background 기본)

```bash
bash ~/.claude/scripts/codex-delegate.sh "Task: ...

Where: src/auth/middleware.ts:120 (cors() handler)

Why: CORS preflight가 OPTIONS 요청에서 인증 미들웨어보다 늦게 호출돼서 CORS 헤더가 안 붙는 버그. ...

Constraints: ...

Acceptance: ..."
```

Output: `Codex Task started in the background as task-XXXXX-YYYYY.`

job id를 메모해둔다 (또는 `--status`로 다시 찾을 수 있음).

### Step 3: 진행 모니터링

```bash
# 전체 잡 목록
bash ~/.claude/scripts/codex-delegate.sh --status

# 특정 잡 상태
bash ~/.claude/scripts/codex-delegate.sh --status task-XXXXX-YYYYY

# 로그 실시간 follow
bash ~/.claude/scripts/codex-delegate.sh --tail task-XXXXX-YYYYY
```

`--tail`은 ISO 타임스탬프를 걷어내고 사람이 읽기 좋게 prefix를 붙여 흐름을 보여준다:

- `🟢 turn started` — turn 시작
- `🔵 turn completed` — turn 정상 종료
- `🟠 turn <status>` — turn이 비정상 종료 (failed, cancelled 등 — companion이 emit하는 status를 그대로 표시)
- `💬 ...` — codex가 중간에 한 말 (intermediate message + 최종 답변)
- `🧠 ...` — codex의 reasoning summary trace
- `▶ <command>` — codex가 실행한 명령 (zsh -lc 래퍼는 제거)
- `  ✓ (exit N)` — 명령 결과
- `❌ <error>` — codex runtime error
- `[final marker — codex done]` — 정상 종료 (마지막 turn 상태가 completed일 때)
- `[final marker — codex <status>]` — 비정상 종료 (failed/cancelled 등 마지막 turn 상태 그대로)
- `[final marker — codex errored]` — Codex error 라인이 먼저 잡혀서 종료한 경우

작업 5분 이상 걸리면 `--tail`로 보면서 다른 일 진행. raw 로그 (디버깅용) 가 필요하면 `CODEX_DELEGATE_TAIL_RAW=1 bash ... --tail JOB`.

### Step 4: 결과 회수

작업 완료 후:

```bash
bash ~/.claude/scripts/codex-delegate.sh --result task-XXXXX-YYYYY
```

→ codex의 최종 summary (touched files, what changed, what didn't, follow-ups).

### Step 5: 검증 (필수)

위임한 변경은 **반드시 본인이 다시 본다**:

1. `git diff`로 실제 변경 확인 — codex가 약속한 것과 일치하는가?
2. scope 침범 확인 — 건드리지 말라고 한 파일을 건드렸는가?
3. 테스트/typecheck 직접 실행 — codex가 돌렸다고 해도 한번 더
4. 의심스러우면 `/cross-review` — codex가 작성한 코드도 cross-review 대상

## 옵션

```bash
# Foreground (작은 작업, 결과 즉시 받기)
bash ~/.claude/scripts/codex-delegate.sh --foreground "..."

# Read-only (조사만, 수정 금지) — diagnostic 위임에 사용
bash ~/.claude/scripts/codex-delegate.sh --readonly "왜 이 테스트가 flaky한지 조사하고 가설 3개 제시"

# 작업 취소
bash ~/.claude/scripts/codex-delegate.sh --cancel task-XXXXX-YYYYY

# 모델/effort 조정 (env)
CODEX_DELEGATE_EFFORT=high bash ~/.claude/scripts/codex-delegate.sh "..."
CODEX_DELEGATE_MODEL=spark bash ~/.claude/scripts/codex-delegate.sh "..."  # 빠른 모델
```

## 응답 포맷 (사용자에게)

```
## Codex Delegation

Job: task-XXXXX-YYYYY (12s, completed)
Sandbox: workspace-write

### Codex's summary
<--result 출력 그대로>

### Verification (Claude)
- git diff 확인: <맞음 / X에서 scope 벗어남>
- 테스트: <pass / fail / 안 돌림 + 이유>
- 검토 의견: <문제 없음 / Q1, Q2 사용자 결정 필요>

### Next
<권장 다음 단계 — 추가 위임, 본인이 마무리, 사용자 결정 등>
```

## 원칙

- **위임 = 책임 위임이 아님**. 결과는 본인이 review + verify 한다. codex가 "테스트 통과" 했다고 자동 트러스트 금지.
- **위임 후 cross-review**. codex가 작성한 코드는 다른 LLM이 봐야 하므로 `/cross-review`를 한 번 더 돌리는 게 안전 (특히 security-adjacent).
- **Background 기본, foreground는 예외**. 1분 안에 끝날 trivial한 작업만 foreground. 그 외엔 background로 띄우고 본인은 다른 작업 진행.
- **위임 시 cross-review 게이트 자동 강제 (--write 모드만)**. codex가 파일을 직접 편집하니까 Claude의 Edit/Write hook을 우회 → track-edit.sh가 안 발동 → dirty-log undercount + reviewed marker 그대로 유지. 그래서 codex-delegate.sh가 launch 시점에 두 가지를 함:
  1. `~/.claude/state/reviewed-<repo-hash>` 삭제 (이미 통과한 review를 무효화)
  2. `~/.claude/state/codex-delegate-pending-<repo-hash>` touch (pre-commit-gate가 file-count early-exit를 우회하도록 신호)

  결과: 위임 이후 commit/push은 `/cross-review` APPROVED 받기 전엔 `pre-commit-gate.sh`가 무조건 막음. 두 marker는 cross-review APPROVED 시 `mark_repo_reviewed()`가 한꺼번에 정리.
- **하나씩 위임**. 여러 task를 한 번에 묶어서 던지지 말 것 — codex가 우선순위를 잘못 잡거나 일부만 처리하고 끝낼 수 있다.
- **commit 금지**. 스크립트의 default operating rules에 "git push/commit 금지"가 들어있지만, 만약 raw로 보낼 때도 명시할 것.
- **막혔을 때만 rescue로**. 본인이 처음부터 할 수 있는 작업을 매번 위임하면 사용자의 컨텍스트가 codex와 Claude 양쪽으로 분산돼서 디버깅이 어려워진다.

## 주의

- 위임 prompt는 **한 번** 잘 쓴다. codex와 다회 대화는 plan용 (`/codex-plan`)이지 위임용이 아님 — 위임 작업은 자기-완결적이어야 한다.
- `--tail`은 잡이 완료되면 `[final marker — codex done]` 출력 후 자동 종료. 잡 끝나기 전에 빠지고 싶으면 Ctrl-C — 잡 자체에는 영향 없음.
- background job 결과는 `~/.claude/state/codex-companion/state/<workspace>/jobs/`에 영구 저장됨. 재부팅 후에도 `--result <job-id>`로 회수 가능.
