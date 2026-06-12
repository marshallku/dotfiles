# Styles — 프리셋 3종

테마는 `deck-base.css` 뒤의 별도 `<style>` 블록에 들어간다. 구조는 항상 같다:
`:root`의 `--deck-*` 변수 → 폰트 로드 → 슬라이드 공통 타이포 → 레이아웃 유틸 클래스.

공통 원칙:

- **한국어 본문이 깨지지 않는 폰트가 1순위.** 영문 디스플레이 폰트를 쓰더라도 본문 fallback에 Pretendard를 항상 끼운다.
- 시스템 기본 폰트(Arial, 맑은 고딕 그대로)나 Inter+보라 그라데이션 같은 "AI 기본값" 조합은 금지. 프리셋을 베이스로 하되 콘텐츠 주제에 맞게 색·폰트를 한 번은 비튼다.
- 변수만 갈아끼우면 테마가 통째로 바뀌도록, 슬라이드 마크업에는 색상/폰트 하드코딩을 하지 않는다.

폰트 로드 (공통):

```html
<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin />
<link
    rel="stylesheet"
    href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/variable/pretendardvariable-dynamic-subset.min.css"
/>
```

---

## 1. Terminal — 개발자 발표 기본값

다크 배경에 모노스페이스 악센트. 기술 발표, 아키텍처 리뷰, 사내 데모.

```css
:root {
    --deck-backdrop: #0a0e14;
    --deck-surface: #11151c;
    --deck-ink: #e6e1cf;
    --deck-muted: #707a8c;
    --deck-accent: #39d98a;
    --deck-accent-alt: #ffb454;
    --deck-font-display: "JetBrains Mono", "D2Coding", "Pretendard Variable", monospace;
    --deck-font-body: "Pretendard Variable", sans-serif;
    --deck-font-code: "JetBrains Mono", "D2Coding", monospace;
}
```

- 모션: 커서 깜빡임, 타이핑 리빌, step은 `translateX` 슬라이드-인. 절제된 60~300ms.
- 배경: 미세한 스캔라인 또는 도트 그리드 (`background-image: radial-gradient(...)` 저대비).
- 제목 앞에 `$`/`>` 프롬프트 글리프, 슬라이드 번호는 `[03/12]` 형식.

## 2. Editorial — 밝은 종이 질감, 읽기용 덱

세리프 디스플레이 + 넉넉한 여백. 보고서형 공유 덱, 회고, 기획 발표.

```css
:root {
    --deck-backdrop: #e8e4dc;
    --deck-surface: #f5f2ec;
    --deck-ink: #1c1a17;
    --deck-muted: #8a8478;
    --deck-accent: #c2410c;
    --deck-accent-alt: #1e3a5f;
    --deck-font-display: "Noto Serif KR", "Pretendard Variable", serif;
    --deck-font-body: "Pretendard Variable", sans-serif;
    --deck-font-code: "JetBrains Mono", monospace;
}
```

- 모션: 페이드 + 미세한 상승만. 화려한 모션은 이 테마의 톤을 깬다.
- 큰 풀-블리드 따옴표, 헤어라인 구분선(1px), 본문 최대 60자 폭.
- 고밀도(읽기용) 콘텐츠와 가장 잘 맞는 프리셋.

## 3. Signal — 고대비 임팩트, 키노트용

거의-검정 배경에 한 가지 강렬한 시그널 컬러. 컨퍼런스 토크, 제품 공개, 한 슬라이드 한 메시지.

```css
:root {
    --deck-backdrop: #08080a;
    --deck-surface: #131318;
    --deck-ink: #fafafa;
    --deck-muted: #55555e;
    --deck-accent: #ff2e63;
    --deck-accent-alt: #08d9d6;
    --deck-font-display: "Pretendard Variable", sans-serif; /* weight 800~900으로 크게 */
    --deck-font-body: "Pretendard Variable", sans-serif;
    --deck-font-code: "JetBrains Mono", monospace;
}
```

- 타이포가 곧 비주얼: 제목 120~200px, weight 900, 자간 -0.03em. 악센트는 한 단어에만.
- 모션: 슬라이드 전환에 클립-리빌(`clip-path`), step은 큰 폭의 stagger. 임팩트 모먼트에 몰아 쓴다.
- 저밀도(발표자 주도) 전용. 읽기용 덱에 쓰면 안 된다.

---

## 프리셋 밖으로 나갈 때

사용자가 브랜드 컬러/레퍼런스 이미지를 주면 프리셋을 베이스로 변수만 교체한다.
완전히 새로운 무드를 원하면 `/frontend-design` 스킬의 원칙(독특한 타이포, 응집된 팔레트, 과감한 모션 1~2개)을 따르되,
변수 구조(`--deck-*`)와 고정 스테이지 규칙은 그대로 유지한다 — 그래야 인터랙션 레시피가 전부 호환된다.
