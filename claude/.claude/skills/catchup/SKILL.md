---
name: catchup
description: 마지막 정리 시점부터 오늘까지의 ~/.claude + ~/.codex 대화 기록을 훑어서 노트(daily/weekly/topics)에 작업/의사결정/배운 것을 정리. 쓰기는 AIDE(aidectl), 읽기는 ~/docs mirror. 마지막 일자는 ~/docs/.last-catchup에 저장됨.
user-invocable: true
allowed-tools: Bash,Read,Edit,Write,Glob,Grep
effort: high
---

## 절차

### 1. 시작 일자 확정

```bash
SINCE=$(cat ~/docs/.last-catchup 2>/dev/null | tr -d '[:space:]')
[[ -z "$SINCE" ]] && SINCE=$(date -d "7 days ago" +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)
echo "catchup range: $SINCE → $TODAY (SINCE 포함, 오버랩 의도)"
```

### 2. 소스 탐색 — Claude가 직접

구조/스키마를 **먼저 probe**한 뒤 어떤 surface를 읽을지 결정할 것. 소스 포맷은 CLI 버전에 따라 바뀌므로 스키마 가정 금지, 우선 살펴보고 판단. 후보:

**Claude Code**
- `~/.claude/projects/<proj-hash>/*.jsonl` — 세션 전문 (canonical). 프로젝트별 hash는 cwd 경로에 대응.
- `~/.claude/projects/<proj-hash>/memory/MEMORY.md` + 관련 md — 자동 memory (user/feedback/project/reference). 해당 프로젝트 맥락 이해에 유용.
- `~/.claude/handoffs/latest.md` — 가장 최근 세션 핸드오프 요약.

**Codex**
- `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` — 세션 rollout (**codex 0.118+ 현재 canonical**).
- `~/.codex/history.jsonl` — user prompt 스트림 (session_id/ts/text). 단, 최근 버전에서 갱신 안 될 수 있음 — mtime 확인.
- `~/.codex/state_5.sqlite` — threads 메타 (cwd, git_branch, git_sha, first_user_message, tokens_used). 마찬가지로 버전에 따라 stale 가능. 최근 `updated_at` 확인:
  ```bash
  sqlite3 ~/.codex/state_5.sqlite "select datetime(max(updated_at), 'unixepoch') from threads" 2>/dev/null
  ```
- `~/.codex/memories/` — 크로스 세션 memory (있다면).

**Git cross-validation**
세션에서 논의된 게 실제 commit됐는지 각 cwd마다:
```bash
git -C <cwd> log --since="$SINCE" --pretty='format:%h %ad %s' --date=short 2>/dev/null
```

**가속기 (선택)**
빠른 overview가 필요하면 `~/docs/scripts/dn catchup --since "$SINCE" --full`. 이건 jsonl만 훑고 내부 bash 필터가 frozen이라 최신 소스를 전부 커버하진 않음 — 보조용.

### 3. 노이즈 패턴 (source 읽을 때 적용)

필터는 Claude가 판단해서 적용. 대표 noise:

- Claude Code: `type != user/assistant`, `isSidechain == true`, 또는 content가 `Respond ONLY 'allow' or 'deny'.` / `<system-reminder>` / `<task-notification>` / `<command-message>` / `<command-name>` / `<local-command-stdout>` / `Stop hook feedback:` / `[auto-review]` / `Caveat: The messages below` / `[Request interrupted by user` 로 시작.
- Codex: `type != response_item`, `payload.role ∈ {developer, reasoning}`, 또는 content가 `# AGENTS.md instructions for` / `<permissions instructions>` / `<user_instructions>` / `<system_instructions>` 로 시작.

이 목록은 가이드일 뿐 — 새 패턴 보이면 판단해서 거르고, 사용자가 직접 타이핑한 걸로 보이는 건 무조건 보존.

### 4. 노트 업데이트 — AIDE로 쓰기

노트의 원본은 AIDE다. `~/docs`는 docs-sync가 1분 안팎으로 따라오는 **읽기 전용 mirror** — `~/docs/daily|weekly|topics/` 파일을 Edit/Write로 직접 고치지 마라(두 번째 writer가 되어 docs-sync 충돌을 만든다). 쓰기는 전부 `aidectl`(catchup 토큰):

```bash
export AIDECTL_CONFIG=~/.config/aidectl/catchup   # daily·weekly·topics 쓰기, templates 읽기
```

- **덧붙이기** (Notes 항목, 로그 한 줄 등): 서버가 섹션 끝에 원자적으로 붙인다. 재실행해도 중복 없음.
  `aidectl append topics/<cat>/<slug>.md --heading Notes --create-heading --if-absent --text "<항목>"`
- **고쳐 쓰기** (기존 섹션 보강, frontmatter `updated:` 갱신 등):
  1. `aidectl get <path> --json > /tmp/n.json` → `jq -r .body`를 임시 `.md`로, `jq .version`을 V로.
  2. 임시 파일을 Edit로 수정.
  3. `aidectl put <path> --base-version V --file <임시.md>` — exit 4면 그사이 바뀐 것: 1부터 다시(새 본문에 같은 수정을 다시 적용). 덮어쓰기는 이 경로로만.
