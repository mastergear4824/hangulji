#!/bin/bash
# macos/scripts/build-app.sh — swift build + .app 번들 조립 + ad-hoc 서명
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Hangulji.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Hangulji "$APP/Contents/MacOS/"
cp AppBundle/Info.plist "$APP/Contents/"
cp AppBundle/main.tiff "$APP/Contents/Resources/"

# SPM 리소스 번들 (변환 사전 등) — Bundle.module이 Contents/Resources에서 찾는다
# 주의: .build/release는 .build/arm64-apple-macosx/release로의 심볼릭 링크다.
# find는 기본(-P)으로 커맨드라인에 준 심볼릭 링크를 따라가지 않아 -maxdepth 1이
# 링크 자체에서 멈추고 번들을 하나도 못 찾는다 (조용히 실패 — 확인 필요).
# -L로 심볼릭 링크를 따라가게 해야 실제로 하위 항목이 탐색된다.
find -L .build/release -maxdepth 1 -name '*.bundle' -print -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --deep --sign - "$APP"
echo "built: $APP"
