---
name: iterate
description: 한 사이클 작업 워크플로우 — 코드 작업 → 유닛 테스트 → e2e 검증 → 빌드/린트/타입체크 → cross-review → save.sh 커밋. /loop와 함께 쓰면 매 사이클마다 같은 게이트가 강제됨.
user-invocable: true
allowed-tools: Bash,Read,Grep,Glob,Edit,Write,Agent,Skill,WebFetch
effort: high
---

## 언제 쓰나

- **`/iterate <task>` (기본)** — 한 사이클을 표준 게이트로 돌리고 싶을 때. 일반적인 사용은 이걸로 충분.
- **`/loop /iterate <task>` (반복형)** — 같은 워크플로우를 여러 사이클 반복해야 할 때만. 큰 작업을 사이클 단위로 쪼개서 자동 진행시키고 싶을 때 사용.
- 단순 한 줄 수정·문서·rename은 굳이 이 스킬을 쓸 필요 없음. 바로 `~/save.sh`로 충분.

## 절대 규칙

1. 단계는 **순서대로** 진행한다. 앞 단계에서 명확히 실패했다면 뒤로 진행하지 않는다.
2. 단계를 **스킵하려면 사유를 명시 보고**한다. ("e2e 인프라 없음 — 라이브러리 패키지라 스킵" 같은 식으로)
3. 마지막 commit은 반드시 `~/save.sh`를 통한다. 직접 `git commit`/`git push`를 부르지 않는다. (commit 전 cross-review 게이트는 Step 5에서 처리.)
4. 한 사이클은 **한 가지 작업 단위**로 끝낸다. 도중에 별개 작업이 끼어들면 별 사이클로 분리한다.

## Step 0 — 작업 컨텍스트 확정

- 인자로 받은 작업을 읽고, 작업 단위가 명확한지 확인한다.
- 모호하면 사용자에게 한 줄로 확인 후 진행 (질문 1개를 넘기지 않는다).
- 비자명한 작업이면 `/codex-plan`으로 plan을 pressure-test한 후 진행을 권장 (필수 아님).

## Step 1 — 구현

- 요청된 작업을 코드로 구현한다.
- 사용자 프로필의 anti-patterns / typescript-patterns / rust-patterns를 따른다.
- 변경은 작업 단위로 응집되게. 무관한 리팩터를 끼워 넣지 않는다.

## Step 2 — 유닛 테스트

테스트 가능 여부를 판단:

- **테스트 추가가 적절한 경우** (순수 함수, 분기 로직, 변환 함수 등) → 테스트 추가
- **테스트 추가가 부적절한 경우** (UI 마크업, 단순 글루 코드, 외부 API 래핑) → 추가 안 함

기존 테스트 + 새 테스트를 실행:

- `package.json` → `npm test` / `pnpm test` / `bun test`
- `Cargo.toml` → `cargo test`
- `go.mod` → `go test ./...`
- 그 외 → 프로젝트 README의 테스트 명령 따름

실패 시:

- 1~2회 수정 후 재시도
- 3회째도 실패하면 `/debug`로 전환하거나 사용자 보고

## Step 3 — e2e 검증 (자동 분기)

프로젝트 타입을 감지해 적절한 방식을 자동 선택한다.

### 분기 트리 (위에서 아래로 평가)

**(a) HTTP/RPC 서버 작업인가?**
판단 근거: 변경이 라우터/엔드포인트/핸들러를 건드렸거나, 서버 프레임워크(`express`, `fastify`, `hono`, `actix`, `axum`, `gin`, `fastapi`, `nest` 등) 의존성이 있는 패키지에서 일어났다.
→ 시나리오를 정하고 `curl` / `httpie` / 프로젝트 내 e2e 스크립트로 실행. 서버를 띄워야 하면 `run_in_background`로 띄우고 끝나면 정리.

