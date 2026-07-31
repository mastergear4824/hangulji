#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-sim.sh
xcrun simctl bootstatus "iPhone 17" -b
xcrun simctl install "iPhone 17" build/Build/Products/Debug-iphonesimulator/HanguljiApp.app
open -a Simulator
xcrun simctl launch "iPhone 17" com.mastergear.hangulji-ios || true
echo "설치 완료. 시뮬레이터 설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → 한글지"