- **daily**: `aidectl daily YYYY-MM-DD --json`(없으면 템플릿으로 생성)으로 받고 위 절차. `## Tasks`와 `<!-- aide:slot … -->` 블록은 건드리지 마라(사용자·플러그인 소유).
- **weekly**: 주가 끝났으면 `aidectl periodic weekly YYYY-WNN --json`으로 받고(없으면 템플릿 생성) 위 절차.
- **topics**: 관련 topic 업데이트. 신규 topic은 명백히 새 주제일 때만, 사용자 확인 후 `aidectl put topics/<cat>/<slug>.md --create-only --file <임시.md>` (exit 3 = 이미 있음 → 내용 비교 후 판단).
- **`topics/INDEX.md`**: 신규 topic이면 `aidectl append topics/INDEX.md --heading "<카테고리 이름, # 없이>" --create-heading --if-absent --text "<index_line>"`.
- AIDE에 닿지 않으면(exit 1) **멈추고 보고**한다. 로컬 파일로 대신 쓰지 마라.
- 읽기(관련 노트 찾기·Read)는 `~/docs` mirror나 `dn search`로 해도 된다. 방금 쓴 내용은 mirror에 1분쯤 늦게 보인다.

### 5. 마지막 일자 기록

```bash
date +%Y-%m-%d > ~/docs/.last-catchup
```

다음 /catchup의 시작점. 오늘 날짜를 저장하므로 다음 호출은 오늘부터 다시 시작 (overlap 의도).

## 큐 모드 (비대화형 — life-assistant 야간 잡)

야간 무인 실행(life-assistant `catchup-queue` 플러그인)에는 사람이 없어 "신규 topic 확인"을 받을 수 없다. 이때 프롬프트가 **큐 모드**를 지시한다. 큐 모드에서는:

- daily/weekly 로그, **기존** topic 노트 Notes 섹션 append 는 평소처럼 자율 수행.
- **신규 topic 노트를 직접 만들지 마라.** 대신 각 후보를 **스풀 파일** `~/docs/.catchup-queue/incoming/<TODAY>.json` 에 적재 (authoritative `~/docs/.catchup-queue/<TODAY>.json` 는 절대 직접 쓰지 마라 — life-assistant 가 뮤텍스 하에 병합):

  ```json
  { "date": "YYYY-MM-DD", "candidates": [ {
      "id": "<짧은 슬러그, ':' 금지>",
      "title": "<한 줄 제목>",
      "category": "<automation 등 topics 하위 카테고리>",
      "target_path": "topics/<cat>/<slug>.md",
      "index_category": "## <INDEX.md 카테고리 헤더>",
      "index_line": "- [<제목>](<cat>/<slug>.md) — <훅>",
      "rationale": "<왜 새 주제인지 한두 줄>",
      "file_content": "<frontmatter + 본문 완성본. 그대로 topics/에 쓰일 최종본>",
      "status": "pending"
  } ] }
  ```

- 기존 노트 쓰기는 위 4번과 같이 `aidectl`로 한다.
- 스풀 파일이 이미 있으면 candidates 에 **append**. 한 스풀 안에서 같은 `target_path` 는 한 번만. (authoritative 큐와의 status 병합·중복 제거는 Go 가 처리하니, 이미 승인/반려된 항목인지까지 신경 쓸 필요 없다.)
- `file_content` 는 `~/docs/CLAUDE.md` 컨벤션(frontmatter, Atomic Note, Related)을 지킨 **최종본** — 사람이 버튼 한 번 누르면 그대로 커밋된다.
- `target_path` 는 반드시 `topics/` 하위 `.md`. (life-assistant 가 경로 순회를 거부)

승인/반려/보류는 사람이 Discord 버튼으로 처리한다. `.catchup-queue/` 는 gitignore 대상(임시 상태).

## 규칙

- **한국어 작성**. `~/docs/CLAUDE.md` 컨벤션 준수.
- **대화형 시작 시 큐 픽업**: `~/docs/.catchup-queue/*.json` 에 `status: pending` 후보가 있으면 정리 전에 먼저 사용자에게 보여주고, 승인하면 `file_content` 를 `aidectl put <target_path> --create-only` 로 만들고(exit 3 → `aidectl get` 해서 같은 내용이면 이미 된 것, 다르면 멈추고 보고), INDEX 에 `index_line` 을 `append --if-absent` 로 추가한 뒤에만 해당 후보 `status`→`approved` 로 갱신(키보드 폴백).
- **`dn`/`aidectl` 호출은 항상 `EDITOR=cat`** (안 그러면 nvim이 떠서 블로킹). `aidectl … --edit`은 쓰지 마라 — 위 get/put 절차로.
- **Notes 섹션 항목 사이 `---` 줄**.
- **topic note Related 섹션 양방향 유지** (A→B 추가 시 B→A도).
- **신규 topic 자동 생성 금지**. 사용자 확인 후만.
- 관련 topic이 있을 법한 작업이면 해당 `topics/<cat>/<slug>.md`를 먼저 Read하고 시작.
- 세션 수 많으면 cwd 기준으로 우선순위 정해서 의미 있는 것부터. 짧은 세션(1~2 턴)이나 보일러플레이트(`You are a senior engineer performing an independent code review...`)는 핵심만 요약.
