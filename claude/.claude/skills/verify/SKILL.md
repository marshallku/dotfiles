---
name: verify
description: 프론트엔드 시각 검증 — 브라우저 스크린샷 + 비전 분석
user-invocable: true
arguments: <URL 또는 검증 대상 설명>
argument-hint: http://localhost:3000 또는 "로그인 페이지 확인"
allowed-tools: Bash,Read,Glob,Grep,mcp__browser-control__tab_list,mcp__browser-control__tab_open,mcp__browser-control__tab_navigate,mcp__browser-control__tab_close,mcp__browser-control__screenshot,mcp__browser-control__screenshot_element,mcp__browser-control__screenshot_diff,mcp__browser-control__get_html,mcp__browser-control__get_text,mcp__browser-control__get_accessibility_tree,mcp__browser-control__click_element,mcp__browser-control__type_text,mcp__browser-control__scroll_page,mcp__browser-control__press_key,mcp__browser-control__execute_js,mcp__browser-control__wait_for_selector,mcp__browser-control__wait_for_navigation,mcp__browser-control__get_console_logs,mcp__browser-control__get_page_errors,mcp__browser-control__annotate_page,mcp__browser-control__get_page_metrics
---

# Frontend Visual Verification

브라우저를 통해 프론트엔드 결과물을 시각적으로 검증한다.

## 전제 조건

- browser-control MCP 서버가 등록되어 있어야 한다
- 브라우저에 browser-control 익스텐션이 설치되어 있어야 한다
- 브라우저가 열려 있어야 한다

## 워크플로우

### 1. 페이지 접근

- URL이 주어지면 `tab_navigate`로 이동
- 설명만 주어지면 프로젝트 컨텍스트에서 URL 추론 (package.json의 dev 서버 포트 등)
- 이미 열린 탭이 있으면 `tab_list`로 확인 후 재사용

### 2. 전체 스크린샷

- `screenshot`으로 현재 화면 캡처
- 캡처된 이미지를 비전으로 분석:
  - 레이아웃이 깨진 곳은 없는가
  - 텍스트가 잘리거나 겹치는 곳은 없는가
  - 빈 영역이나 로딩 실패한 요소는 없는가
  - 전반적인 시각적 품질

### 3. 콘솔 에러 확인

- `get_console_logs`로 콘솔 출력 확인
- `get_page_errors`로 JS 에러 확인
- 에러가 있으면 코드와 대조하여 원인 분석

### 4. 반응형 검증 (요청 시)

3개 breakpoint에서 스크린샷 비교:

```javascript
// execute_js로 뷰포트 리사이즈
window.resizeTo(375, 812); // Mobile
window.resizeTo(768, 1024); // Tablet
window.resizeTo(1440, 900); // Desktop
```

각 breakpoint에서 `screenshot` 촬영 후 비교 분석.

### 5. 레퍼런스 비교 (선택)

- `.claude/screenshots/` 디렉토리에 레퍼런스 이미지가 있으면 `screenshot_diff`로 비교
- diff percentage 보고
- 의도된 변경과 의도치 않은 변경 구분

### 6. 인터랙션 테스트 (요청 시)

- `annotate_page`로 인터랙티브 요소에 번호 표시
- `click_element`, `type_text`로 주요 인터랙션 테스트
- 폼 제출, 네비게이션, 모달 등 확인

## 보고 형식

```
## 검증 결과

### 시각적 상태
- [ ] 레이아웃 정상
- [ ] 텍스트 렌더링 정상
- [ ] 이미지/미디어 로드 정상
- [ ] 반응형 정상 (확인한 경우)

### 콘솔
- 에러: N개
- 경고: N개

### 발견된 이슈
1. (있으면 기술)

### 스크린샷
(캡처한 스크린샷 첨부)
```

## 주의사항

- 로컬 개발 서버가 실행 중인지 먼저 확인
- SPA의 경우 네비게이션 후 `wait_for_selector`로 렌더링 완료 대기
- 인증이 필요한 페이지는 먼저 로그인 처리
