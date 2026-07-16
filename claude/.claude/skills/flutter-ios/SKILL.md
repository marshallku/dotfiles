---
name: flutter-ios
description: Flutter iOS 앱을 시뮬레이터에 헤드리스로 빌드·실행·스크린샷·합성 탭·integration test 검증. **macOS 전용**(uname 게이트). 흰 화면(flutter run 필수)·키보드 미전달·TCC under tmux·AMFI hang 등 실증된 함정 회피 절차 내장. "iOS 시뮬 띄워/스크린샷/탭해봐/앱 화면 검증/flutter 빌드 확인" 류 요청 + playzy·book-and-record·dodamdodam 같은 Flutter 앱 작업에 사용.
user-invocable: true
allowed-tools: Bash,Read,Write,Edit
effort: medium
---

## 목적

Flutter iOS 앱을 GUI 조작 없이 CLI에서 **빌드 → 실행 → 스크린샷 → 합성 탭 → e2e 검증**까지 모는 절차. playzy·book-and-record·dodamdodam 등 Flutter 앱에서 반복되던 수동 멀티스텝(매번 `~/docs/topics/automation/ios-simulator-headless-control.md`를 보고 재현)을 한 스킬로 고정. 이 워크플로우는 **OS 분기를 심하게 타서**(AMFI 코드사이닝, TCC 접근성, Simulator 창 좌표) macOS에서만 의미가 있다 — Step 0에서 하드 게이트.

> **SSoT**: 함정의 상세/배경은 `~/docs/topics/automation/ios-simulator-headless-control.md`가 정본. 이 스킬은 그 절차의 **실행 가능한 요약**이다. 새 함정을 발견하면 그 노트의 `## Notes`에 append-only로 기록하고, 절차가 바뀌면 이 스킬도 갱신.

---

## Step 0 — 프리플라이트 (OS 게이트 + 툴체인). **반드시 먼저 실행.**

```bash
set -e
# --- OS 게이트: macOS 아니면 즉시 중단 ---
if [[ "$(uname)" != "Darwin" ]]; then
    echo "⛔ flutter-ios는 macOS 전용입니다 (iOS 시뮬레이터 = macOS+Xcode). 현재: $(uname). 중단." >&2
    exit 2
fi

ROOT="${1:-$PWD}"                     # 인자로 repo/앱 디렉터리, 없으면 cwd
# pubspec 자동 탐색: root 직하 → app/ 하위 → 한 단계 아래 (playzy는 app/, book-and-record는 root)
APP=""
for cand in "$ROOT" "$ROOT/app"; do
    [ -f "$cand/pubspec.yaml" ] && { APP="$cand"; break; }
done
if [ -z "$APP" ]; then
    APP=$(dirname "$(find "$ROOT" -maxdepth 2 -name pubspec.yaml -not -path '*/build/*' 2>/dev/null | head -1)" 2>/dev/null)
fi
[ -n "$APP" ] && [ -f "$APP/pubspec.yaml" ] || { echo "⛔ $ROOT 아래에서 pubspec.yaml을 못 찾음 — Flutter 앱 아님" >&2; exit 2; }
echo "📱 Flutter 앱: $APP"

# Xcode (sudo 없이 env override)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version >/dev/null 2>&1 || { echo "⛔ Xcode.app 없음/미설정" >&2; exit 2; }

# flutter — AMFI hang 감지 (dart가 _dyld_start에서 무한 hang하는 이 맥의 알려진 이슈)
if ! timeout 20 flutter --version >/dev/null 2>&1; then
    echo "⚠️ flutter --version 실패/hang — AMFI 코드사이닝 이슈 가능. Step 0b(AMFI 복구) 실행 필요." >&2
    exit 3
fi

# 시뮬레이터 디바이스
xcrun simctl list devices available | grep -q iPhone || { echo "⛔ 사용 가능한 iPhone 시뮬 없음" >&2; exit 2; }
echo "✅ 프리플라이트 통과. 부팅된 시뮬:"; xcrun simctl list devices booted | grep -i iphone || echo "  (없음 — Step 2에서 부팅)"

# 합성 탭이 필요할 때만 (선택)
command -v cliclick >/dev/null || echo "ℹ️ cliclick 없음 — 합성 탭 필요 시 'brew install cliclick'"
```

