#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Hangulji.xcodeproj -scheme HanguljiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=17.0 build | tail -5
echo "built: build/Build/Products/Debug-iphonesimulator/HanguljiApp.app"
