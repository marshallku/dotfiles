# Interactions — 플러그인 레시피 카탈로그

덱의 모든 인터랙션은 **플러그인**이다. `deck-core.js`는 절대 수정하지 않는다 — 마크업에 `data-*` 속성을 달고,
마지막 `<script>` 블록에서 `deck.use({...})`로 등록한다. 이 분리 덕분에 인터랙션을 추가/제거해도 네비게이션은 깨지지 않는다.

## 플러그인 계약

```js
deck.use({
    name: "my-plugin",                       // 에러 로그 식별용, 필수
    init({ deck }) {},                       // 등록 시 1회 — DOM 준비 완료 상태
    onSlideChange({ deck, slide, index }) {},  // 슬라이드 전환마다 + 등록 직후 현재 슬라이드로 1회 (시작 슬라이드 보장)
    onStepReveal({ deck, element, index }) {}, // data-step 공개마다
});
```

- 훅은 전부 선택. 플러그인 에러는 core가 잡아서 로그만 남기고 발표는 계속된다.
- 상태가 필요하면 클로저에 가둔다. 전역 오염 금지.
- `onSlideChange`에서 "현재 슬라이드에 내 대상이 있나"를 검사하고 없으면 early return — 모든 레시피의 공통 골격.

## CDN 정책

기본은 zero-dependency(인라인 CSS/JS)다. 외부 스크립트는 아래처럼 **그 인터랙션을 실제로 쓸 때만** `<head>`가 아닌
`</body>` 직전에 추가하고, 오프라인 발표가 필요하다고 하면 라이브러리를 인라인으로 박아 넣는다.

| 용도 | 라이브러리 | CDN |
|---|---|---|
| 이미지 줌 | smooth-zoom | `https://cdn.jsdelivr.net/npm/smooth-zoom@latest/dist/zoom.min.js` |
| 코드 하이라이트 | highlight.js | `https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/highlight.min.js` |
| 복잡한 차트 | Chart.js | `https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js` |

---

## 레시피 1 — 이미지 줌 (smooth-zoom, 기본 탑재 권장)

이미지가 한 장이라도 있는 덱이면 기본으로 넣는다. Medium/Google Photos 스타일 클릭 확대.

마크업:

```html
<img class="zoomable" src="diagram.png" alt="아키텍처 다이어그램" />
```

스크립트 (`deck-core.js` 인라인 뒤):

```html
<script src="https://cdn.jsdelivr.net/npm/smooth-zoom@latest/dist/zoom.min.js"></script>
<script>
    deck.use({
        name: "image-zoom",
        init() {
            // background: "auto" — 이미지 평균색으로 오버레이를 깔아 어떤 테마와도 어울린다
            window.Zoom(".zoomable", { background: "auto" });
        },
    });
</script>
```

주의: 스테이지가 `transform: scale()`된 상태에서 줌이 뜨므로, 줌 오버레이가 스테이지 **바깥**(body 직속)에
생성되는 smooth-zoom 동작과 잘 맞는다. 커스텀 줌을 직접 구현할 때도 오버레이는 반드시 `.deck-stage` 밖에 그린다.

## 레시피 2 — 단계 공개 (core 내장)

플러그인조차 필요 없다. 순서대로 보여줄 요소에 `data-step`만 단다.

```html
<ul>
    <li data-step>첫 번째 포인트</li>
    <li data-step>두 번째 포인트</li>
</ul>
```

→/Space가 슬라이드 이동 전에 step을 하나씩 공개한다. 모션을 바꾸려면 테마 블록에서 `[data-step]`의
숨김 상태 transform만 오버라이드한다 (예: `transform: translateX(-24px)` 또는 `scale(0.95)`).

## 레시피 3 — 카운트업 숫자

지표 슬라이드에 진입할 때 숫자가 0에서 목표값까지 올라간다.

```html
<strong class="count-up" data-target="1200000">0</strong>
```

```js
deck.use({
    name: "count-up",
    onSlideChange({ slide }) {
        const counters = [...slide.querySelectorAll(".count-up")];

        if (counters.length === 0) return;

        const DURATION_MS = 1200;

        counters.forEach((el) => {
            const target = Number(el.dataset.target);
            const startedAt = performance.now();
            const tick = (now) => {
                const ratio = Math.min((now - startedAt) / DURATION_MS, 1);

                el.textContent = Math.round(target * ratio).toLocaleString();

                if (ratio < 1) requestAnimationFrame(tick);
            };

            requestAnimationFrame(tick);
        });
    },
});
```

## 레시피 4 — 코드 하이라이트

코드가 한두 블록이면 zero-dep: `<span>`에 테마 변수 색을 수동으로 입힌다 (토큰 4~5색이면 충분).
코드 슬라이드가 3장 이상이면 (Rule of Three) highlight.js CDN으로 전환:

```html
<pre><code class="language-typescript">const [error, data] = await to(promise);</code></pre>
<script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/highlight.min.js"></script>
<script>
    deck.use({
        name: "code-highlight",
        init() {
            window.hljs.highlightAll();
        },
    });
</script>
```

하이라이트 색은 highlight.js 기본 테마 CSS를 넣지 말고 `--deck-*` 변수 기반으로 `.hljs-*` 클래스 십여 개만 직접 칠한다 —
덱 테마와 따로 노는 코드 블록이 가장 흔한 촌스러움이다.

## 레시피 5 — 차트

기본은 **인라인 SVG + CSS 애니메이션** (bar는 `transform: scaleY`, line은 `stroke-dashoffset` 드로잉).
슬라이드 진입 시 재생하려면:

```js
deck.use({
    name: "chart-replay",
    onSlideChange({ slide }) {
        const charts = [...slide.querySelectorAll(".chart-animated")];

        charts.forEach((el) => {
            el.classList.remove("play");
            void el.offsetWidth; // reflow로 애니메이션 리셋
            el.classList.add("play");
        });
    },
});
```

인터랙티브 툴팁/실데이터가 필요할 때만 Chart.js CDN으로 올라간다.

## 레시피 6 — 라이브 데모 (iframe)

```html
<iframe class="live-demo" data-src="https://demo.example.com" title="라이브 데모"></iframe>
```

```js
deck.use({
    name: "lazy-iframe",
    onSlideChange({ slide }) {
        // 해당 슬라이드에 처음 도달했을 때만 로드 — 시작부터 무거운 데모가 발표를 잡아먹지 않게
        const frames = [...slide.querySelectorAll("iframe[data-src]")];

        frames.forEach((frame) => {
            frame.src = frame.dataset.src;
            frame.removeAttribute("data-src");
        });
    },
});
```

## 레시피 7 — 새 인터랙션 직접 만들기

위 어디에도 없는 요청이 오면:

1. 마크업에 선언적 `data-*` / 클래스 마킹을 정의한다 (동작 대상과 파라미터를 HTML에서 읽을 수 있게).
2. 플러그인 계약대로 작성한다 — `onSlideChange`에서 대상 탐색 + early return 골격을 그대로 쓴다.
3. `prefers-reduced-motion`을 존중해야 하는 모션이면 CSS 클래스 토글로 구현한다 (base CSS의 reduce 규칙이 공짜로 먹힌다).
4. 같은 패턴의 플러그인이 3개째 생기면 공통 헬퍼로 추출을 검토한다.