**게이트 exit code**: `2`=환경 불충족(비-macOS/앱아님/툴없음, 중단), `3`=AMFI 복구 필요(Step 0b). 게이트에 걸리면 사용자에게 사유 한 줄 보고하고 멈춘다.

### Step 0b — AMFI hang 복구 (게이트가 exit 3일 때만, sudo 불필요)

`dart`/`flutter`가 첫 실행 시 `_dyld_start`에서 무한 hang → cache의 Mach-O를 ad-hoc 재서명:
```bash
xattr -dr com.apple.quarantine /opt/homebrew/share/flutter
cd /opt/homebrew/share/flutter
while IFS= read -r f; do file "$f" | grep -q Mach-O && codesign --force --sign - "$f"; done \
  < <(find bin/cache -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \))
```
무서명은 arm64에서 SIGKILL(137) — **ad-hoc 서명이 정답**. 원상복구: `brew reinstall --cask flutter`.

---

## Step 1 — 빌드

```bash
cd "$APP"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
flutter build ios --simulator --debug        # → build/ios/iphonesimulator/Runner.app
```

## Step 2 — 실행 ⚠️ **디버그 빌드는 `flutter run` 필수 (흰 화면 함정)**

디버그 `.app`을 `simctl launch`로 단독 실행하면 **흰 화면**만 나온다(디버거 연결을 기대). 맥/시뮬 재시작으로도 안 고쳐짐 — 원인은 GPU가 아니라 "디버거 미연결".

```bash
SIM=$(xcrun simctl list devices available | grep -m1 iPhone | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator                            # 창 띄우기(합성 탭엔 필요)
# ✅ flutter run이 디버거를 붙여 렌더시킴. background로 유지.
cd "$APP" && flutter run -d "$SIM" --debug   # "A Dart VM Service ... is available at" = 렌더 완료
```
- `flutter run` 프로세스를 **살려둬야** 앱이 계속 렌더된다(죽이면 흰 화면).
- background로 띄우고(`run_in_background`), "Dart VM Service" 라인이 나올 때까지 기다린 뒤 다음 스텝.

## Step 3 — 스크린샷 (헤드리스, 창 위치 무관)

```bash
xcrun simctl io booted screenshot /tmp/sim.png   # 프레임버퍼 직접 캡처, 좌표 무관 항상 신뢰
```
캡처 후 Read로 이미지를 보고 레이아웃/상태를 눈으로 검증한다.

## Step 4 — 합성 탭/클릭 (cliclick + Quartz). 시각 플로우 구동용.

`simctl`엔 tap 명령이 없고 `idb`는 아카이브됨. **cliclick(자체 접근성 권한) + Quartz(권한 불필요, 창 bounds 읽기)** 조합이 tmux 하에서도 유일하게 안정적. 아래 스니펫을 `/tmp`에 쓰고 실행:

