---
name: codex-plan
description: 구현 전 plan을 codex에게 pressure-test 시키기. Multi-round로 같은 thread에서 plan을 다듬어나간다.
user-invocable: true
allowed-tools: Bash, Read, Write, Edit
effort: medium
---

## 언제 사용하나

- **구현 시작 전** non-trivial한 plan이 잡혔을 때
- 새 모듈/엔드포인트/스키마 변경/마이그레이션 같은 **돌이키기 어려운 결정** 직전
- "이 접근으로 갈까 말까" 본인이 80% 확신 미만일 때
- ExitPlanMode 직전 마지막 sanity check 용도

작은 버그 수정, 단순 리팩터링, doc 변경은 스킵. `/ask-codex`가 더 가볍고 빠르다.

위치 관계:
- `/ask-codex` — 단발 자문 (작업 중)
- `/codex-plan` — 다회차 plan 검증 (구현 전) ← **여기**
- `/cross-review` — 코드 리뷰 (커밋 전)
- `/codex-delegate` — 하위 작업 위임 (코드 작성 위임)

## 워크플로우

### Step -1: Prior context retrieval (~/docs SSoT)

Plan brief를 쓰기 **전에** 30초 투자해서 SSoT를 본다. 비슷한 결정을 과거에 했거나, 다른 repo에서 같은 접근을 시도한 적이 있으면 plan에 인용한다 — codex가 같은 영역에 집중 비판할 수 있어 신호의 질이 한 단계 올라간다.

```bash
# Plan의 핵심 명사 2-3개로 검색
dn search "<keyword1> <keyword2>"
# 현재 repo가 topics/repos/에 있으면 인접 자료
dn related <repo-note>            # 예: dn related kagi
# 같은 도메인의 다른 repo도 살피기 (사용자가 명시적으로 차용을 원함)
ls ~/docs/topics/repos/           # 비슷한 프로젝트 후보
ls ~/docs/topics/decisions/ 2>/dev/null  # 과거 결정 기록
```

우선순위 hit:
- `sources/sessions/<repo-slug>/` — 같은 repo의 직전 작업들
- `topics/repos/<repo>.md` — 이 repo의 누적 지식
- `topics/repos/<다른 repo>.md` — 비슷한 도메인/스택의 다른 프로젝트 아이디어
- `topics/decisions/` — 과거 결정 기록
- `sources/debug/` — 과거 debug saga (관련 root cause)

hit이 있으면 Read해서 Step 0의 plan brief 안 `## Prior context` 섹션에 1-3줄로 인용. hit 0개면 그냥 다음으로. 검색에 5분 이상 쓰지 말 것.

### Step 0: Plan brief 작성

Claude 본인의 working memory에 있는 plan을 짧게 정리한다. codex가 코드도 직접 읽으니까 너무 장황할 필요 없음 — 의도와 핵심 결정만.

```bash
PLAN=$(mktemp /tmp/codex-plan.XXXXXX.md)
cat > "$PLAN" <<'EOF'
## Goal
<무엇을 왜 한다 — 1-2줄>

## Prior context (from ~/docs)
<Step -1에서 찾은 자료 1-3줄. 예: "kagi에서 같은 패턴을 Y로 풀었음 (~/docs/topics/repos/kagi.md). 이번엔 Z 제약 때문에 다르게 가야 함." 없으면 "없음".>

## Approach
<어떻게 한다 — 주요 파일/함수/단계 3-5개 bullet>

## Key decisions
<의미있는 트레이드오프, 대안을 고려했다가 버린 이유. 없으면 "없음">

## Risks I see
<본인이 인지하고 있는 리스크. 없으면 "없음 (codex가 찾아주길)">
EOF
```

**원칙**:
- 전체 200단어 이하 (Prior context 포함)
- 정직하게 써라. "사실 이 부분 어떻게 할지 모르겠음"이라고 적어도 OK — codex가 그 부분을 집중적으로 본다
- "Risks I see"에 본인이 본 리스크를 미리 적으면 codex가 같은 걸 다시 지적하는 노이즈를 줄여줌

### Round 1 (fresh)

```bash
bash ~/.claude/scripts/codex-plan.sh --plan-file "$PLAN"
# 또는 짧은 plan은 인라인:
bash ~/.claude/scripts/codex-plan.sh --reset "Plan: ..."
```

