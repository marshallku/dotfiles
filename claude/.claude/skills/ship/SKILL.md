---
name: ship
description: 테스트 → 커밋 → PR 워크플로우
user-invocable: true
allowed-tools: Bash,Read,Grep,Glob,Edit,Agent
effort: medium
---

## 워크플로우

### Step 1: 테스트 실행

- 프로젝트 타입에 맞는 테스트 실행:
  - `package.json` → `npm test` 또는 `pnpm test`
  - `Cargo.toml` → `cargo test`
  - `go.mod` → `go test ./...`
- 타입 체크: `tsc --noEmit` / `cargo check` / `go vet ./...`
- 린트: `npm run lint` (있으면)

### Step 2: 테스트 실패 시

- 실패 원인 분석
- 수정 가능하면 수정 후 재실행
- 수정 불가능하면 사용자에게 보고 후 중단

### Step 2.5: Codex Cross-Review 게이트

커밋 직전, 변경 범위가 trivial하지 않으면 codex 크로스체크를 실행한다:

- 한 줄 수정 / 문서만 변경 / 순수 rename → **스킵 가능**
- 그 외 모두 → `bash ~/.claude/scripts/codex-review.sh --uncommitted` 실행
- 종료 코드로 판단:
  - exit 0 (APPROVED) → Step 3으로 진행
  - exit 1 (REVISE) → `/cross-review` skill의 Fix-First 루프로 전환. CRITICAL 해결 후 재시도.
  - exit 2 (error) → 사용자에게 보고 후 중단 (codex 미설치, 네트워크 등)

Ship 흐름에서는 CRITICAL이 있으면 **절대 커밋하지 않는다**. 이게 "항상 리뷰받는" 규칙의 강제 지점.

### Step 3: 커밋

- `git diff --staged` + `git diff` 확인
- 변경 사항 분석 후 conventional commit 메시지 작성
- `git add` (관련 파일만, `-A` 사용 금지)
- `git commit`

### Step 4: PR 생성

- `git push -u origin <branch>`
- `gh pr create` 실행
- PR 제목: 70자 이하
- PR 본문: Summary + Test plan

## 규칙

- .env, credentials 등 시크릿 파일 커밋 금지
- 테스트 통과 전 커밋 금지
- main/master에 직접 push 금지 (확인 필요)