```python
# /tmp/sim_tap.py  — 사용: python3 /tmp/sim_tap.py <dx> <dy> [DW DH]
import Quartz, subprocess, time, sys
DW, DH = (float(sys.argv[3]), float(sys.argv[4])) if len(sys.argv) > 4 else (402.0, 874.0)  # iPhone17=402x874pt
def frame():
    wl = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
    s = [w for w in wl if 'Simulator' in w.get('kCGWindowOwnerName','') and w['kCGWindowBounds']['Height']>400]
    b = s[0]['kCGWindowBounds']; return b['X'], b['Y'], b['Width'], b['Height']
X, Y, W, H = frame()                          # ⚠️ 클릭 직전, 같은 스크립트 안에서 읽어라(창이 움직임)
tb = 28.0; scale = min(W/DW, (H-tb)/DH)        # letterbox fit, Simulator 타이틀바 ~28pt
ox = X + (W-DW*scale)/2; oy = Y + tb + ((H-tb)-DH*scale)/2
CC = "/opt/homebrew/bin/cliclick"
subprocess.run([CC, f"c:{int(X+W/2)},{int(Y+14)}"]); time.sleep(0.4)   # 타이틀바 클릭해 focus 먼저
dx, dy = float(sys.argv[1]), float(sys.argv[2])
subprocess.run([CC, f"c:{int(ox+dx*scale)},{int(oy+dy*scale)}"])       # 목표 탭(디바이스 pt)
```
```bash
brew install cliclick 2>/dev/null; python3 -m pip install --user --break-system-packages pyobjc-framework-Quartz 2>/dev/null
python3 /tmp/sim_tap.py 201 764               # 디바이스 pt. 좌표는 screenshot_px / 3
```
**3대 함정**: (1) cliclick 자체 Accessibility 권한 필요 — 없으면 조용히 무시됨(시스템 설정→손쉬운 사용에서 `/opt/homebrew/bin/cliclick` 켜기). (2) 창이 read마다 움직임 → 위치는 **클릭 직전 같은 스크립트에서** 읽기. (3) 클릭 전 타이틀바 클릭으로 focus.

## Step 5 — 텍스트 입력 & 행동 검증 ⛔ 합성 키보드는 **안 됨** → integration test로

cliclick 키 이벤트/`Cmd+V`는 Flutter 텍스트 필드에 **전달 안 됨**(한글은 아예 불가). `defaults`로 shared_preferences 시딩도 실패. 텍스트가 필요한 플로우는 **on-device integration test**가 유일한 신뢰 경로 — `tester.enterText`가 문제없이 됨:

```bash
# integration_test/app_journey_test.dart 에 전체 여정(tap/enterText/expect) 작성 후:
cd "$APP" && flutter test integration_test/app_journey_test.dart -d "$SIM"
```
- tall 디바이스: 하단 버튼은 `await tester.scrollUntilVisible(find.text('저장하기'), 300, scrollable: find.byType(Scrollable).first)` 후 tap.
- **역할 분담**: 행동 pass/fail은 §5 e2e로, 시각 스크린샷은 §3+§4(탭 구동) 또는 web 빌드 캡처로 나눠서.

## Step 6 — (선택) 서명된 ipa 무인 빌드 — fastlane + App Store Connect API

book-and-record 패턴. `fastlane/Fastfile`에 App Store Connect API 키(`~/.appstoreconnect/private_keys/AuthKey_*.p8`)로 번들ID 등록 + 프로파일 생성 + 서명 ipa를 완전 무인으로:
```bash
cd "$APP" && bundle exec fastlane ios build_ipa      # spaceship ConnectAPI로 콘솔 수동 단계 제거
```
콘솔 UI 없이 제출까지 자동화하려는 경우에만. 존재하는 레인은 `fastlane/Fastfile` 확인.

---

## 완료 보고

무엇을 검증했는지 명시: 빌드 성공 여부, 어느 화면을 스크린샷으로 확인, e2e pass/fail. 시각 캡처는 `docs/verification/`(playzy 관례)에 저장하고 재현 커맨드를 함께 남기면 다음 검증이 싸진다.

## 주의 / 범위

- **macOS 전용**. Step 0 게이트가 비-macOS를 exit 2로 막는다 — 우회하지 말 것(Linux엔 iOS 시뮬 자체가 없음).
- macOS **데스크톱** 타깃(book-and-record `macos/`)은 별개: `flutter run -d macos`로 직접 렌더되며 이 시뮬 함정들이 없다. 이 스킬은 iOS 시뮬 전용.
- Android는 이 스킬 범위 밖(`flutter run -d emulator-*` + `adb`로 별도). 필요하면 확장.
- 새 함정/해결책은 `~/docs/.../ios-simulator-headless-control.md`의 `## Notes`에 먼저 기록.
