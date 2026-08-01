#!/bin/bash
# HanguljiEngine .so 크로스컴파일 + Swift 런타임 .so + 사전 assets 배치.
#
# 사용: android/scripts/build-engine.sh            (기본 ABIS="arm64-v8a x86_64", release)
#       ABIS=arm64-v8a android/scripts/build-engine.sh
#       BUILD_CONFIG=debug android/scripts/build-engine.sh
#
# 전제: swift.org 툴체인 필요 — Xcode 내장 툴체인은 Swift SDK 크로스컴파일을 지원하지
# 않고, 크로스컴파일용 Android SDK(artifactbundle)는 자신을 만든 툴체인과 patch 버전까지
# 정확히 일치해야 한다("module compiled with Swift 6.2 cannot be imported by the Swift
# 6.2.4 compiler" — 6.2.4+6.2 SDK 조합으로 실측). 그래서 아래 버전들은 세트로 고정한다.
#
# 버전 근거 (2026-08 스파이크에서 실측·검증):
#   - 엔진 저장소 자체 CI(.github/workflows/swift.yml android-build 잡)는 Swift 6.1 +
#     finagolfin/swift-android-sdk 6.1(android-24)로 x86_64·aarch64·armv7을 빌드한다.
#   - 이 호스트(Xcode 26.5 / MacOSX26.5.sdk)에서는 Swift 6.1.x 툴체인이 매니페스트
#     컴파일부터 실패한다(구식 clang 내장 헤더 vs 26.5 SDK modulemap —
#     "found_incompatible_headers__check_search_paths"). finagolfin 최신 릴리스인
#     Swift 6.2(=6.2.0)가 이 호스트에서 동작하는 최소 버전이라 6.2.0으로 올려 고정.
#   - swift.org 공식 Android SDK는 아직 릴리스가 없다(6.3.3까지 확인, URL 404).
#     공식 URL을 먼저 시도하고 finagolfin으로 폴백한다.
#
# release 모드 주의: Swift 6.2.0(+assertions 릴리스 툴체인)은 swift-tokenizers의
# Trie/map 특수화를 -O로 컴파일할 때 SIL verifier 단언으로 크래시한다(Android 타깃
# 실측; OwnershipModelEliminator 직전 verify 단계). 해당 코드는 Zenzai(EfficientNGram)
# 전용 경로로 hangulji 변환 경로에서는 실행되지 않으며, 엔진 업스트림 CI는 Android를
# debug로만 빌드해서 이 버그를 본 적이 없다. 여기서는 -Xfrontend -sil-verify-none으로
# verifier만 끄고 릴리스 빌드한다(assertions 없는 프로덕션 툴체인과 동일한 lowering).
# 6.2보다 새 툴체인+SDK 세트가 나오면 이 플래그부터 제거하고 재검증할 것.
set -euo pipefail
cd "$(dirname "$0")/../engine"

SWIFT_VERSION="${SWIFT_VERSION:-6.2.0}"       # swiftly 표기 (6.2.0 → 툴체인 디렉터리 swift-6.2-RELEASE)
SDK_TAG="${SDK_TAG:-6.2}"                     # finagolfin 릴리스 태그 / artifactbundle 파일명 버전
SDK_CHECKSUM="${SDK_CHECKSUM:-c26ebfd4e32c0ca1beabcc45729b62042da57ee76d7d043f63f2235da90dc491}"
ANDROID_API="${ANDROID_API:-24}"
ABIS="${ABIS:-arm64-v8a x86_64}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
SDK_ID="swift-${SDK_TAG}-RELEASE-android-${ANDROID_API}-0.1"
CACHE="$HOME/.cache/hangulji-swift-android"
JNILIBS="$(cd .. && pwd)/app/src/main/jniLibs"
ASSETS="$(cd .. && pwd)/app/src/main/assets/azooKey_dictionary"

# 1) swift.org 툴체인 (swiftly 관리)
if ! command -v swiftly >/dev/null 2>&1 && [ ! -x "$HOME/.swiftly/bin/swiftly" ]; then
  echo "swiftly 미설치. 설치:" >&2
  echo "  curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg" >&2
  echo "  installer -pkg swiftly.pkg -target CurrentUserHomeDirectory" >&2
  echo "  ~/.swiftly/bin/swiftly init --assume-yes --skip-install --no-modify-profile" >&2
  exit 1
fi
SWIFTLY="$(command -v swiftly || echo "$HOME/.swiftly/bin/swiftly")"

# swiftly 버전 표기 → 툴체인 디렉터리명 (6.2.0 → swift-6.2-RELEASE, 6.2.1 → swift-6.2.1-RELEASE)
TOOLCHAIN_VER="${SWIFT_VERSION%.0}"
TOOLCHAIN="$HOME/Library/Developer/Toolchains/swift-${TOOLCHAIN_VER}-RELEASE.xctoolchain"
if [ ! -x "$TOOLCHAIN/usr/bin/swift" ]; then
  # 주의: `swiftly use`는 저장소에 .swift-version 파일을 만들므로 install만 한다.
  "$SWIFTLY" install "$SWIFT_VERSION"
fi
SWIFT_BIN="$TOOLCHAIN/usr/bin/swift"
"$SWIFT_BIN" --version | head -1

