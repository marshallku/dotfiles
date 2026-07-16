---
name: loops
description: open-loops 레지스트리 triage — review_after 지난 항목을 daily 노트/git 증거와 대조해 close/defer/act 결정 후 원자적으로 갱신. "열린 것 정리해", "밀린 것 뭐 있어", "open loops 봐줘", "/loops" 류 요청에 사용.
user-invocable: true
allowed-tools: Bash,Read,Edit,Write,Grep,Glob
effort: medium
---

## 목적

`open-loops.json`(life-assistant 운영 메모리)은 성실히 유지되지만 **에스컬레이션 레이어가 없다** — `review_after`가 지난 항목이 몇 주씩 방치되고 저녁 리뷰에서 손으로 일부만 재기록된다. `surface-open-loops.sh` hook이 세션 시작 시 하루 1회 nudge를 주고, 이 스킬이 그 nudge를 받아 **각 항목을 실제로 처리**한다.

핵심 가치: 사람에게 "다시 판단하라"고만 하지 않고, **daily 노트 + git 증거를 대조해 "이건 이미 끝난 것 같다 / 이건 진짜 방치다"를 먼저 제안**한다. 방치의 상당수는 "실은 완료됐는데 close 안 한 것"이다 (예: monthly-note, 이미 랜딩된 기능).

## 절차

### 1. 레지스트리 로드 + overdue 계산

```bash
LOOPS_FILE="${OPEN_LOOPS_FILE:-$HOME/bots/Marshall Ku/memory/open-loops.json}"
TODAY=$(date +%Y-%m-%d)
[ -f "$LOOPS_FILE" ] || { echo "레지스트리 없음: $LOOPS_FILE"; exit 0; }

python3 - "$LOOPS_FILE" "$TODAY" <<'PY'
import json, sys, datetime
path, today_s = sys.argv[1], sys.argv[2]
today = datetime.date.fromisoformat(today_s)
data = json.load(open(path, encoding="utf-8"))
items = data.get("items", [])
ACTIVE = {"active", "incubating"}
overdue, active_nd = [], []
for it in items:
    if it.get("status") not in ACTIVE: continue
    ra = it.get("review_after")
    if not ra: active_nd.append(it); continue
    try: d = datetime.date.fromisoformat(ra)
    except Exception: continue
    if d < today: overdue.append(((today-d).days, it))
overdue.sort(key=lambda x: x[0], reverse=True)
print(f"updated_at={data.get('updated_at')}  total={len(items)}  active/incubating={sum(1 for i in items if i.get('status') in ACTIVE)}")
print(f"\n=== OVERDUE ({len(overdue)}) ===")
for days, it in overdue:
    print(f"[{days}d] {it['id']} · {it.get('domain','?')} · {it.get('status')} · review_after={it.get('review_after')}")
    print(f"      next_action: {it.get('next_action','')[:200]}")
print(f"\n=== ACTIVE, no review_after ({len(active_nd)}) ===")
for it in active_nd:
    print(f"  {it['id']} · {it.get('domain','?')} · {it.get('status')}")
PY
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

### 4. 원자적 갱신

승인된 disposition을 JSON에 반영. **반드시 원자적으로**(temp write + `mv`), 스키마 보존, `updated_at`을 오늘로:

```bash
python3 - "$LOOPS_FILE" "$TODAY" <<'PY'
import json, sys, os, tempfile
path, today = sys.argv[1], sys.argv[2]
data = json.load(open(path, encoding="utf-8"))

# 예시: 아래 dict를 실제 승인 결과로 채운다.
# id -> {"status": "closed"/"active"/"incubating", "next_action": "...", "review_after": "YYYY-MM-DD" or None}
DISPOSITIONS = {
    # "monthly-note-april": {"status": "closed", "next_action": "W14~W18 랜딩 완료, 월간노트 폐기 확정 (2026-07-16)", "review_after": None},
}

by_id = {it["id"]: it for it in data["items"]}
for _id, d in DISPOSITIONS.items():
    it = by_id.get(_id)
    if not it:
        print(f"WARN: id 없음 {_id}"); continue
    it.update({k: v for k, v in d.items() if v is not None or k == "review_after"})
data["updated_at"] = today

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=4)
    f.write("\n")
os.replace(tmp, path)
print(f"applied {len(DISPOSITIONS)} disposition(s)")
PY
```

> **커밋**: `open-loops.json`은 bots repo의 런타임 메모리이고 auto-sync cron(30분 간격)이 커밋/푸시한다. **여기서 수동 commit/save.sh 하지 말 것** — 파일만 갱신하면 된다. dotfiles/코드 변경이 아니므로 cross-review 게이트 대상도 아니다.

### 5. 요약

처리 결과를 1문단으로: 몇 개 close / defer / act, 남은 overdue, 오늘의 다음 액션(act로 넘긴 항목). act 항목이 있으면 그 작업으로 자연스럽게 이어가라.

## 주의

- 이 스킬은 **레지스트리 위생(hygiene)** 도구다. overdue를 0으로 만드는 게 목표가 아니라, 각 항목이 정직한 상태(진짜 active인지, 실은 closed인지)를 갖게 하는 것.
- defer는 남용 금지 — "그냥 미루기"가 방치의 원인이었다. defer할 거면 **왜, 언제 다시 볼지** 구체적으로. 3회+ 반복 defer는 drop 후보.
- daily 노트의 "밀린 것" 섹션과 이 레지스트리가 어긋나면(노트엔 있는데 레지스트리엔 없음, 혹은 반대) 그 불일치도 사용자에게 보고.