스크립트가 자동으로 새 thread를 시작하고 codex가 코드를 읽어가며 비판한다. stderr로 `[codex] Running command: ...` 형태 progress가 실시간으로 나옴.

### Round 2+ (continue)

같은 thread에서 후속 질문/반박:

```bash
bash ~/.claude/scripts/codex-plan.sh --continue "If I switch to approach Y instead, does X still apply?"
bash ~/.claude/scripts/codex-plan.sh --continue "What about the case where the queue is empty at startup?"
```

`--continue`는 같은 codex 세션을 이어가므로 **이전 라운드의 맥락을 전부 기억**한다. 매번 plan brief를 다시 보낼 필요 없음.

⚠️ **`--continue`의 한계**: 우리 4개 wrapper (`/ask-codex`, `/codex-plan`, `/cross-review`, `/codex-delegate`)는 모두 내부적으로 `codex-companion task` 서브커맨드로 라우팅된다 → 모두 동일한 `jobClass: "task"`로 기록됨. companion CLI는 thread id별 resume을 노출하지 않고 `--resume-last`는 이 task class 중 가장 최근 것을 그냥 잡는다. 따라서 plan 라운드 사이에 다른 wrapper를 호출하면 `--continue`가 그 thread를 잡아버린다. 두 가지 회피책:

1. **격리 (권장)**: plan 라운드 사이에 다른 codex wrapper를 호출하지 마라. 한 plan 세션을 끝낸 후 다른 codex 작업으로 넘어간다.
2. **--reset + 본인이 paraphrase**: round 2 prompt에 round 1의 핵심 critique를 1-2줄로 요약해서 포함시키고 `--reset`. 토큰은 더 쓰지만 wrong-thread 위험 0.

대부분의 plan은 1라운드면 충분하니 이 한계가 자주 문제되진 않음.

### 정리

각 codex 응답을 받으면:

1. **유효한 critique** → plan에 반영 (Edit으로 PLAN 파일 업데이트하거나 본인 working memory 수정)
2. **잘못 짚은 critique** → 다음 round에 `--continue`로 반박 ("X는 이미 Y로 처리됨")
3. **판단이 갈리는 부분** → 사용자에게 양쪽 의견 제시하고 결정 요청
4. 더 이상 critical concern 없으면 종료

## 응답 포맷 (사용자에게)

```
## Codex Plan Pressure-Test

Round 1: 5 concerns raised
Round 2: 2 resolved, 1 still standing, 2 new

### Reflected in plan
- <concern 1 요약>: plan에서 X로 보강
- <concern 2 요약>: 접근 변경 (A → B)

### Pushed back
- <concern 3 요약>: codex가 잘못 짚음. 이유: ...

### Needs your decision
- [Q1] <concern>: codex는 X 권장, Claude는 Y 선호. 차이점: ...

### Updated plan
<수정된 plan 요약 2-3줄>
```

## 원칙

- **Codex는 비판가, 결정자가 아님**. critique를 무조건 수용 금지. 본인이 판단해서 골라낸다.
- **본인 plan에 자신 있으면 1라운드로 끝**. round 2를 굳이 돌리지 마라. 새 시각이 안 나오면 노이즈만 늘어난다.
- **3라운드 이상 가면 stop**. plan이 그렇게 헷갈리는 거면 plan 자체를 다시 쓰는 게 맞다. 사용자에게 보고하고 처음부터.
- **읽기 전용**. codex는 plan 단계에서 코드를 절대 수정하지 않음 (스크립트가 read-only sandbox 강제). 위임이 필요하면 `/codex-delegate`로 별도 호출.
- **VERDICT 계약 없음**. plan은 코드 리뷰가 아니라 대화. APPROVED/REVISE 같은 게이트가 없다 — Claude가 본인 판단으로 종료한다.

## 주의

- plan이 너무 추상적("리팩터링 잘 하기")이면 codex는 일반론밖에 못 꺼낸다. **구체적인 파일/함수/단계**가 들어가야 신호가 나온다.
- 구현 도중 plan이 크게 바뀌면 `--reset`으로 thread를 새로 시작하는 게 깨끗하다. 이전 thread의 잘못된 가정을 codex가 계속 끌고 가는 걸 방지.