# 2) Swift Android SDK artifactbundle (로컬 파일 설치 — 체크섬은 다운로드 후 검증)
if ! "$SWIFT_BIN" sdk list 2>/dev/null | grep -q "android-${ANDROID_API}"; then
  mkdir -p "$CACHE"
  BUNDLE="$CACHE/${SDK_ID}.artifactbundle.tar.gz"
  if [ ! -f "$BUNDLE" ]; then
    # 공식(swift.org) 우선 — 2026-08 현재 미존재(404) — 엔진 CI가 쓰는 finagolfin 폴백.
    curl -fL -o "$BUNDLE" \
      "https://download.swift.org/swift-${SDK_TAG}-release/android/swift-${SDK_TAG}-RELEASE/${SDK_ID}.artifactbundle.tar.gz" \
    || curl -fL -o "$BUNDLE" \
      "https://github.com/finagolfin/swift-android-sdk/releases/download/${SDK_TAG}/swift-${SDK_TAG}-RELEASE-android-${ANDROID_API}-0.1.artifactbundle.tar.gz"
  fi
  echo "${SDK_CHECKSUM}  ${BUNDLE}" | shasum -a 256 -c - >/dev/null
  "$SWIFT_BIN" sdk install "$BUNDLE"
fi
"$SWIFT_BIN" sdk list

# release에서만 SIL verifier 우회 (파일 상단 주석 참조)
EXTRA_FLAGS=()
if [ "$BUILD_CONFIG" = "release" ]; then
  EXTRA_FLAGS=(-Xswiftc -Xfrontend -Xswiftc -sil-verify-none)
fi

# jniLibs에 배치할 런타임 .so 최소 집합: libHanguljiEngine.so의 DT_NEEDED 전이 폐쇄.
# (엔진 저장소 CI는 sysroot의 lib*.so 전부 복사 후 libc/libdl/liblog/libm 제외 —
#  거기엔 XCTest·curl 등 불필요 라이브러리가 섞이므로 여기서는 폐쇄 계산으로 좁힌다.
#  시스템 제공 libc/libm/libdl/liblog/libandroid/libz는 Android가 제공하므로 제외.)
copy_runtime_closure() {
  local seed="$1" syslib="$2" dest="$3"
  "$TOOLCHAIN/usr/bin/llvm-objdump" --version >/dev/null
  python3 - "$TOOLCHAIN/usr/bin/llvm-objdump" "$syslib" "$seed" "$dest" <<'PY'
import os, shutil, subprocess, sys
objdump, syslib, seed, dest = sys.argv[1:5]
system = {"libc.so", "libm.so", "libdl.so", "liblog.so", "libandroid.so", "libz.so"}
def needed(path):
    out = subprocess.run([objdump, "-p", path], capture_output=True, text=True, check=True).stdout
    return [line.split()[1] for line in out.splitlines() if "NEEDED" in line]
todo, seen = needed(seed), set()
while todo:
    name = todo.pop()
    if name in seen or name in system:
        continue
    seen.add(name)
    path = os.path.join(syslib, name)
    if not os.path.exists(path):
        sys.exit(f"sysroot에 없는 런타임 라이브러리: {name}")
    todo += needed(path)
for name in sorted(seen):
    shutil.copy2(os.path.join(syslib, name), dest)
print(f"runtime libs: {len(seen)}")
PY
}

# 3) ABI별 크로스컴파일 + 런타임 .so 복사
for ABI in $ABIS; do
  case "$ABI" in
    arm64-v8a) ARCH=aarch64 ;;
    x86_64)    ARCH=x86_64 ;;
    *) echo "지원하지 않는 ABI: $ABI" >&2; exit 1 ;;
  esac
  TRIPLE="${ARCH}-unknown-linux-android${ANDROID_API}"
  echo "== build $TRIPLE ($BUILD_CONFIG) =="
  "$SWIFT_BIN" build -c "$BUILD_CONFIG" --swift-sdk "$TRIPLE" --product HanguljiEngine "${EXTRA_FLAGS[@]}"

  DEST="$JNILIBS/$ABI"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cp ".build/$TRIPLE/$BUILD_CONFIG/libHanguljiEngine.so" "$DEST/"

  # Swift 런타임 — 6.2 SDK sysroot 레이아웃: usr/lib/<arch>-linux-android/lib*.so
  # (6.1 시절 CI 레시피의 <api> 하위 디렉터리에는 CRT 스텁만 있다)
  # (find는 존재하지 않는 검색 경로에서 비0으로 끝난다 — pipefail 대비 || true)
  SYSROOT_LIBS=$({ find "$HOME/Library/org.swift.swiftpm/swift-sdks" "$HOME/.config/swiftpm/swift-sdks" \
    -type d -path "*${SDK_ID}*" -path "*sysroot/usr/lib/${ARCH}-linux-android" 2>/dev/null || true; } | head -1)
  if [ -z "$SYSROOT_LIBS" ]; then
    echo "런타임 .so 디렉터리를 찾지 못함 — SDK 번들 내부 구조를 확인할 것:" >&2
    find "$HOME/Library/org.swift.swiftpm/swift-sdks" -maxdepth 4 -type d 2>/dev/null >&2
    exit 1
  fi
  copy_runtime_closure "$DEST/libHanguljiEngine.so" "$SYSROOT_LIBS" "$DEST"
  ls "$DEST" | head -20
done

# 4) 사전 → assets (SwiftPM 체크아웃의 서브모듈에서 — 35MB)
DICT_SRC=".build/checkouts/AzooKeyKanaKanjiConverter/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary"
[ -d "$DICT_SRC" ] || { echo "사전 디렉터리 없음: $DICT_SRC" >&2; exit 1; }
mkdir -p "$ASSETS"
rsync -a --delete "$DICT_SRC/" "$ASSETS/"
echo "assets: $(du -sh "$ASSETS" | cut -f1), jniLibs: $(du -sh "$JNILIBS" | cut -f1)"
echo "build-engine OK"
