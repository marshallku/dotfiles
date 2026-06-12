---
name: slides
description: HTML 프레젠테이션 덱 생성 — 의존성 없는 단일 HTML 파일, 고정 16:9 스테이지, 플러그인 인터랙션 시스템(smooth-zoom 이미지 줌 등). "발표자료/PPT/슬라이드 만들어줘", "이 문서를 발표자료로", "덱에 인터랙션 추가해줘" 류 요청에 사용.
user-invocable: true
arguments: topic
argument-hint: [주제 또는 소스 파일 경로] (생략 시 대화로 파악)
---

## 무엇을 만드나

브라우저에서 바로 열리는 **단일 HTML 파일** 프레젠테이션. 빌드 없음, 서버 없음, 의존성 없음(인터랙션용 CDN만 선택적).
구조는 항상 동일하다:

- 고정 **1920×1080 스테이지**를 viewport에 통째로 scale — 어떤 화면에서도 레이아웃이 똑같다
- `assets/deck-core.js` — 네비게이션(키보드/스와이프/해시) + **플러그인 시스템**. 인터랙션은 전부 `deck.use()` 플러그인으로 붙는다
- `assets/deck-base.css` — 스테이지/슬라이드/step/print/reduced-motion 베이스

이 스킬의 정체성은 **인터랙션 확장이 쉬운 덱**이다. 정적 슬라이드 생성기가 아니라, 이미지 줌(smooth-zoom)·카운트업·
라이브 데모 같은 인터랙션을 코어 수정 없이 끼워 넣는 구조를 항상 유지한다.

## 절대 규칙

1. **단일 파일.** `deck-base.css`와 `deck-core.js`를 **전문 그대로 인라인**한다. 요약·생략·수정 금지. 테마/플러그인은 별도 블록으로 뒤에 붙인다.
2. **고정 스테이지.** 슬라이드 내부에 responsive breakpoint, `vw/vh` 단위, scroll 금지. 슬라이드 전환은 `.active`(visibility/opacity)로만 — `display: none` 금지.
3. **overflow 금지.** 모든 슬라이드는 1920×1080 안에 들어가야 한다. 내용이 넘치면 폰트를 줄이지 말고 슬라이드를 쪼갠다.
4. **인터랙션 = 플러그인.** `deck-core.js` 본문을 고치고 싶어지면 설계가 틀린 것이다. `references/interactions.md`의 계약을 따른다.
5. **코드 스타일.** 인라인 JS/CSS도 프로필 그대로: 4 spaces, double quotes, camelCase, early return, magic number는 UPPER_CASE 상수.
6. 작업물(워크플로우) 텍스트를 슬라이드에 렌더링하지 않는다 — "preview", "preset", 파일 경로, 템플릿 이름 등.

## Step 0 — 모드 감지

- **A. 새 덱**: 주제/내용 설명에서 시작
- **B. 변환**: 기존 자료(markdown, 문서, PPTX 텍스트 추출본)가 소스. 내용 구조를 먼저 요약해 확인받는다
- **C. 수정/인터랙션 추가**: 기존 덱 HTML이 있음. 베이스/코어 블록은 건드리지 않고 테마·슬라이드·플러그인 블록만 수정. 이 모드면 Step 1~2를 건너뛴다

## Step 1 — 내용 파악 (질문은 한 번에)

빠진 것만 한 번에 묻는다 (이미 답이 있으면 묻지 않는다):

1. **목적/청중** — 컨퍼런스 발표? 사내 공유? 보고?
2. **분량** — 슬라이드 수 또는 발표 시간
3. **밀도** — 발표자 주도(저밀도: 슬라이드당 1메시지, 큰 타이포) vs 읽기용(고밀도: 자기완결, 4~8개 불릿/카드). 이 선택이 레이아웃 전체를 결정한다
4. **자료** — 이미지/차트 데이터/코드 유무. 이미지가 있으면 smooth-zoom 줌을 기본 적용한다

## Step 2 — 스타일 결정

`references/styles.md`의 프리셋 3종(Terminal / Editorial / Signal)에서 출발한다.

- 주제·청중으로 충분히 판단되면 **하나를 추천하고 이유를 한 줄로** 말한 뒤 진행한다 (기술 발표 → Terminal, 보고/회고 → Editorial, 키노트 → Signal)
- 사용자가 고민하면 대표 슬라이드 1장짜리 미리보기 HTML 2~3개를 만들어 보여주고 고르게 한다
- 브랜드 컬러/레퍼런스가 있으면 프리셋 변수만 교체한다. 어느 쪽이든 콘텐츠에 맞게 최소 한 번은 프리셋을 비튼다 — 기본값 그대로는 금지

## Step 3 — 생성

출력 골격 (이 순서 고정):

```html
<!doctype html>
<html lang="ko">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{제목}</title>
        <!-- 폰트 (styles.md 참조) -->
        <style>/* 1. deck-base.css 전문 */</style>
        <style>/* 2. 테마: --deck-* 변수 + 타이포 + 레이아웃 유틸 */</style>
        <style>/* 3. 슬라이드별 커스텀 */</style>
    </head>
    <body>
        <main class="deck-stage">
            <section class="slide"><!-- 슬라이드 1 --></section>
            <!-- ... -->
        </main>
        <div class="deck-progress"><div class="deck-progress-bar"></div></div>
        <script>/* 4. deck-core.js 전문 */</script>
        <!-- 5. 인터랙션 CDN (쓸 때만) -->
        <script>/* 6. deck.use() 플러그인 등록 */</script>
    </body>
</html>
```

- 순차 공개가 필요한 요소에 `data-step` (core 내장, 플러그인 불필요)
- 이미지가 있으면 `interactions.md` 레시피 1(smooth-zoom)을 기본 탑재
- 그 외 인터랙션은 `references/interactions.md`에서 해당 레시피를 읽고 적용. 없는 인터랙션은 레시피 7(플러그인 계약)대로 새로 작성

## Step 4 — 검증 (생략 금지)

1. tabd로 파일을 열어 슬라이드별 스크린샷을 찍는다 (`#1`, `#2`, … 해시로 직접 이동 가능)
2. 확인: 콘텐츠 overflow 없음 / 콘솔 에러 없음 / `data-step` 동작 / 등록한 플러그인 동작(줌 클릭 등)
3. overflow 발견 시 폰트 축소가 아니라 **슬라이드 분할**로 고친다
4. tabd를 못 쓰는 환경이면 그 사실을 말하고 사용자에게 브라우저 확인을 요청한다

## Step 5 — 전달

- 파일 경로 + 조작법 한 줄: ←→/Space/스와이프 이동, `#n` 해시 점프, 인쇄(Ctrl+P)로 PDF 저장
- 어떤 인터랙션이 들어갔는지, 새 인터랙션을 추가하려면 어디(마지막 script 블록)에 플러그인을 붙이면 되는지 한 줄로 안내
