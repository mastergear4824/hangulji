#!/bin/bash
# scripts/install-dev.sh — 개인용 설치 + 프로세스 재시작
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST="$HOME/Library/Input Methods/Hangulji.app"
rm -rf "$DEST"
cp -R build/Hangulji.app "$DEST"
killall Hangulji 2>/dev/null || true
echo "installed: $DEST"
echo "시스템 설정 > 키보드 > 입력 소스 > '+' > 일본어에서 Hangulji(한글지) 추가."
echo "목록에 안 보이면 로그아웃/로그인 후 다시 확인."
