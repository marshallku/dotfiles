---
name: audit
description: 프로젝트 갭 감사 — 코드/문서/로드맵을 병렬 탐색해 미완성 구현, 문서-실제 불일치, 남은 작업을 우선순위 리스트로 정리. "개선할 부분/미비한 부분 없는지 깊이 파악해봐", "남은 작업 뭐야", "보안 위협 있는지 파악해봐" 류 요청에 사용.
user-invocable: true
arguments: focus
argument-hint: [focus] (optional — security / docs / mvp / perf 등 관점. 생략 시 전체 감사)
allowed-tools: Bash,Read,Grep,Glob,Agent
effort: high
---

## 언제 쓰나

- `/audit` — 프로젝트 전체를 훑어 "뭐가 미비한가 / 뭐가 남았나"를 우선순위로 뽑고 싶을 때.
- `/audit security` — 특정 관점(보안, 문서, MVP 출시, 성능 등)으로 좁혀서 감사할 때.
- 단일 파일/함수 단위 질문에는 과하다 — 그건 그냥 직접 읽고 답한다.

## 절대 규칙

1. **읽기 전용.** 이 스킬은 발견·보고만 한다. 수정은 사용자가 갭 리스트에서 골라준 뒤 별도 작업(워크플로우 게이트 적용)으로 진행한다.
2. **모든 발견은 증거 필수** — `file:line` 또는 커맨드 출력. "~인 것 같다"는 발견이 아니다.
3. **이미 알려진 항목 제외** — roadmap/TODO 문서에 이미 "할 일"로 적혀 있는 것은 갭이 아니라 계획이다. 단, 문서가 "됐다"고 주장하는데 실제로 안 된 것은 최우선 갭이다.

## Step 1 — 컨텍스트 수집 (인라인, 5분 이내)

병렬로 실행:

- 프로젝트가 스스로 주장하는 상태: `README*`, `docs/`, `ROADMAP*`, `CHANGELOG*`, `Cargo.toml`/`package.json`/`go.mod` 메타데이터
- 최근 흐름: `git log --oneline -30`, 열린 브랜치, `git status`
- SSoT 기억: `dn search "<project-name>"` (있으면) — 과거 세션에서 정리해둔 미완 항목·결정 사항
- focus 인자가 있으면 해당 관점의 키워드를 Step 2 프롬프트에 주입

## Step 2 — Explore fan-out (병렬 서브에이전트)

Agent(subagent_type: Explore)를 **한 메시지에서 병렬로** 띄운다. 기본 4개 렌즈, focus 인자가 있으면 해당 렌즈를 심화하고 무관한 렌즈는 줄인다:

| 렌즈 | 찾는 것 |
|---|---|
| **미완성 구현** | TODO/FIXME/HACK/unimplemented!/todo!()/stub/placeholder, 빈 catch, 시그니처만 있고 본문 없는 함수, dead feature flag |
| **문서-실제 불일치** | README/docs가 설명하는 플래그·명령·동작 vs 실제 CLI surface(--help)·코드. 양방향: 문서에만 있는 것, 코드에만 있는 것 |
| **품질 갭** | 핵심 로직 중 테스트 없는 모듈, 에러를 삼키는 경로, 입력 검증 누락, (focus=security면: path traversal·injection·secret 노출·권한 체크) |
| **완성도 갭** | 주요 사용자 플로우 중 끊기는 지점 — 설치→실행→핵심 기능→에러 시나리오를 따라가며 동작 안 할 코드 경로 |

각 에이전트 프롬프트에 반드시 포함: 프로젝트 한 줄 설명(Step 1에서 확보), focus 관점, "발견마다 file:line + 한 줄 근거, 추측 금지, 발견 없으면 '없음'이라고 답하라".

## Step 3 — 종합: 우선순위 갭 리스트

발견을 합쳐 중복 제거 후 분류:

- **P0** — 사용자가 겪는 깨짐 / 보안 결함 / 문서가 거짓말하는 것
- **P1** — 핵심 플로우의 미완성 / 테스트 공백 중 회귀 위험 높은 것
- **P2** — 개선하면 좋은 것 (naming/style/future-improvement는 제외 — 노이즈)

보고 형식:

```
[audit 결과 — <project> (focus: <focus|전체>)]
P0:
1. <한 줄> — <file:line> <근거 한 줄>
P1:
...
P2:
...
제외: 이미 roadmap에 계획된 항목 N개, 스타일성 지적 N개
```

발견이 없으면 없다고 보고한다 — 억지로 채우지 않는다.

## Step 4 — 후속 제안

리스트 제시 후 한 줄로 묻는다: **"어디부터 진행할까? 고르면 항목별로 워크플로우 게이트(구현→테스트→e2e→cross-review→save.sh) 지키면서 진행한다."**

사용자가 "전부" 또는 항목을 고르면, 항목당 한 작업 단위로 `/iterate` 게이트를 따라 진행한다.
