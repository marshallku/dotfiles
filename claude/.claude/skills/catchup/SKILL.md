---
name: catchup
description: 마지막 정리 시점부터 오늘까지의 ~/.claude + ~/.codex 대화 기록을 훑어서 ~/docs(daily/weekly/topics)에 작업/의사결정/배운 것을 정리. 마지막 일자는 ~/docs/.last-catchup에 저장됨.
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

### 4. `~/docs` 업데이트

`~/docs/CLAUDE.md`의 conventions 준수. 핵심:

- **`daily/YYYY-MM-DD.md`** — 날짜별 작업 로그 / 배운 것 / 정리. 이미 있으면 `## Tasks` 섹션은 보존(사용자가 직접 쓴 것), 나머지만 보강. Notes 섹션 항목 사이는 `---` 구분.
- **`topics/<cat>/<slug>.md`** — 관련 topic 업데이트. frontmatter `updated:` 날짜 갱신. 신규 topic은 명백히 새 주제일 때만, 사용자에게 확인 후.
- **`weekly/YYYY-WNN.md`** — 주가 마무리됐으면 작성. 템플릿 필요하면 `EDITOR=cat ~/docs/scripts/dn weekly YYYY-WNN`.
- **`topics/INDEX.md`** — 신규 topic 추가 시 해당 카테고리 섹션에 1줄 추가.

### 5. 마지막 일자 기록

```bash
date +%Y-%m-%d > ~/docs/.last-catchup
```

다음 /catchup의 시작점. 오늘 날짜를 저장하므로 다음 호출은 오늘부터 다시 시작 (overlap 의도).

## 규칙

- **한국어 작성**. `~/docs/CLAUDE.md` 컨벤션 준수.
- **`dn` 호출은 항상 `EDITOR=cat`** (안 그러면 nvim이 떠서 블로킹).
- **Notes 섹션 항목 사이 `---` 줄**.
- **topic note Related 섹션 양방향 유지** (A→B 추가 시 B→A도).
- **신규 topic 자동 생성 금지**. 사용자 확인 후만.
- 관련 topic이 있을 법한 작업이면 해당 `topics/<cat>/<slug>.md`를 먼저 Read하고 시작.
- 세션 수 많으면 cwd 기준으로 우선순위 정해서 의미 있는 것부터. 짧은 세션(1~2 턴)이나 보일러플레이트(`You are a senior engineer performing an independent code review...`)는 핵심만 요약.
