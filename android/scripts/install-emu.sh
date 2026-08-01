#!/bin/bash
# 에뮬레이터 부팅 → installDebug → 한글지 IME 활성화·선택 → 안내 앱 실행
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
AVD="${AVD:-hangulji}"

if ! adb get-state >/dev/null 2>&1; then
  nohup "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -netdelay none -netspeed full \
    >/dev/null 2>&1 &
fi
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'

./gradlew :app:installDebug

IME_ID="com.mastergear.hangulji/.keyboard.HanguljiInputMethodService"
adb shell ime enable "$IME_ID"
adb shell ime set "$IME_ID"
if ! adb shell ime list -s | grep -q "$IME_ID"; then echo "IME 등록 실패: $IME_ID" >&2; exit 1; fi
echo "IME 활성: $IME_ID"
adb shell am start -n com.mastergear.hangulji/.MainActivity
echo "앱의 테스트 입력창에서: xhdnzydn → 변환·스페이스 → 東京 탭"
