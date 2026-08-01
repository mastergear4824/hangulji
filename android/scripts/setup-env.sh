#!/bin/bash
# JDK 17+ / cmdline-tools / SDK 패키지 / AVD 'hangulji' / gradle wrapper 를 멱등으로 준비한다.
set -euo pipefail
cd "$(dirname "$0")/.."
# JAVA_HOME/ANDROID_HOME을 여기서 먼저 확정해야 아래 sdkmanager/avdmanager 호출이
# jenv 기본 java(11)가 아니라 17을 사용한다.
source scripts/env.sh

# 1) JDK 17+ (없으면 temurin)
if ! /usr/libexec/java_home -v 17 &>/dev/null && ! /usr/libexec/java_home -v 21 &>/dev/null; then
  brew install --cask temurin@17
fi

# 2) cmdline-tools (sdkmanager/avdmanager) — 기존 SDK 디렉터리에 설치
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  BREW_SM=/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager
  [ -x "$BREW_SM" ] || brew install --cask android-commandlinetools
  # brew 설치본으로 SDK 루트에 자기 자신을 복제 → 이후 PATH는 SDK 루트만 쓴다
  yes | "$BREW_SM" --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true
  "$BREW_SM" --sdk_root="$ANDROID_HOME" "cmdline-tools;latest"
fi
yes | "$SDKMANAGER" --licenses >/dev/null || true

# 3) SDK 패키지 (이미 있으면 no-op)
"$SDKMANAGER" \
  "platform-tools" "platforms;android-35" "build-tools;35.0.1" "emulator" \
  "system-images;android-35;google_apis;arm64-v8a" \
  "ndk;27.2.12479018" "cmake;3.22.1"

# 4) 전용 AVD
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
if ! "$AVDMANAGER" list avd 2>/dev/null | grep -q 'Name: hangulji$'; then
  echo no | "$AVDMANAGER" create avd -n hangulji \
    -k "system-images;android-35;google_apis;arm64-v8a" -d "medium_phone"
fi

# 5) gradle wrapper (1회 — 이후 ./gradlew만 사용)
# 참고: brew의 기본 'gradle' 포뮬러는 9.x라 AGP 8.11.1과 호환되지 않아
# wrapper 생성을 위한 프로젝트 평가 자체가 실패한다. keg-only 'gradle@8'
# (8.14.x)로 부트스트랩하고, 이후 ./gradlew는 gradle-wrapper.properties에
# 명시된 정확히 8.14.2를 받는다.
if [ ! -x ./gradlew ]; then
  GRADLE_BOOTSTRAP="$(brew --prefix gradle@8 2>/dev/null || true)/bin/gradle"
  if [ ! -x "$GRADLE_BOOTSTRAP" ]; then
    brew install gradle@8
    GRADLE_BOOTSTRAP="$(brew --prefix gradle@8)/bin/gradle"
  fi
  source scripts/env.sh
  "$GRADLE_BOOTSTRAP" wrapper --gradle-version 8.14.2
fi

source scripts/env.sh
echo "== 검증 =="
java -version 2>&1 | head -1
"$SDKMANAGER" --version
adb --version | head -1
"$ANDROID_HOME/emulator/emulator" -version | head -1
"$AVDMANAGER" list avd | grep -A1 'Name: hangulji'
echo "setup-env OK"
