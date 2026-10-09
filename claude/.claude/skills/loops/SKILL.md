---
name: loops
description: open-loops 레지스트리 triage — review_after 지난 항목을 daily 노트/git 증거와 대조해 close/defer/act 결정 후 원자적으로 갱신. "열린 것 정리해", "밀린 것 뭐 있어", "open loops 봐줘", "/loops" 류 요청에 사용.
user-invocable: true
allowed-tools: Bash,Read,Edit,Write,Grep,Glob
effort: medium
---

## 목적

open-loops 레지스트리(AIDE 노트 `loops/open`, 2026-10-09부터 — 그 전엔 life-assistant `open-loops.json`)는 AIDE `loops` 플러그인이 매일 21:15 갱신하지만 **에스컬레이션 레이어가 없다** — `review_after`가 지난 항목이 몇 주씩 방치되고 저녁 리뷰에서 손으로 일부만 재기록된다. `surface-open-loops.sh` hook이 세션 시작 시 하루 1회 nudge를 주고, 이 스킬이 그 nudge를 받아 **각 항목을 실제로 처리**한다.

핵심 가치: 사람에게 "다시 판단하라"고만 하지 않고, **daily 노트 + git 증거를 대조해 "이건 이미 끝난 것 같다 / 이건 진짜 방치다"를 먼저 제안**한다. 방치의 상당수는 "실은 완료됐는데 close 안 한 것"이다 (예: monthly-note, 이미 랜딩된 기능).

## 절차

### 1. 레지스트리 로드 + overdue 계산

레지스트리는 AIDE 노트 `loops/open`이다(형식: `~/.claude/scripts/open-loops.py` 문서 참조 — `## 도메인` 아래 `- **제목** · 상태[ · review 날짜] · \`id\`` + 들여쓴 다음 행동 줄). 읽기·쓰기 모두 aidectl로:

```bash
export AIDECTL_CONFIG=~/.config/aidectl/catchup   # loops 쓰기 포함
LOOPS=$(mktemp -d)
aidectl get loops/open --json > "$LOOPS/note.json" || { echo "AIDE에 닿지 않음 — 멈추고 보고"; exit 1; }
jq -j .body "$LOOPS/note.json" > "$LOOPS/open.md"
TODAY=$(date +%Y-%m-%d)
~/.claude/scripts/open-loops.py overdue "$LOOPS/open.md" "$TODAY"
~/.claude/scripts/open-loops.py parse "$LOOPS/open.md" | jq '[.items[] | select(.status=="active" or .status=="incubating") | select(.review_after=="")] | map(.id)'   # 날짜 없는 active
```

인자로 특정 domain/id가 주어지면(`/loops maji`, `/loops life-assistant`) 그걸로 필터해서 좁혀라. 인자 없으면 overdue 전체.

### 2. 항목별 증거 대조 — 처리안(disposition) 제안

overdue 각 항목에 대해, 판단 전에 **가벼운 증거 수집**을 한다 (병렬로):

- **~/docs recall**: `dn search "<핵심어>"` 또는 `grep -rl "<id 핵심어>" ~/docs/daily ~/docs/topics | tail -5` — 최근 daily/topic에서 이 항목이 실제로 다뤄졌거나 완료 언급이 있는지.
- **git 증거**: 항목이 특정 repo와 관련되면(`domain`/제목에서 추론) 해당 repo에서 관련 커밋 확인 — `git -C <repo> log --oneline --since='<review_after>' | grep -i <keyword>`.
- 애매하면 해당 항목의 소스 노트(topics/…)를 Read.

증거를 근거로 각 항목에 처리안을 붙여 **표로 제시**한다:

| id | overdue | 추천 | 근거 |
|---|---|---|---|
| monthly-note-april | 38d | **close** or **act(즉시)** | 이미 W14~W18 랜딩, 노트만 안 씀 → 지금 쓰거나 폐기 |
| wesh-initial | 56d | **defer** or **drop** | incubating, 착수 의지 없음 3주+ 강등 이력 |
| investment-discord-length | 52d | **verify→close?** | 루프 메시지 청크 분할됐는지 코드 확인 필요 |

추천 disposition은 4종:
- **close** — 이미 해결됐거나(증거 확인) 폐기 확정. `next_action`에 해결/폐기 사유 1줄, `review_after: null`.
- **defer** — 여전히 유효하나 지금 안 함. 새 `review_after` 날짜 지정(막연히 미루지 말고 구체 날짜, 반복 강등이면 `incubating`으로 강등).
- **act** — 지금 처리. 이 스킬을 나가서 실제 작업으로 이어짐(별도 작업 후 완료되면 close).
- **drop** — 방치 확정 → close와 동일 처리하되 사유를 "폐기(N일 방치, 착수 의지 없음)"로.

### 3. 사용자 승인

표 + 추천을 제시하고 **사용자 확인을 받는다**. 자동으로 close/defer 하지 말 것 — 이건 사용자의 우선순위 판단 영역이다. 사용자가 "다 추천대로" 하면 일괄 적용, 개별 조정하면 그대로 반영.

### 4. 갱신 — 읽은 버전으로만 쓴다

승인된 disposition을 노트에 반영한다. 1단계에서 받은 version으로만 쓰므로, 그사이 `loops` 플러그인이나 앱에서 바뀌었으면 exit 4로 거절된다 → 1단계부터 다시(새 본문에 같은 disposition 재적용).

```bash
# 승인 결과: id -> 바꿀 필드만 (status / next_action / review_after("" = 없음) / title / domain)
cat > "$LOOPS/changes.json" <<'JSON'
{
  "monthly-note-april": {"status": "closed", "next_action": "W14~W18 랜딩 완료, 월간노트 폐기 확정 (2026-10-09)", "review_after": ""}
}
JSON
# apply는 모든 id가 남고 형식이 맞을 때만 노트를 출력한다(아니면 아무것도 안 쓰고 exit 1)
~/.claude/scripts/open-loops.py apply "$LOOPS/open.md" "$LOOPS/changes.json" > "$LOOPS/new.md" \
  && aidectl put loops/open --base-version "$(jq .version "$LOOPS/note.json")" --file "$LOOPS/new.md"
```

> 커밋은 필요 없다 — AIDE가 원본이고 docs-sync가 mirror(`~/docs/loops/open.md`)에 반영한다. 항목은 지우지 말고 close한다(`loops` 플러그인도 지우지 않는다).

### 5. 요약

처리 결과를 1문단으로: 몇 개 close / defer / act, 남은 overdue, 오늘의 다음 액션(act로 넘긴 항목). act 항목이 있으면 그 작업으로 자연스럽게 이어가라.

## 주의

- 이 스킬은 **레지스트리 위생(hygiene)** 도구다. overdue를 0으로 만드는 게 목표가 아니라, 각 항목이 정직한 상태(진짜 active인지, 실은 closed인지)를 갖게 하는 것.
- defer는 남용 금지 — "그냥 미루기"가 방치의 원인이었다. defer할 거면 **왜, 언제 다시 볼지** 구체적으로. 3회+ 반복 defer는 drop 후보.
- daily 노트의 "밀린 것" 섹션과 이 레지스트리가 어긋나면(노트엔 있는데 레지스트리엔 없음, 혹은 반대) 그 불일치도 사용자에게 보고.