**(b) 프론트엔드 작업인가?**
판단 근거: 변경이 React/Vue/Svelte 컴포넌트, CSS, 페이지 라우트를 건드렸다.
→ tabd(헤드리스 브라우저)로 dev 서버에 접속해 시나리오 실행. UI 변경이면 스크린샷까지 떠서 레이아웃 깨짐·콘솔 에러를 직접 확인.

**(c) CLI 도구인가?**
→ 실제 바이너리/스크립트를 만들거나 실행해서 입출력을 확인.

**(d) 위 어디에도 안 맞거나 자동화가 비현실적인가?**
→ 사용자에게 시나리오를 한 줄로 제시하고 리뷰 요청. 예:

> "e2e 자동화가 어려워서 직접 확인 부탁. 시나리오: 1) 로그인 페이지 진입 → 2) 잘못된 비번 입력 → 3) 에러 토스트 노출. 통과/실패만 알려주면 됨."

**(e) 그것도 의미가 없는 경우** (라이브러리 내부 유틸 등)
→ "e2e 스킵 — 사유: 외부 인터페이스를 변경하지 않은 라이브러리 내부 변경이라 유닛 테스트로 충분" 형식으로 명시 보고. 사일런트 스킵 금지.

## Step 4 — 빌드 / 린트 / 타입체크

병렬로 가능한 것은 한 메시지에서 동시에 실행 (Bash 병렬).

| 프로젝트   | 명령                                                           |
| ---------- | -------------------------------------------------------------- |
| TypeScript | `npx tsc --noEmit`, `npm run lint`, `npm run build` (있으면)   |
| Rust       | `cargo check`, `cargo clippy -- -D warnings`, `cargo build`    |
| Go         | `go vet ./...`, `golangci-lint run` (있으면), `go build ./...` |

실패 시:

- 1~2회 수정 후 재시도
- 그래도 실패면 `/debug` 또는 사용자 보고

> **참고**: `post-typecheck.sh` hook이 매 Edit/Write 후 자동으로 `tsc --noEmit` / `cargo check` 등을 돌리므로 Step 4는 마지막 종합 점검 성격. 그래도 빌드/린트는 hook이 안 돌리니 여기서 직접 돌린다.

## Step 5 — cross-review → 커밋

여기까지 통과했으면 commit 전 마지막 게이트를 직접 처리한다.

1. **cross-review** — `/cross-review`(또는 `codex-review.sh`)로 변경분을 codex에 크로스체크. CRITICAL이 나오면 그 자리에서 Fix-First 적용 후 재시도. 같은 CRITICAL이 두 번 연속이면 사용자 보고.
2. **commit** — APPROVED면 `~/save.sh`로 커밋(+push). 직접 `git commit`/`git push`를 부르지 않는다. (auto-review 게이트가 켜져 있으면 `~/save.sh`는 fresh reviewed marker가 있어야 통과 — cross-review가 APPROVED 시 자동으로 marker를 찍는다.)

PR이 필요하면 `~/save.sh` 후 `gh pr create`로 별도 처리. 작은 단위 작업은 commit-only로 충분.

## /loop 통합 가이드

```
/loop /iterate <task description>
```

- dynamic loop (`/loop /iterate ...` interval 미지정)이 가장 자연스럽다. 한 사이클이 끝나면 다음 사이클은 새 작업 받거나 같은 작업을 이어가도록 사용자가 결정.
- 매 틱마다 이 SKILL.md가 다시 로드되므로 단계 누락이 어렵다.
- 사이클 끝에 다음 작업이 없으면 loop를 자연스럽게 종료하고 사용자에게 다음 입력을 요청.

## 보고 형식

사이클이 끝나면 한 블록으로 정리:

```
[iterate cycle 결과]
- 구현: <한 줄>
- 유닛 테스트: 추가 N개 / 통과 (또는 스킵 사유)
- e2e: <분기 결과> / 통과 (또는 스킵 사유)
- 빌드/린트/타입체크: 통과
- cross-review: APPROVED (또는 적용한 CRITICAL fix)
- 커밋: <해시> (save.sh)
```

스킵한 단계가 있으면 그 사유가 위 보고에 반드시 들어가야 한다.
