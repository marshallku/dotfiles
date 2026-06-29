---
name: pr-review
description: 리모트 GitHub PR을 적대적으로 리뷰. Claude + codex 이중 리뷰어로 line-by-line 검증, P1~P5 분류, inline comment를 하나의 review로 일괄 게시, P1/P2 없으면 approve. "이 PR 리뷰해봐", "적대적 리뷰어로 리뷰하고 codex한테도 시켜", "line by line으로 comment 남겨" 류 요청에 사용.
user-invocable: true
arguments: pr
argument-hint: <PR 번호 또는 URL> (생략 시 현재 브랜치의 PR)
allowed-tools: Bash, Read, Grep, Glob, Agent
effort: high
---

## 목적

리모트 PR을 **적대적 리뷰어**로 검증한다. 핵심 규약(사용자가 매번 받아쓰게 하던 것):

1. **이중 리뷰어** — Claude(적대적) + codex(독립). 서로 다른 실패 모드를 노린다.
2. **소스코드 대조** — diff만 보지 말고 우리 코드베이스 컨벤션/기존 패턴과 비교.
3. **line-by-line** — 발견사항을 **각각 해당 라인에 anchor된 inline comment**로. 절대 하나로 뭉쳐 달지 않는다 (← 과거 실패 모드).
4. **P1~P5 분류** — 심각도. P1/P2가 하나도 없으면 `approve`, 있으면 `comment`(request-changes 아님, 사용자 규약은 comment).

> codex로 가는 프롬프트는 항상 영어. 사용자 보고는 한국어.

## 워크플로우

### Step 0: PR 식별 + 컨텍스트 수집

```bash
# 셀렉터 정규화: 인자가 있으면 그걸 PR로, 없으면 현재 브랜치의 PR 번호로 해소.
# 절대 빈 "$PR"를 gh에 넘기지 않는다 (`gh pr view ""`는 에러).
ARG="${ARG:-}"
# 인자(번호/URL) 또는 현재 브랜치 → 항상 **숫자 PR 번호**로 정규화.
# (URL/빈 값이 그대로 `gh api repos/.../pulls/$PR/...` 경로에 들어가면 깨진다.)
PR=$(gh pr view ${ARG:+"$ARG"} --json number -q .number 2>/dev/null) || {
  echo "PR을 특정할 수 없음 (인자 없고 현재 브랜치 PR도 없음) — 사용자에게 PR 번호/URL을 물어볼 것"; exit 1; }
gh pr view "$PR" --json number,title,body,baseRefName,headRefName,headRefOid,url,additions,deletions,changedFiles
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

이후 모든 명령은 정규화된 숫자 `"$PR"`를 쓴다 — URL/빈 값이 `gh api` 경로로 흘러갈 일이 없다.

- `headRefOid`(HEAD sha)는 inline comment 게시에 **필수** — 저장해둔다.
- `baseRefName`은 codex-review의 base.
- PR 번호/owner/repo도 저장.

전체 diff와 파일 목록:

```bash
gh pr diff "$PR"                    # 통짜 diff (Claude 정독용)
gh pr diff "$PR" --name-only        # 변경 파일 목록
```

### Step 1: Claude 적대적 리뷰

diff를 정독하고, **각 파일을 우리 소스와 대조**한다 (해당 모듈의 기존 패턴/유틸/에러 핸들링 컨벤션을 Grep으로 확인). 적대적 자세 — "이게 어떻게 깨지는가"를 먼저 묻는다. 점검 축:

- **정확성/버그** — 경계조건, null/에러 경로, race, off-by-one, 누락된 await
- **보안** — 입력 검증, 인젝션, 권한, 시크릿 노출, SSRF
- **회귀/호환성** — 기존 API/스키마/계약 깨짐
- **코드 퀄리티** — Rule of Three 위반, 중복, 재사용 가능한 기존 유틸 무시, 안티패턴(profile/910)
- **누락** — PR 설명의 의도 대비 미구현, 테스트 공백(단 "테스트 없음"은 보고 억제 대상 — 아래 참조)

각 발견사항은 `{path, line, severity(P1~P5), category, body}`로 구조화.

**심각도 기준:**
- **P1** — 머지하면 안 됨. 데이터 손실/보안 취약점/크래시/명백한 로직 버그.
- **P2** — 머지 전 수정 필요. 동작 결함, 회귀, 누락된 핵심 케이스.
- **P3** — 고치는 게 맞음. 약한 버그 가능성, 견고성, 명확성.
- **P4** — 제안. 가독성/구조/사소한 개선.
- **P5** — nit. 취향/스타일(억제 후보).

**보고 억제**(profile Codex 원칙 2): prettier/eslint가 잡는 포맷, CI가 잡는 lint/typecheck, 주관적 네이밍, "나중에 개선" 류, TODO 주석, 단순 테스트 커버리지 부족, import 정렬. → P4/P5에도 넣지 말 것.

### Step 2: codex 독립 리뷰 (병렬 관점)

PR을 로컬에 체크아웃하고 codex-review를 돌린다. **현재 브랜치를 저장**해두고 끝나면 복원:

```bash
ORIG_BRANCH=$(git rev-parse --abbrev-ref HEAD)
# 실제로 더티할 때만 stash → STASHED 플래그로 가드 (남의 기존 stash를 pop하지 않도록)
STASHED=0
if ! git diff --quiet || ! git diff --cached --quiet || \
   [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git stash push -u -m pr-review-tmp && STASHED=1
fi
gh pr checkout "$PR"

cat > /tmp/pr-review-brief.md <<EOF
Adversarial PR review. Compare against existing codebase conventions.
PR #$PR: <title>
Intent (from PR body): <요약>
Focus: correctness, security, regressions, code quality vs our patterns.
Classify each finding P1..P5. Report file:line for each.
EOF

CODEX_REVIEW_TIMEOUT=1200 bash ~/.claude/scripts/codex-review.sh \
  --base "$baseRefName" --context-file /tmp/pr-review-brief.md
# (gating call → foreground, Bash tool timeout: 600000)

git checkout "$ORIG_BRANCH"
[ "$STASHED" = 1 ] && git stash pop   # 우리가 만든 stash만 복원
```

codex 출력의 VERDICT/findings를 파싱한다. codex는 ground truth가 아님 — 명백한 오탐/억제 대상은 버린다.

### Step 3: 추합 (merge)

Claude findings ∪ codex findings:
- **중복 제거** — 같은 file:line ± 인접 라인의 같은 이슈는 하나로, 출처 표기(`Claude+codex 합치`).
- **충돌** — Claude와 codex 의견이 갈리면 양쪽을 모두 comment에 적고 사용자 판단에 맡긴다 (한쪽을 임의로 채택 금지).
- 각 comment body 형식: `**P2 · correctness** — <문제>. <왜 문제인지>. <제안>.` (출처가 둘 다면 ` _(Claude+codex)_` 첨부)

### Step 4: inline comment 일괄 게시 (← 메커닉 핵심)

**절대 `gh pr comment`(이슈 코멘트)로 뭉쳐 달지 않는다.** 모든 발견사항을 **하나의 review**에 line-anchored inline comment 배열로 담아 한 번에 게시한다. 페이로드를 파일로 만들고 `gh api ... --input`:

```bash
# payload.json — comments[]는 전부 같은 review에 묶여 한 번에 달린다
cat > /tmp/pr-review-payload.json <<'JSON'
{
  "commit_id": "<headRefOid>",
  "event": "COMMENT",
  "body": "## 적대적 리뷰 (Claude + codex)\n\n- P1: 0 / P2: 1 / P3: 2 / P4: 1\n- 판정: **CHANGES REQUESTED** (P2 존재)\n\n<2~3줄 총평>",
  "comments": [
    { "path": "src/foo.ts", "line": 42, "side": "RIGHT",
      "body": "**P2 · correctness** — `await` 누락으로 reject가 삼켜짐. ...에서 throw가 무시됨. `await` 추가. _(Claude+codex)_" },
    { "path": "src/bar.ts", "line": 88, "side": "RIGHT",
      "body": "**P3 · robustness** — 빈 배열일 때 NaN. 가드 추가 권장." }
  ]
}
JSON

gh api "repos/$REPO/pulls/$PR/reviews" --input /tmp/pr-review-payload.json
```

규칙:
- `line`은 **diff의 RIGHT(신규) 측 절대 라인 번호**. 삭제된 줄에 달려면 `"side":"LEFT"`. 범위 코멘트는 `start_line`+`line`.
- comment가 게시 불가한 라인(diff 컨텍스트 밖)이면 가장 가까운 변경 라인으로 옮기고 body에 원위치 명시.
- 라인 매칭이 까다로우면, 안전하게: 각 comment를 개별 `gh api .../pulls/$PR/comments -f commit_id=.. -f path=.. -F line=.. -f side=RIGHT -f body=..`로 달아도 된다(여러 개 — 여전히 뭉치지 않음). 삭제된 줄이면 `side=LEFT`. 단 review 일괄이 1순위.

### Step 5: 최종 판정

- **P1/P2 = 0** → `event=APPROVE`로 게시(또는 별도 `gh pr review "$PR" --approve --body "..."`). 총평에 "큰 문제 없음, approve".
- **P1/P2 ≥ 1** → `event=COMMENT`(위). request-changes 아님 — 사용자 규약은 comment.

게시 후 사용자에게 한국어로: PR 링크, P1~P5 카운트, 판정(approve/comment), 게시한 inline comment 수, 충돌/판단 필요 항목. 기술 식별자(path:line, 함수명)는 verbatim.

## 인자

- `$ARG` 있음 → PR 번호 또는 URL.
- 없음 → 현재 브랜치의 PR(`gh pr view`)로 추론. 없으면 사용자에게 질문.

## 주의

- read-only가 아님 — 실제로 GitHub에 리뷰를 게시한다. 게시 전 추합 결과를 사용자에게 먼저 보여주고 진행해도 되는지 한 번 확인하는 게 안전(특히 approve).
- 본인 PR이어도 적대적 자세 유지.
