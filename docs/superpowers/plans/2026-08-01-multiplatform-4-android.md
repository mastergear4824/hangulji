# 멀티플랫폼 서브프로젝트 4: Android 키보드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 커스텀 키보드(InputMethodService) — 2벌식 한글 키로 가나 철자를 치면 조합 영역에 가나가 표시되고, 스페이스(변환)로 한자 후보를 골라 입력한다. 코어는 SPEC.md 기반 Kotlin 이디엄 포트(픽스처 conformance), 한자 엔진은 AzooKeyKanaKanjiConverter를 Swift Android SDK로 크로스컴파일한 `.so` + JNI.

**Architecture:** `android/`에 Gradle 단일 `:app` 모듈(`com.mastergear.hangulji`). ① 코어(Jamo/Keymap/JamoComposer/KanaMapper/HanguljiComposer)는 `spec/SPEC.md`+`mapping.tsv`(gen-kotlin 생성 테이블)로부터 Kotlin 포트, JVM 유닛테스트로 `spec/fixtures/*.json` 전체(45+8)를 통과해야 한다. ② 엔진은 `android/engine/`(SwiftPM 패키지)이 `@_cdecl` C 심 4함수를 노출하는 `libHanguljiEngine.so`로 크로스컴파일되고, 앱의 작은 C JNI 글루(`hangulji_jni.c`)가 이를 Kotlin `KanjiConverter.candidateList(reading): List<String>`로 잇는다. 사전은 assets→filesDir 1회 복사 후 경로 전달. ③ 셸은 iOS `KeyboardModel`과 동일 의미론의 Kotlin 상태머신 + Compose UI. 엔진 `.so`가 없어도 앱은 빌드·동작(변환 불가 시 가나 그대로 확정)하도록 그레이스풀 디그레이드 — CI가 크로스컴파일 없이 돌 수 있는 근거.

**Tech Stack:** Kotlin 2.2.0 / AGP 8.11.1 / Gradle 8.14.2(wrapper 커밋) / JDK 17 / compileSdk 35·minSdk 28 / Jetpack Compose(BOM 2025.05.00) — **플레인 View/XML 미사용(결정: iOS KeyboardView 구조 미러링·후보바/팝업 선언형 구현이 압도적으로 짧음)**. 엔진: swift.org 툴체인(swiftly) + Swift Android SDK artifactbundle, AzooKeyKanaKanjiConverter **exact 0.11.2**(core-swift Package.resolved와 동일 리비전), NDK 27.2.12479018 + CMake 3.22.1(JNI 글루만). 에뮬레이터: arm64-v8a(Apple Silicon 네이티브), CLI 전용(sdkmanager/avdmanager/gradle/adb — Android Studio 불요).

**Spec:** `docs/superpowers/specs/2026-07-31-hangulji-multiplatform-design.md` §5.3, §7(SP4 완료 정의), §8(리스크) + `spec/SPEC.md`(포팅 요구사항 전체) + `spec/mapping.tsv` + `spec/fixtures/*.json`

## Global Constraints

- **spec 파일 불가침**: `spec/mapping.tsv`·`spec/SPEC.md`·`spec/fixtures/*.json` 수정 금지. 이 계획에서 spec/에 추가되는 파일은 `spec/generators/gen-kotlin.swift` 하나뿐
- **테이블 상수는 생성물만**: `android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt`는 gen-kotlin.swift 산출물 — 수기 수정 금지, CI 최신성 검사(생성 후 diff 0) 대상
- **픽스처 = conformance 게이트**: kana.json 45케이스 + composition.json 8케이스 전부 그린이어야 코어 포트 완료 (러너는 개수 하드코딩 금지 — SPEC §6, 최소치 38/8만 검사)
- **엔진 버전 고정**: AzooKeyKanaKanjiConverter `exact("0.11.2")` — core-swift Package.resolved(0.11.2, rev 80b8204)와 동일. `android/engine/Package.resolved` 커밋
- **기존 코드 무수정**: `core-swift/`·`macos/`·`ios/`·`windows/` 변경 금지. 예외는 Task 9의 명시 범위(`.github/workflows/core.yml` 최신성 스텝에 gen-kotlin 1줄 추가, 루트 `README.md` Android 섹션)뿐
- **버전 핀**: Kotlin 2.2.0, AGP 8.11.1, Gradle 8.14.2, JDK 17(코레토 17 설치 확인됨 — jenv 기본이 11이므로 **모든 gradle 호출 전 `source android/scripts/env.sh` 필수**), compileSdk 35, targetSdk 35, minSdk 28, Compose BOM 2025.05.00, NDK 27.2.12479018, CMake 3.22.1
- **CLI 전용**: Android Studio 설치·사용 금지. 검증된 로컬 자산: `~/Library/Android/sdk`(platform-tools·platforms;android-35·build-tools 35.0.1·emulator 존재, cmdline-tools 부재 → setup-env.sh가 설치), AVD는 전용 `hangulji`(system-images;android-35;google_apis;arm64-v8a)를 새로 만든다
- **커밋 메시지에 Co-Authored-By 트레일러 금지**
- **매 태스크 종료 조건**: 해당 태스크 검증 명령 + `source android/scripts/env.sh && (cd android && ./gradlew :app:testDebugUnitTest)` 그린(Task 2부터) + 코어 회귀 `swift test --package-path core-swift` 통과
- **완료 정의(§7 SP4)**: 에뮬레이터에서 한글지 키보드로 토우쿄우(xhdnzydn) 입력 → 스페이스 → 東京 선택 입력 성공
- **엔진 스파이크 타임박스**: Task 5는 1일 타임박스. 초과 실패 시 BLOCKED 리포트(libmozc 권고) 작성하고 중단 — 폴백 상세 계획은 이 문서 범위 밖(Task 5 Step 7 프로토콜 참조)

## 2벌식 키 → 라틴 문자 (UI 버튼 정의의 유일한 근거 — core Keymap과 동일)

```
ㅂq ㅈw ㄷe ㄱr ㅅt ㅛy ㅕu ㅑi ㅐo ㅔp
ㅁa ㄴs ㅇd ㄹf ㅎg ㅗh ㅓj ㅏk ㅣl
ㅋz ㅌx ㅊc ㅍv ㅠb ㅜn ㅡm
시프트/롱프레스 변형: ㅃQ ㅉW ㄸE ㄲR ㅆT ㅒO ㅖP (그 외 키는 변형 없음)
```

## File Structure

```
spec/generators/gen-kotlin.swift        # mapping.tsv → KanaTable.kt (Task 2)
android/
├── settings.gradle.kts
├── build.gradle.kts                    # 루트 — 플러그인 버전 선언만
├── gradle.properties
├── gradle/wrapper/                     # 커밋 (gradle-wrapper.jar 포함)
├── gradlew, gradlew.bat
├── .gitignore
├── scripts/
│   ├── env.sh                          # JAVA_HOME/ANDROID_HOME/PATH — 모든 스크립트·수동 gradle의 전제
│   ├── setup-env.sh                    # JDK·cmdline-tools·SDK 패키지·AVD 멱등 설치/검증
│   ├── build-engine.sh                 # Swift 크로스컴파일 → jniLibs + 사전 → assets
│   └── install-emu.sh                  # 에뮬레이터 부팅 + installDebug + adb ime enable/set
├── engine/                             # SwiftPM 패키지 (Android 전용 .so)
│   ├── Package.swift
│   └── Sources/HanguljiEngine/Shim.swift   # @_cdecl C 심 4함수
└── app/
    ├── build.gradle.kts
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── res/xml/method.xml          # IME 선언
        │   ├── assets/azooKey_dictionary/  # build-engine.sh 산출 (커밋 안 함)
        │   ├── jniLibs/{arm64-v8a,x86_64}/ # build-engine.sh 산출 (커밋 안 함)
        │   ├── cpp/
        │   │   ├── CMakeLists.txt
        │   │   └── hangulji_jni.c          # JNI ↔ C ABI 글루 (~70줄)
        │   └── kotlin/com/mastergear/hangulji/
        │       ├── MainActivity.kt          # 설치 안내 + 테스트 입력창
        │       ├── core/Jamo.kt             # Consonant/Vowel/Jamo/Keymap (SPEC §1)
        │       ├── core/KanaTable.kt        # ★생성물 (gen-kotlin.swift)
        │       ├── core/JamoComposer.kt     # Syllable + automaton (SPEC §2)
        │       ├── core/KanaMapper.kt       # MappedSyllable + 매핑 (SPEC §3)
        │       ├── core/Katakana.kt         # String.toKatakana()
        │       ├── core/HanguljiComposer.kt # 토큰 스트림 파사드 (SPEC §5)
        │       ├── engine/KanjiConverter.kt # JNI 래퍼 + candidateList 계약
        │       ├── engine/DictionaryInstaller.kt  # assets → filesDir 1회 복사
        │       ├── keyboard/KeyboardModel.kt      # 상태머신 (iOS 동일 의미론)
        │       ├── keyboard/HanguljiInputMethodService.kt
        │       └── keyboard/KeyboardView.kt       # Compose 레이아웃 + 후보바 + 롱프레스 팝업
        ├── test/kotlin/com/mastergear/hangulji/
        │   ├── core/KeymapTest.kt
        │   ├── core/JamoComposerTest.kt
        │   ├── core/KanaMapperTest.kt
        │   ├── core/FixtureConformanceTest.kt     # 45+8 conformance 러너
        │   └── keyboard/KeyboardModelTest.kt      # iOS 14테스트 계약 + 엔진부재 폴백 1개
        └── androidTest/kotlin/com/mastergear/hangulji/
            └── EngineSmokeTest.kt          # 에뮬레이터: とうきょう→東京
.github/workflows/android.yml           # ubuntu: JVM 테스트 + assembleDebug(.so 없이)
```

---

### Task 1: 툴체인 부트스트랩 + Gradle 스캐폴드 — 빈 앱이 assembleDebug 된다

**Files:**
- Create: `android/scripts/env.sh`, `android/scripts/setup-env.sh`, `android/settings.gradle.kts`, `android/build.gradle.kts`, `android/gradle.properties`, `android/.gitignore`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/mastergear/hangulji/MainActivity.kt`, gradle wrapper 일체

**Interfaces:**
- Produces: `source android/scripts/env.sh` 후 `./gradlew :app:assembleDebug`가 성공하는 빌드 파이프라인, AVD `hangulji`. Task 2 이후 모든 태스크가 이 위에 소스를 얹는다.

- [ ] **Step 1: env.sh 작성** (`android/scripts/env.sh`)

```bash
# 모든 android 스크립트와 수동 gradle/adb 호출 전에 source 할 것.
# (jenv 기본 java가 11이라 JAVA_HOME 명시가 필수)
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null \
  || /usr/libexec/java_home -v 21 2>/dev/null)}"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

- [ ] **Step 2: setup-env.sh 작성** (`android/scripts/setup-env.sh`) — 멱등 설치/검증

```bash
#!/bin/bash
# JDK 17+ / cmdline-tools / SDK 패키지 / AVD 'hangulji' / gradle wrapper 를 멱등으로 준비한다.
set -euo pipefail
cd "$(dirname "$0")/.."
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

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
if [ ! -x ./gradlew ]; then
  command -v gradle >/dev/null || brew install gradle
  source scripts/env.sh
  gradle wrapper --gradle-version 8.14.2
fi

source scripts/env.sh
echo "== 검증 =="
java -version 2>&1 | head -1
"$SDKMANAGER" --version
adb --version | head -1
"$ANDROID_HOME/emulator/emulator" -version | head -1
"$AVDMANAGER" list avd | grep -A1 'Name: hangulji'
echo "setup-env OK"
```

`chmod +x android/scripts/*.sh`

- [ ] **Step 3: 실행·검증** — `./android/scripts/setup-env.sh` → 마지막 줄 `setup-env OK`, AVD `hangulji` 표시. (초회는 system image 다운로드로 수 분.)

- [ ] **Step 4: Gradle 스캐폴드 작성**

`android/settings.gradle.kts`:
```kotlin
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "hangulji-android"
include(":app")
```

`android/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.0" apply false
}
```

`android/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
```

`android/.gitignore`:
```
.gradle/
build/
local.properties
app/src/main/jniLibs/
app/src/main/assets/azooKey_dictionary/
app/.cxx/
```

`android/app/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.mastergear.hangulji"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mastergear.hangulji"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    sourceSets.getByName("main") { kotlin.srcDir("src/main/kotlin") }
    sourceSets.getByName("test") { kotlin.srcDir("src/test/kotlin") }
    sourceSets.getByName("androidTest") { kotlin.srcDir("src/androidTest/kotlin") }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.05.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.savedstate:savedstate-ktx:1.2.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.google.code.gson:gson:2.11.0")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

// conformance 러너가 spec/fixtures를 읽는다 — -DfixturesDir로 재지정 가능 (Task 4에서 소비)
tasks.withType<Test>().configureEach {
    systemProperty(
        "fixturesDir",
        System.getProperty("fixturesDir") ?: rootDir.resolve("../spec/fixtures").absolutePath
    )
}
```

`android/app/src/main/AndroidManifest.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="한글지"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <!-- IME 서비스는 Task 8에서 추가 -->
    </application>
</manifest>
```

`android/app/src/main/kotlin/com/mastergear/hangulji/MainActivity.kt` (스텁 — Task 8에서 본 구현):
```kotlin
package com.mastergear.hangulji

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Text("한글지 (구현 중)") } }
    }
}
```

- [ ] **Step 5: 빌드 검증**

Run: `source android/scripts/env.sh && (cd android && ./gradlew :app:assembleDebug)`
Expected: `BUILD SUCCESSFUL`, `android/app/build/outputs/apk/debug/app-debug.apk` 생성. 코어 회귀 `swift test --package-path core-swift` 통과.

- [ ] **Step 6: Commit**

```bash
git add android
git commit -m "feat(android): 툴체인 부트스트랩 스크립트 + Gradle 스캐폴드 (빈 앱 assembleDebug)"
```

---

### Task 2: Kotlin 자모 타입 + Keymap + gen-kotlin 생성기

**Files:**
- Create: `android/app/src/main/kotlin/com/mastergear/hangulji/core/Jamo.kt`, `android/app/src/test/kotlin/com/mastergear/hangulji/core/KeymapTest.kt`, `spec/generators/gen-kotlin.swift`, (생성) `android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt`

**Interfaces:**
- Consumes: `spec/SPEC.md` §1(키맵 33항목·대문자 폴백), §2.7(인덱스 표 — enum 선언 순서의 근거), `spec/mapping.tsv`
- Produces (Task 3~4가 소비):
  - `enum class Consonant(val char: Char)` — 유니코드 초성 순서 19개, `ordinal` = 초성 인덱스
  - `enum class Vowel(val char: Char)` — 유니코드 중성 순서 21개, `ordinal` = 중성 인덱스
  - `sealed interface Jamo { data class C(val consonant: Consonant); data class V(val vowel: Vowel) }`
  - `object Keymap { fun jamo(ch: Char): Jamo? }`
  - `object KanaTable { val body: List<Triple<Consonant, Vowel, String>>; val finals: List<Pair<Consonant, String>> }` (생성물)

- [ ] **Step 1: 실패하는 테스트 작성** (`android/app/src/test/kotlin/com/mastergear/hangulji/core/KeymapTest.kt`)

```kotlin
package com.mastergear.hangulji.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class KeymapTest {
    @Test
    fun lowercaseMappings() {
        assertEquals(Jamo.C(Consonant.G), Keymap.jamo('r'))
        assertEquals(Jamo.V(Vowel.A), Keymap.jamo('k'))
        assertEquals(Jamo.V(Vowel.EU), Keymap.jamo('m'))
    }

    @Test
    fun explicitUppercaseMappings() {
        assertEquals(Jamo.C(Consonant.GG), Keymap.jamo('R'))
        assertEquals(Jamo.C(Consonant.SS), Keymap.jamo('T'))
        assertEquals(Jamo.V(Vowel.YAE), Keymap.jamo('O'))
        assertEquals(Jamo.V(Vowel.YE), Keymap.jamo('P'))
    }

    @Test
    fun unassignedUppercaseFallsBackToLowercase() {   // SPEC §1.1
        assertEquals(Jamo.C(Consonant.M), Keymap.jamo('A'))
        assertEquals(Jamo.V(Vowel.YO), Keymap.jamo('Y'))
    }

    @Test
    fun nonJamoCharacters() {
        assertNull(Keymap.jamo('1'))
        assertNull(Keymap.jamo('-'))
        assertNull(Keymap.jamo(' '))
    }

    @Test
    fun ordinalsMatchUnicodeIndices() {   // SPEC §2.7 인덱스 표와 enum 선언 순서 일치 검증
        assertEquals(0, Consonant.G.ordinal)
        assertEquals(11, Consonant.NG.ordinal)
        assertEquals(18, Consonant.H.ordinal)
        assertEquals(0, Vowel.A.ordinal)
        assertEquals(9, Vowel.WA.ordinal)
        assertEquals(20, Vowel.I.ordinal)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `source android/scripts/env.sh && (cd android && ./gradlew :app:testDebugUnitTest)`
Expected: 컴파일 실패 (`Unresolved reference 'Keymap'`)

- [ ] **Step 3: Jamo.kt 구현** (`android/app/src/main/kotlin/com/mastergear/hangulji/core/Jamo.kt`)

```kotlin
package com.mastergear.hangulji.core

/** 초성(choseong) 유니코드 정규 순서로 선언 — ordinal이 곧 초성 인덱스 (SPEC §2.7) */
enum class Consonant(val char: Char) {
    G('ㄱ'), GG('ㄲ'), N('ㄴ'), D('ㄷ'), DD('ㄸ'), R('ㄹ'), M('ㅁ'),
    B('ㅂ'), BB('ㅃ'), S('ㅅ'), SS('ㅆ'), NG('ㅇ'), J('ㅈ'), JJ('ㅉ'),
    CH('ㅊ'), K('ㅋ'), T('ㅌ'), P('ㅍ'), H('ㅎ'),
}

/** 중성(jungseong) 유니코드 정규 순서로 선언 — ordinal이 곧 중성 인덱스 (SPEC §2.7) */
enum class Vowel(val char: Char) {
    A('ㅏ'), AE('ㅐ'), YA('ㅑ'), YAE('ㅒ'), EO('ㅓ'), E('ㅔ'),
    YEO('ㅕ'), YE('ㅖ'), O('ㅗ'), WA('ㅘ'), WAE('ㅙ'), OE('ㅚ'),
    YO('ㅛ'), U('ㅜ'), WO('ㅝ'), WE('ㅞ'), WI('ㅟ'), YU('ㅠ'),
    EU('ㅡ'), UI('ㅢ'), I('ㅣ'),
}

sealed interface Jamo {
    data class C(val consonant: Consonant) : Jamo
    data class V(val vowel: Vowel) : Jamo
}

/** 2벌식 키맵: 라틴 문자(하드웨어 자판) → 자모 (SPEC §1 — 33항목) */
object Keymap {
    private val table: Map<Char, Jamo> = mapOf(
        'q' to Jamo.C(Consonant.B), 'w' to Jamo.C(Consonant.J), 'e' to Jamo.C(Consonant.D),
        'r' to Jamo.C(Consonant.G), 't' to Jamo.C(Consonant.S),
        'y' to Jamo.V(Vowel.YO), 'u' to Jamo.V(Vowel.YEO), 'i' to Jamo.V(Vowel.YA),
        'o' to Jamo.V(Vowel.AE), 'p' to Jamo.V(Vowel.E),
        'a' to Jamo.C(Consonant.M), 's' to Jamo.C(Consonant.N), 'd' to Jamo.C(Consonant.NG),
        'f' to Jamo.C(Consonant.R), 'g' to Jamo.C(Consonant.H),
        'h' to Jamo.V(Vowel.O), 'j' to Jamo.V(Vowel.EO), 'k' to Jamo.V(Vowel.A),
        'l' to Jamo.V(Vowel.I),
        'z' to Jamo.C(Consonant.K), 'x' to Jamo.C(Consonant.T), 'c' to Jamo.C(Consonant.CH),
        'v' to Jamo.C(Consonant.P),
        'b' to Jamo.V(Vowel.YU), 'n' to Jamo.V(Vowel.U), 'm' to Jamo.V(Vowel.EU),
        'Q' to Jamo.C(Consonant.BB), 'W' to Jamo.C(Consonant.JJ), 'E' to Jamo.C(Consonant.DD),
        'R' to Jamo.C(Consonant.GG), 'T' to Jamo.C(Consonant.SS),
        'O' to Jamo.V(Vowel.YAE), 'P' to Jamo.V(Vowel.YE),
    )

    /** SPEC §1.1: 정확 일치 → 미배정 대문자는 소문자 폴백 → 그래도 없으면 null */
    fun jamo(ch: Char): Jamo? =
        table[ch] ?: if (ch.isUpperCase()) table[ch.lowercaseChar()] else null
}
```

- [ ] **Step 4: 테스트 통과 확인** — Step 2와 같은 명령, Expected: `BUILD SUCCESSFUL` (KeymapTest 5개 통과)

- [ ] **Step 5: gen-kotlin.swift 작성** (`spec/generators/gen-kotlin.swift` — gen-swift.swift 미러)

```swift
#!/usr/bin/env swift
// spec/mapping.tsv → android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt
// 사용: swift spec/generators/gen-kotlin.swift (저장소 루트에서)
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let tsvURL = root.appendingPathComponent("spec/mapping.tsv")
let outURL = root.appendingPathComponent(
    "android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt")

guard let tsv = try? String(contentsOf: tsvURL, encoding: .utf8) else {
    fatalError("spec/mapping.tsv 를 읽을 수 없음 — 저장소 루트에서 실행했는가?")
}

// 자모 문자 → Kotlin enum 케이스 이름 (Jamo.kt의 Consonant/Vowel 선언과 반드시 일치)
let consonantNames: [String: String] = [
    "ㄱ": "G", "ㄲ": "GG", "ㄴ": "N", "ㄷ": "D", "ㄸ": "DD", "ㄹ": "R", "ㅁ": "M",
    "ㅂ": "B", "ㅃ": "BB", "ㅅ": "S", "ㅆ": "SS", "ㅇ": "NG", "ㅈ": "J", "ㅉ": "JJ",
    "ㅊ": "CH", "ㅋ": "K", "ㅌ": "T", "ㅍ": "P", "ㅎ": "H",
]
let vowelNames: [String: String] = [
    "ㅏ": "A", "ㅐ": "AE", "ㅑ": "YA", "ㅒ": "YAE", "ㅓ": "EO", "ㅔ": "E",
    "ㅕ": "YEO", "ㅖ": "YE", "ㅗ": "O", "ㅘ": "WA", "ㅙ": "WAE", "ㅚ": "OE",
    "ㅛ": "YO", "ㅜ": "U", "ㅝ": "WO", "ㅞ": "WE", "ㅟ": "WI", "ㅠ": "YU",
    "ㅡ": "EU", "ㅢ": "UI", "ㅣ": "I",
]

var bodyLines: [String] = []
var finalLines: [String] = []
var seenKeys: Set<String> = []
for (lineIndex, rawLine) in tsv.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
    let line = String(rawLine)
    if line.hasPrefix("#") || line.isEmpty { continue }
    let cols = line.components(separatedBy: "\t")
    guard cols.count == 4 else { fatalError("잘못된 TSV 행: \(line)") }
    let key = "\(cols[0])\t\(cols[1])\t\(cols[2])"
    guard seenKeys.insert(key).inserted else {
        fatalError("중복 매핑 행 (줄 \(lineIndex + 1)): \(line)")
    }
    switch cols[0] {
    case "body":
        guard let ci = consonantNames[cols[1]], let vi = vowelNames[cols[2]] else {
            fatalError("알 수 없는 자모: \(line)")
        }
        bodyLines.append("        Triple(Consonant.\(ci), Vowel.\(vi), \"\(cols[3])\"),")
    case "final":
        guard let ci = consonantNames[cols[1]] else { fatalError("알 수 없는 자모: \(line)") }
        finalLines.append("        Consonant.\(ci) to \"\(cols[3])\",")
    default:
        fatalError("알 수 없는 kind: \(line)")
    }
}

let output = """
// KanaTable.kt
// spec/mapping.tsv 에서 생성됨 — 수기 수정 금지.
// 재생성: swift spec/generators/gen-kotlin.swift (저장소 루트에서)
package com.mastergear.hangulji.core

object KanaTable {
    val body: List<Triple<Consonant, Vowel, String>> = listOf(
\(bodyLines.joined(separator: "\n"))
    )

    val finals: List<Pair<Consonant, String>> = listOf(
\(finalLines.joined(separator: "\n"))
    )
}

"""
try! output.write(to: outURL, atomically: true, encoding: .utf8)
print("wrote \(outURL.path): body \(bodyLines.count), finals \(finalLines.count)")
```

- [ ] **Step 6: 생성 실행 + 결정성 검증**

```bash
swift spec/generators/gen-kotlin.swift          # → "wrote ...: body 159, finals 7"
cp android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt /tmp/KanaTable.kt.1
swift spec/generators/gen-kotlin.swift
diff /tmp/KanaTable.kt.1 android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt
```
Expected: body 159·finals 7(mapping.tsv 행 수와 일치), 두 번째 실행 diff 없음(결정성). `./gradlew :app:testDebugUnitTest` 여전히 그린(KanaTable.kt가 Jamo.kt와 함께 컴파일됨).

- [ ] **Step 7: Commit**

```bash
git add spec/generators/gen-kotlin.swift android/app/src/main/kotlin/com/mastergear/hangulji/core android/app/src/test
git commit -m "feat(android): Kotlin 자모 타입·Keymap + gen-kotlin 생성기(KanaTable.kt)"
```

---

### Task 3: JamoComposer + KanaMapper + Katakana — SPEC §2·§3 포트

**Files:**
- Create: `android/app/src/main/kotlin/com/mastergear/hangulji/core/JamoComposer.kt`, `.../core/KanaMapper.kt`, `.../core/Katakana.kt`, `android/app/src/test/kotlin/com/mastergear/hangulji/core/JamoComposerTest.kt`, `.../core/KanaMapperTest.kt`

**Interfaces:**
- Consumes: Task 2의 `Consonant`/`Vowel`/`Jamo`/`Keymap`/`KanaTable`
- Produces (Task 4가 소비):
  - `data class Syllable(val initial: Consonant?, val vowel: Vowel?, val final: Consonant?)` — `val hangul: String`, `companion object { fun canBeFinal(c: Consonant): Boolean }`
  - `class JamoComposer { val isEmpty: Boolean; fun append(jamo: Jamo); fun backspace(): Boolean; fun clear(); val syllables: List<Syllable> }`
  - `data class MappedSyllable(val display: String, val isMapped: Boolean)`
  - `object KanaMapper { fun map(syllables: List<Syllable>): List<MappedSyllable> }`
  - `fun String.toKatakana(): String`

- [ ] **Step 1: 실패하는 테스트 작성** (`android/app/src/test/kotlin/com/mastergear/hangulji/core/JamoComposerTest.kt`)

```kotlin
package com.mastergear.hangulji.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JamoComposerTest {
    private fun compose(keys: String): List<String> {
        val composer = JamoComposer()
        for (ch in keys) composer.append(Keymap.jamo(ch) ?: error("자모 아님: $ch"))
        return composer.syllables.map { it.hangul }
    }

    @Test fun basicSyllable() = assertEquals(listOf("카"), compose("zk"))
    @Test fun finalConsonant() = assertEquals(listOf("간"), compose("rks"))

    @Test
    fun batchimReanalysis() {   // SPEC §2.3-1: 간+ㅣ → 가/니
        assertEquals(listOf("가", "니"), compose("rksl"))
    }

    @Test
    fun compoundVowel() {   // SPEC §2.4: ㅜ+ㅓ=ㅝ, ㅗ+ㅏ=ㅘ
        assertEquals(listOf("워"), compose("dnj"))
        assertEquals(listOf("화"), compose("ghk"))
    }

    @Test
    fun doubleVowelSplits() {   // SPEC §2.3-4: 결합표 밖 모음 → flush
        assertEquals(listOf("카", "ㅏ"), compose("zkk"))
    }

    @Test
    fun ddCannotBeFinal() {   // SPEC §2.5: ㄸ 종성 불가 → 새 음절 초성
        assertEquals(listOf("카", "따"), compose("zkEk"))
    }

    @Test fun loneConsonant() = assertEquals(listOf("ㅋ"), compose("z"))
    @Test fun loneVowel() = assertEquals(listOf("ㅏ"), compose("k"))

    @Test
    fun consonantRunFlushes() {   // SPEC §2.2-1: 초성 연속 → 낱자 flush
        assertEquals(listOf("ㄱ", "ㄴ"), compose("rs"))
    }

    @Test
    fun backspaceRemovesOneJamo() {   // SPEC §2.6
        val composer = JamoComposer()
        for (ch in "rks") composer.append(Keymap.jamo(ch)!!)
        assertTrue(composer.backspace())
        assertEquals(listOf("가"), composer.syllables.map { it.hangul })
        assertTrue(composer.backspace()); assertTrue(composer.backspace())
        assertTrue(composer.isEmpty)
        assertFalse(composer.backspace())
    }

    @Test
    fun hangulRenderingFormula() {   // SPEC §2.7: 0xAC00 공식 — 힣 = ㅎ+ㅣ+ㅎ
        assertEquals("힣", Syllable(Consonant.H, Vowel.I, Consonant.H).hangul)
        assertEquals("", Syllable().hangul)
    }
}
```

`android/app/src/test/kotlin/com/mastergear/hangulji/core/KanaMapperTest.kt`:
```kotlin
package com.mastergear.hangulji.core

import org.junit.Assert.assertEquals
import org.junit.Test

class KanaMapperTest {
    private fun syllables(keys: String): List<Syllable> {
        val composer = JamoComposer()
        for (ch in keys) composer.append(Keymap.jamo(ch) ?: error("자모 아님: $ch"))
        return composer.syllables
    }

    @Test
    fun bodyAndFinal() {   // SPEC §3: 몸통+종성 독립 조회 — 간=がん
        assertEquals(
            listOf(MappedSyllable("がん", true)),
            KanaMapper.map(syllables("rks"))
        )
    }

    @Test
    fun unmappableSyllableStaysHangul() {   // 별: ㅂ+ㅕ 몸통 없음 → 한글 그대로
        assertEquals(
            listOf(MappedSyllable("별", false)),
            KanaMapper.map(syllables("quf"))
        )
    }

    @Test
    fun incompleteSyllableUnmapped() {   // SPEC §3-1: 낱자 → 매핑 불가
        assertEquals(
            listOf(MappedSyllable("ㅋ", false)),
            KanaMapper.map(syllables("z"))
        )
    }

    @Test
    fun unmappableFinalFailsWholeSyllable() {   // SPEC §3-4: 종성 ㄹ은 final 표에 없음 → 칼 전체 한글
        assertEquals(
            listOf(MappedSyllable("칼", false)),
            KanaMapper.map(syllables("zkf"))
        )
    }

    @Test
    fun katakanaConversion() {
        assertEquals("トウキョウ", "とうきょう".toKatakana())
        assertEquals("ラーメン", "らーめん".toKatakana())   // ー(U+30FC)는 범위 밖 — 보존
        assertEquals("abc東京", "abc東京".toKatakana())
    }
}
```

- [ ] **Step 2: 실패 확인** — `source android/scripts/env.sh && (cd android && ./gradlew :app:testDebugUnitTest)` → 컴파일 실패 (`Unresolved reference 'JamoComposer'`)

- [ ] **Step 3: JamoComposer.kt 구현** (`android/app/src/main/kotlin/com/mastergear/hangulji/core/JamoComposer.kt`)

```kotlin
package com.mastergear.hangulji.core

data class Syllable(
    val initial: Consonant? = null,
    val vowel: Vowel? = null,
    val final: Consonant? = null,
) {
    /** 화면 표시용 한글 — SPEC §2.7 유니코드 완성형 조합 공식 (미완성이면 낱자) */
    val hangul: String
        get() {
            if (initial != null && vowel != null) {
                val fi = final?.let { jongseongIndex[it] } ?: 0
                val code = 0xAC00 + (initial.ordinal * 21 + vowel.ordinal) * 28 + fi
                return String(Character.toChars(code))
            }
            if (initial != null) return initial.char.toString()
            if (vowel != null) return vowel.char.toString()
            return ""
        }

    companion object {
        /** 종성 인덱스 (SPEC §2.7). ㄸㅃㅉ 없음 = 종성 불가 (§2.5) */
        private val jongseongIndex: Map<Consonant, Int> = mapOf(
            Consonant.G to 1, Consonant.GG to 2, Consonant.N to 4, Consonant.D to 7,
            Consonant.R to 8, Consonant.M to 16, Consonant.B to 17, Consonant.S to 19,
            Consonant.SS to 20, Consonant.NG to 21, Consonant.J to 22, Consonant.CH to 23,
            Consonant.K to 24, Consonant.T to 25, Consonant.P to 26, Consonant.H to 27,
        )

        fun canBeFinal(c: Consonant): Boolean = jongseongIndex.containsKey(c)
    }
}

class JamoComposer {
    private val jamos = mutableListOf<Jamo>()

    val isEmpty: Boolean get() = jamos.isEmpty()

    fun append(jamo: Jamo) { jamos.add(jamo) }

    fun backspace(): Boolean {
        if (jamos.isEmpty()) return false
        jamos.removeAt(jamos.size - 1)
        return true
    }

    fun clear() { jamos.clear() }

    /** 모음 조합 결합표 (SPEC §2.4) */
    private val vowelCombinations: Map<Vowel, Map<Vowel, Vowel>> = mapOf(
        Vowel.O to mapOf(Vowel.A to Vowel.WA, Vowel.AE to Vowel.WAE, Vowel.I to Vowel.OE),
        Vowel.U to mapOf(Vowel.EO to Vowel.WO, Vowel.E to Vowel.WE, Vowel.I to Vowel.WI),
        Vowel.EU to mapOf(Vowel.I to Vowel.UI),
    )

    /** 자모 스트림 전체를 매번 처음부터 재조합 (SPEC §2.1 — 스트림이 짧아 단순함 우선) */
    val syllables: List<Syllable>
        get() {
            val result = mutableListOf<Syllable>()
            var cur = Syllable()

            fun flush() {
                if (cur != Syllable()) result.add(cur)
                cur = Syllable()
            }

            for (jamo in jamos) when (jamo) {
                is Jamo.C -> {   // SPEC §2.2
                    val c = jamo.consonant
                    if (cur.vowel == null) {
                        if (cur.initial == null) {
                            cur = cur.copy(initial = c)
                        } else {
                            flush()
                            cur = Syllable(initial = c)
                        }
                    } else if (cur.initial != null && cur.final == null && Syllable.canBeFinal(c)) {
                        cur = cur.copy(final = c)
                    } else {
                        flush()
                        cur = Syllable(initial = c)
                    }
                }
                is Jamo.V -> {   // SPEC §2.3
                    val v = jamo.vowel
                    val f = cur.final
                    if (f != null) {
                        cur = cur.copy(final = null)   // 받침 재해석: 종성을 다음 음절 초성으로
                        flush()
                        cur = Syllable(initial = f, vowel = v)
                    } else if (cur.vowel == null) {
                        cur = cur.copy(vowel = v)
                    } else {
                        val combined = vowelCombinations[cur.vowel]?.get(v)
                        if (combined != null) {
                            cur = cur.copy(vowel = combined)
                        } else {
                            flush()
                            cur = Syllable(vowel = v)
                        }
                    }
                }
            }
            flush()
            return result
        }
}
```

- [ ] **Step 4: KanaMapper.kt + Katakana.kt 구현**

`android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaMapper.kt`:
```kotlin
package com.mastergear.hangulji.core

data class MappedSyllable(val display: String, val isMapped: Boolean)

object KanaMapper {
    private val bodyTable: Map<Pair<Consonant, Vowel>, String> =
        KanaTable.body.associate { (initial, vowel, kana) -> (initial to vowel) to kana }

    private val finalTable: Map<Consonant, String> = KanaTable.finals.toMap()

    /** SPEC §3 — 몸통·종성 중 하나라도 실패하면 음절 전체 매핑 불가(한글 그대로) */
    fun map(syllables: List<Syllable>): List<MappedSyllable> = syllables.map { s ->
        val initial = s.initial ?: return@map MappedSyllable(s.hangul, false)
        val vowel = s.vowel ?: return@map MappedSyllable(s.hangul, false)
        val body = bodyTable[initial to vowel] ?: return@map MappedSyllable(s.hangul, false)
        val final = s.final ?: return@map MappedSyllable(body, true)
        val finalKana = finalTable[final] ?: return@map MappedSyllable(s.hangul, false)
        MappedSyllable(body + finalKana, true)
    }
}
```

`android/app/src/main/kotlin/com/mastergear/hangulji/core/Katakana.kt`:
```kotlin
package com.mastergear.hangulji.core

/** 히라가나(U+3041–U+3096)를 가타카나(+0x60)로. 그 외 문자는 보존. (전 범위 BMP — Char 단위 안전) */
fun String.toKatakana(): String = buildString(length) {
    for (ch in this@toKatakana) {
        append(if (ch.code in 0x3041..0x3096) (ch.code + 0x60).toChar() else ch)
    }
}
```

- [ ] **Step 5: 테스트 통과 확인** — Step 2와 같은 명령, Expected: `BUILD SUCCESSFUL` (Keymap 5 + JamoComposer 11 + KanaMapper 5 통과). 코어 회귀 `swift test --package-path core-swift` 통과.

- [ ] **Step 6: Commit**

```bash
git add android/app/src
git commit -m "feat(android): JamoComposer·KanaMapper·Katakana — SPEC §2·§3 Kotlin 포트"
```

---

### Task 4: HanguljiComposer + 픽스처 conformance 러너 (45+8 전부 그린)

**Files:**
- Create: `android/app/src/main/kotlin/com/mastergear/hangulji/core/HanguljiComposer.kt`, `android/app/src/test/kotlin/com/mastergear/hangulji/core/FixtureConformanceTest.kt`

**Interfaces:**
- Consumes: Task 2~3 전부, `spec/fixtures/kana.json`·`composition.json`, build.gradle.kts의 `fixturesDir` 시스템 프로퍼티(Task 1에서 주입 설정 완료)
- Produces (Task 7의 KeyboardModel이 소비):
  - `class HanguljiComposer { val isEmpty: Boolean; fun insert(ch: Char): Boolean; fun backspace(): Boolean; fun clear(); val markedText: String; val reading: String? }`

- [ ] **Step 1: 실패하는 테스트 작성** (`android/app/src/test/kotlin/com/mastergear/hangulji/core/FixtureConformanceTest.kt`)

```kotlin
package com.mastergear.hangulji.core

import com.google.gson.Gson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** spec/fixtures/*.json conformance 러너 (SPEC §6) — 모든 포트가 같은 픽스처를 통과해야 한다.
 *  개수 하드코딩 금지: 파일에 있는 만큼 전부 순회, 최소치(38/8)만 방어적으로 검사. */
class FixtureConformanceTest {
    private val fixturesDir = File(
        System.getProperty("fixturesDir")
            ?: error("-DfixturesDir 필요 (android/app/build.gradle.kts가 기본값을 주입한다)")
    )

    private data class KanaCase(
        val name: String, val keys: String, val kana: String, val fullyMapped: Boolean)
    private data class CompositionCase(
        val name: String, val keys: String, val syllables: List<String>)

    @Test
    fun kanaFixtures() {   // SPEC §6.1 — HanguljiComposer 레벨 골든
        val cases = Gson().fromJson(
            File(fixturesDir, "kana.json").readText(), Array<KanaCase>::class.java)
        assertTrue("케이스 수 ${cases.size} < 38", cases.size >= 38)
        for (c in cases) {
            val composer = HanguljiComposer()
            for (ch in c.keys) composer.insert(ch)
            assertEquals(c.name, c.kana, composer.markedText)
            assertEquals(c.name, c.fullyMapped, composer.reading != null)
        }
    }

    @Test
    fun compositionFixtures() {   // SPEC §6.2 — JamoComposer 레벨 골든
        val cases = Gson().fromJson(
            File(fixturesDir, "composition.json").readText(), Array<CompositionCase>::class.java)
        assertTrue("케이스 수 ${cases.size} < 8", cases.size >= 8)
        for (c in cases) {
            val composer = JamoComposer()
            for (ch in c.keys) {
                val jamo = Keymap.jamo(ch) ?: error("${c.name}: 자모 아님 '$ch'")
                composer.append(jamo)
            }
            assertEquals(c.name, c.syllables, composer.syllables.map { it.hangul })
        }
    }
}
```

- [ ] **Step 2: 실패 확인** — `source android/scripts/env.sh && (cd android && ./gradlew :app:testDebugUnitTest)` → 컴파일 실패 (`Unresolved reference 'HanguljiComposer'`)

- [ ] **Step 3: HanguljiComposer.kt 구현** (`android/app/src/main/kotlin/com/mastergear/hangulji/core/HanguljiComposer.kt`)

```kotlin
package com.mastergear.hangulji.core

/** 셸(IMS)이 사용하는 파사드 — 자모와 ー(장음) 토큰의 혼합 스트림 (SPEC §5).
 *  백스페이스는 토큰 1개 단위. */
class HanguljiComposer {
    private sealed interface Token {
        data class J(val jamo: Jamo) : Token
        data object Prolonged : Token   // ー
    }

    private val tokens = mutableListOf<Token>()

    val isEmpty: Boolean get() = tokens.isEmpty()

    /** 문자를 소비했으면 true. 자모 키와 '-'만 소비한다. */
    fun insert(ch: Char): Boolean {
        val jamo = Keymap.jamo(ch)
        if (jamo != null) { tokens.add(Token.J(jamo)); return true }
        if (ch == '-') { tokens.add(Token.Prolonged); return true }
        return false
    }

    fun backspace(): Boolean {
        if (tokens.isEmpty()) return false
        tokens.removeAt(tokens.size - 1)
        return true
    }

    fun clear() { tokens.clear() }

    /** 자모 연속 구간별로 조합→매핑하고 ー를 사이에 끼운다 (SPEC §5 표시/독법 계산) */
    private val mappedElements: List<MappedSyllable>
        get() {
            val elements = mutableListOf<MappedSyllable>()
            val composer = JamoComposer()

            fun flushJamoRun() {
                if (!composer.isEmpty) {
                    elements.addAll(KanaMapper.map(composer.syllables))
                    composer.clear()
                }
            }

            for (token in tokens) when (token) {
                is Token.J -> composer.append(token.jamo)
                Token.Prolonged -> {
                    flushJamoRun()
                    elements.add(MappedSyllable("ー", isMapped = true))
                }
            }
            flushJamoRun()
            return elements
        }

    /** 조합 중 표시 문자열 (가나 + 매핑불가 한글 혼합) */
    val markedText: String get() = mappedElements.joinToString("") { it.display }

    /** 전부 매핑됐을 때만 가나 reading, 아니면 null (한자 변환 가능 여부 신호) */
    val reading: String?
        get() {
            val elements = mappedElements
            if (elements.isEmpty() || !elements.all { it.isMapped }) return null
            return elements.joinToString("") { it.display }
        }
}
```

- [ ] **Step 4: conformance 통과 확인**

Run: `source android/scripts/env.sh && (cd android && ./gradlew :app:testDebugUnitTest --tests 'com.mastergear.hangulji.core.*')`
Expected: `BUILD SUCCESSFUL` — kana.json 45케이스·composition.json 8케이스 전부 그린. `-DfixturesDir` 재지정도 검증: `./gradlew :app:testDebugUnitTest -DfixturesDir=$(cd .. && pwd)/spec/fixtures` 동일 결과.

- [ ] **Step 5: Commit**

```bash
git add android/app/src
git commit -m "feat(android): HanguljiComposer + 픽스처 conformance 러너 — 45+8 전부 그린"
```

---

### Task 5: Swift 엔진 .so 스파이크 + build-engine.sh (타임박스 1일)

**Files:**
- Create: `android/engine/Package.swift`, `android/engine/Sources/HanguljiEngine/Shim.swift`, `android/scripts/build-engine.sh`, (커밋) `android/engine/Package.resolved`
- 산출(커밋 안 함): `android/app/src/main/jniLibs/{arm64-v8a,x86_64}/*.so`, `android/app/src/main/assets/azooKey_dictionary/`

**Interfaces:**
- Consumes: `core-swift`(HanguljiCore — toKatakana 재사용), AzooKeyKanaKanjiConverter exact 0.11.2의 `KanaKanjiConverter(dictionaryURL:preloadDictionary:)`·`ConvertRequestOptions`·`TextReplacer.empty`·`requestCandidates` (0.11.2 체크아웃에서 시그니처 확인 완료)
- Produces (Task 6이 소비): `libHanguljiEngine.so`가 노출하는 C ABI 4함수 —
  ```c
  /* 사전 디렉터리(louds/·cb/·p/·mm.binary 포함) 경로 → 컨버터 핸들. 실패 시 NULL */
  void *hangulji_converter_init(const char *dictionary_path);
  /* UTF-8 가나 reading → '\n' 구분 UTF-8 후보 목록(heap). 실패 시 NULL.
     반환 버퍼는 hangulji_string_free로 해제 */
  char *hangulji_converter_convert(void *converter, const char *reading, int32_t max_candidates);
  void  hangulji_string_free(char *str);
  void  hangulji_converter_free(void *converter);
  ```
  후보 목록 계약은 core-swift `KanjiConverter.candidateList(for:max:)`와 동일: 한자 후보 최대 max개 + 가나 원문 + 가타카나 폴백 보장 삽입, 등장 순서 유지, 중복 제거.

**리서치 근거(구현 중 검증 대상 — 프로그램 전체 최대 리스크)**: 엔진 저장소 자체 CI(`.github/workflows/swift.yml`의 `android-build` 잡)가 finagolfin/swift-android-sdk artifactbundle로 x86_64·aarch64·armv7 크로스컴파일 + x86_64 에뮬레이터 테스트를 수행 중(체크아웃에서 확인). Swift 런타임 `.so`는 SDK sysroot의 `usr/lib/<arch>-linux-android/<api>/lib*.so`에서 복사하고 libc/libdl/liblog/libm.so는 제외(시스템 제공)하는 것까지 그 CI가 보여준 검증된 레시피다. Swift 6.3은 swift.org 공식 Android SDK도 제공 — 스크립트는 공식 URL을 먼저 시도하고 finagolfin으로 폴백한다.

- [ ] **Step 1: 엔진 심 SwiftPM 패키지 작성**

`android/engine/Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji-engine",
    products: [
        // Android용 동적 라이브러리 — libHanguljiEngine.so
        .library(name: "HanguljiEngine", type: .dynamic, targets: ["HanguljiEngine"]),
    ],
    dependencies: [
        .package(path: "../../core-swift"),
        // Global Constraints: core-swift Package.resolved(0.11.2)와 동일 버전 고정
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", exact: "0.11.2"),
    ],
    targets: [
        .target(
            name: "HanguljiEngine",
            dependencies: [
                .product(name: "HanguljiCore", package: "hangulji-core"),
                // WithDefaultDictionary가 아닌 베이스 모듈 — 사전을 경로로 받는다 (아래 Shim 주석 참조)
                .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`android/engine/Sources/HanguljiEngine/Shim.swift`:
```swift
// Shim.swift — @_cdecl C ABI. JNI 글루(android/app/src/main/cpp/hangulji_jni.c)가 호출한다.
//
// 왜 HanguljiConversion(KanjiConverter.swift)을 그대로 링크하지 않는가:
// 그쪽은 KanaKanjiConverterModuleWithDefaultDictionary의 Bundle.module 리소스로 사전을
// 찾는데, APK 안에서는 SPM 리소스 번들 경로가 존재하지 않는다. Android에서는 사전
// 디렉터리를 명시 경로로 받고(assets→filesDir 복사본), 후보 목록 계약(한자 max개 +
// 가나·가타카나 폴백, 순서 유지, 중복 제거)만 KanjiConverter.swift와 동일하게 유지한다.
// pre-1.0 API 변동은 이 파일 한 곳에 가둔다 — 시그니처가 어긋나면 이 파일만 고친다.
import Foundation
import HanguljiCore
import KanaKanjiConverterModule

private final class EngineBox {
    let converter: KanaKanjiConverter
    let scratchDirectory: URL

    init(dictionaryPath: String) {
        self.converter = KanaKanjiConverter(
            dictionaryURL: URL(fileURLWithPath: dictionaryPath, isDirectory: true),
            preloadDictionary: true
        )
        self.scratchDirectory = FileManager.default.temporaryDirectory
    }

    func candidateList(for reading: String, max: Int) -> [String] {
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)

        let options = ConvertRequestOptions(
            N_best: max,
            requireJapanesePrediction: false,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: scratchDirectory,
            sharedContainerURL: scratchDirectory,
            textReplacer: .empty,   // 이모지 사전은 번들 리소스라 Android에선 미사용
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: nil
        )
        let results = converter.requestCandidates(composing, options: options)

        var seen = Set<String>()
        var kanji: [String] = []
        for text in results.mainResults.map(\.text) {
            if seen.insert(text).inserted { kanji.append(text) }
        }
        var list = Array(kanji.prefix(max))
        for fallback in [reading, reading.toKatakana()] where !list.contains(fallback) {
            list.append(fallback)
        }
        return list
    }
}

@_cdecl("hangulji_converter_init")
public func hangulji_converter_init(
    _ dictionaryPath: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let dictionaryPath, let path = String(validatingCString: dictionaryPath),
          FileManager.default.fileExists(atPath: path) else { return nil }
    let box = EngineBox(dictionaryPath: path)
    return Unmanaged.passRetained(box).toOpaque()
}

@_cdecl("hangulji_converter_convert")
public func hangulji_converter_convert(
    _ handle: UnsafeMutableRawPointer?,
    _ reading: UnsafePointer<CChar>?,
    _ maxCandidates: Int32
) -> UnsafeMutablePointer<CChar>? {
    guard let handle, let reading,
          let readingString = String(validatingCString: reading) else { return nil }
    let box = Unmanaged<EngineBox>.fromOpaque(handle).takeUnretainedValue()
    let list = box.candidateList(for: readingString, max: Int(maxCandidates))
    return strdup(list.joined(separator: "\n"))
}

@_cdecl("hangulji_string_free")
public func hangulji_string_free(_ str: UnsafeMutablePointer<CChar>?) {
    free(str)
}

@_cdecl("hangulji_converter_free")
public func hangulji_converter_free(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    Unmanaged<EngineBox>.fromOpaque(handle).release()
}
```

- [ ] **Step 2: 호스트(macOS) 컴파일로 심 코드 검증** — 크로스컴파일 전에 API 어긋남을 먼저 잡는다

Run: `cd android/engine && swift build 2>&1 | tail -5`
Expected: `Build complete!` (0.11.2 API와 심 코드가 맞음을 호스트에서 증명). 실패 시 Shim.swift만 수정(계약 유지) — Package.swift·다른 파일로 새지 않는다.

- [ ] **Step 3: build-engine.sh 작성** (`android/scripts/build-engine.sh`)

```bash
#!/bin/bash
# HanguljiEngine .so 크로스컴파일 + Swift 런타임 .so + 사전 assets 배치.
# 사용: android/scripts/build-engine.sh            (기본 ABIS="arm64-v8a x86_64")
#       ABIS=arm64-v8a android/scripts/build-engine.sh
# 전제: swift.org 툴체인 필요 — Xcode 내장 툴체인은 Swift SDK 크로스컴파일을 지원하지 않는다.
set -euo pipefail
cd "$(dirname "$0")/../engine"

SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"
ANDROID_API="${ANDROID_API:-24}"
ABIS="${ABIS:-arm64-v8a x86_64}"
SDK_ID="swift-${SWIFT_VERSION}-RELEASE-android-${ANDROID_API}-0.1"
CACHE="$HOME/.cache/hangulji-swift-android"
JNILIBS="$(cd .. && pwd)/app/src/main/jniLibs"
ASSETS="$(cd .. && pwd)/app/src/main/assets/azooKey_dictionary"

# 1) swift.org 툴체인 (swiftly 관리)
if ! command -v swiftly >/dev/null 2>&1; then
  echo "swiftly 미설치. 설치:" >&2
  echo "  curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && ~/.swiftly/bin/swiftly init" >&2
  exit 1
fi
swiftly install --use "$SWIFT_VERSION"
SWIFT_BIN="$(swiftly use --print-location)/usr/bin/swift"
"$SWIFT_BIN" --version | head -1

# 2) Swift Android SDK artifactbundle (로컬 파일 설치 — 체크섬 URL 의존 제거)
if ! "$SWIFT_BIN" sdk list 2>/dev/null | grep -q "android-${ANDROID_API}"; then
  mkdir -p "$CACHE"
  BUNDLE="$CACHE/${SDK_ID}.artifactbundle.tar.gz"
  if [ ! -f "$BUNDLE" ]; then
    # 공식(swift.org) 우선, 엔진 CI가 쓰는 finagolfin 폴백 — 둘 다 같은 artifactbundle 포맷
    curl -fL -o "$BUNDLE" \
      "https://download.swift.org/swift-${SWIFT_VERSION}-release/android/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-android-${ANDROID_API}-0.1.artifactbundle.tar.gz" \
    || curl -fL -o "$BUNDLE" \
      "https://github.com/finagolfin/swift-android-sdk/releases/download/${SWIFT_VERSION}/swift-${SWIFT_VERSION}-RELEASE-android-${ANDROID_API}-0.1.artifactbundle.tar.gz"
  fi
  "$SWIFT_BIN" sdk install "$BUNDLE"
fi
"$SWIFT_BIN" sdk list

# 3) ABI별 크로스컴파일 + 런타임 .so 복사
for ABI in $ABIS; do
  case "$ABI" in
    arm64-v8a) ARCH=aarch64 ;;
    x86_64)    ARCH=x86_64 ;;
    *) echo "지원하지 않는 ABI: $ABI" >&2; exit 1 ;;
  esac
  TRIPLE="${ARCH}-unknown-linux-android${ANDROID_API}"
  echo "== build $TRIPLE =="
  "$SWIFT_BIN" build -c release --swift-sdk "$TRIPLE" --product HanguljiEngine

  DEST="$JNILIBS/$ABI"
  mkdir -p "$DEST"
  cp ".build/$TRIPLE/release/libHanguljiEngine.so" "$DEST/"

  # Swift 런타임 — 엔진 저장소 CI 레시피: sysroot의 lib*.so 복사, 시스템 제공 4개 제외
  SYSROOT_LIBS=$(find "$HOME/Library/org.swift.swiftpm/swift-sdks" "$HOME/.config/swiftpm/swift-sdks" \
    -path "*${SDK_ID}*" -type d -path "*sysroot/usr/lib/${ARCH}-linux-android*" -name "${ANDROID_API}" \
    2>/dev/null | head -1)
  if [ -z "$SYSROOT_LIBS" ]; then
    echo "런타임 .so 디렉터리를 찾지 못함 — SDK 번들 내부 구조를 확인할 것:" >&2
    find "$HOME/Library/org.swift.swiftpm/swift-sdks" -maxdepth 4 -type d 2>/dev/null >&2
    exit 1
  fi
  cp "$SYSROOT_LIBS"/lib*.so "$DEST/"
  rm -f "$DEST"/libc.so "$DEST"/libdl.so "$DEST"/liblog.so "$DEST"/libm.so
  ls -la "$DEST" | head -20
done

# 4) 사전 → assets (SwiftPM 체크아웃의 서브모듈에서 — 35MB)
DICT_SRC=".build/checkouts/AzooKeyKanaKanjiConverter/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary"
[ -d "$DICT_SRC" ] || { echo "사전 디렉터리 없음: $DICT_SRC" >&2; exit 1; }
mkdir -p "$ASSETS"
rsync -a --delete "$DICT_SRC/" "$ASSETS/"
echo "assets: $(du -sh "$ASSETS" | cut -f1), jniLibs: $(du -sh "$JNILIBS" | cut -f1)"
echo "build-engine OK"
```

`chmod +x android/scripts/build-engine.sh`

- [ ] **Step 4: 크로스컴파일 실행 (스파이크 본체)**

Run: `./android/scripts/build-engine.sh`
Expected: `build-engine OK`, `android/app/src/main/jniLibs/arm64-v8a/`와 `x86_64/`에 `libHanguljiEngine.so` + `libswiftCore.so` 등 런타임, `assets/azooKey_dictionary/`에 `louds/ cb/ p/ mm.binary`(~35MB).
검증: `file android/app/src/main/jniLibs/arm64-v8a/libHanguljiEngine.so` → `ELF 64-bit LSB shared object, ARM aarch64`. 심볼 확인: `nm -D --defined-only android/app/src/main/jniLibs/arm64-v8a/libHanguljiEngine.so | grep hangulji_` → 4개 심볼.

- [ ] **Step 5: Package.resolved 커밋 대상 확인** — `grep -A3 AzooKeyKanaKanjiConverter android/engine/Package.resolved` → `"version" : "0.11.2"` (core-swift와 동일 리비전 80b8204).

- [ ] **Step 6: Commit**

```bash
git add android/engine android/scripts/build-engine.sh
git commit -m "feat(android): Swift 엔진 심(@_cdecl 4함수) + Android 크로스컴파일 스크립트"
```

- [ ] **Step 7: 타임박스/BLOCKED 프로토콜** (실패 시에만) — Step 2·4가 누적 1일(작업일 기준)을 넘겨도 해결 불가능한 실패(툴체인·SDK 설치 불가, 엔진 의존성 컴파일 불가 등)로 막히면: ① 실패 지점·에러 로그·시도한 대안을 담은 `docs/superpowers/plans/2026-08-01-multiplatform-4-android-BLOCKED.md`를 작성하고(권고: libmozc `.so` 경로 — 상세 계획은 이 문서 범위 밖), ② Task 6은 중단, ③ Task 1~4 결과물(코어 conformance)은 그대로 가치가 있으므로 커밋 유지, Task 7~9 중 엔진 비의존 부분(7, 8의 가나 확정 동작, 9의 JVM CI)만 별도 판단 후 진행 여부를 사용자에게 보고한다.

---

### Task 6: JNI 글루 + Kotlin KanjiConverter + 사전 설치 + 에뮬레이터 스모크 테스트

**Files:**
- Create: `android/app/src/main/cpp/CMakeLists.txt`, `android/app/src/main/cpp/hangulji_jni.c`, `android/app/src/main/kotlin/com/mastergear/hangulji/engine/KanjiConverter.kt`, `.../engine/DictionaryInstaller.kt`, `android/app/src/androidTest/kotlin/com/mastergear/hangulji/EngineSmokeTest.kt`
- Modify: `android/app/build.gradle.kts` (externalNativeBuild — .so 존재 시에만)

**Interfaces:**
- Consumes: Task 5의 C ABI 4함수 + jniLibs + assets/azooKey_dictionary
- Produces (Task 7~8이 소비):
  - `class KanjiConverter(dictionaryPath: String) { val isAvailable: Boolean; fun candidateList(reading: String, max: Int = 9): List<String>; fun close() }` — 엔진 미탑재 시 `isAvailable=false`·`candidateList`는 빈 목록(그레이스풀 디그레이드)
  - `object DictionaryInstaller { fun ensureInstalled(context: Context): File }` — filesDir 사전 경로 반환

- [ ] **Step 1: 실패하는 스모크 테스트 작성** (`android/app/src/androidTest/kotlin/com/mastergear/hangulji/EngineSmokeTest.kt`)

```kotlin
package com.mastergear.hangulji

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.mastergear.hangulji.engine.DictionaryInstaller
import com.mastergear.hangulji.engine.KanjiConverter
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** 완료 정의의 자동화 절반: 실기(에뮬레이터)에서 엔진이 とうきょう→東京을 낸다.
 *  전제: build-engine.sh 실행 완료(jniLibs + assets). */
@RunWith(AndroidJUnit4::class)
class EngineSmokeTest {
    @Test
    fun tokyoIsAmongCandidates() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dictionary = DictionaryInstaller.ensureInstalled(context)
        val converter = KanjiConverter(dictionary.absolutePath)
        assertTrue("엔진 .so 미탑재 — scripts/build-engine.sh 후 재시도", converter.isAvailable)
        val candidates = converter.candidateList("とうきょう", max = 9)
        assertTrue("후보: $candidates", candidates.contains("東京"))
        assertTrue("후보: $candidates", candidates.contains("とうきょう"))   // 가나 폴백 보장
        assertTrue("후보: $candidates", candidates.contains("トウキョウ"))   // 가타카나 폴백 보장
        converter.close()
    }
}
```

- [ ] **Step 2: JNI 글루 작성**

`android/app/src/main/cpp/hangulji_jni.c`:
```c
// JNI ↔ libHanguljiEngine.so C ABI 글루.
// 반환 문자열은 jbyteArray(UTF-8 원본 바이트)로 넘긴다 — NewStringUTF는 modified UTF-8이라
// 보충면(4바이트) 한자 후보에서 깨질 수 있다. 디코딩은 Kotlin 쪽 String(bytes, UTF_8).
#include <jni.h>
#include <stdint.h>
#include <string.h>

extern void *hangulji_converter_init(const char *dictionary_path);
extern char *hangulji_converter_convert(void *converter, const char *reading,
                                        int32_t max_candidates);
extern void hangulji_string_free(char *str);
extern void hangulji_converter_free(void *converter);

JNIEXPORT jlong JNICALL
Java_com_mastergear_hangulji_engine_KanjiConverterNative_nativeInit(
    JNIEnv *env, jclass clazz, jstring dictionary_path) {
    const char *path = (*env)->GetStringUTFChars(env, dictionary_path, NULL);
    if (path == NULL) return 0;
    void *handle = hangulji_converter_init(path);   /* 경로는 ASCII — modified UTF-8 무해 */
    (*env)->ReleaseStringUTFChars(env, dictionary_path, path);
    return (jlong)(intptr_t)handle;
}

JNIEXPORT jbyteArray JNICALL
Java_com_mastergear_hangulji_engine_KanjiConverterNative_nativeConvert(
    JNIEnv *env, jclass clazz, jlong handle, jbyteArray reading_utf8, jint max_candidates) {
    if (handle == 0) return NULL;
    jsize reading_len = (*env)->GetArrayLength(env, reading_utf8);
    char reading[1024];
    if (reading_len <= 0 || reading_len >= (jsize)sizeof(reading)) return NULL;
    (*env)->GetByteArrayRegion(env, reading_utf8, 0, reading_len, (jbyte *)reading);
    reading[reading_len] = '\0';

    char *joined = hangulji_converter_convert((void *)(intptr_t)handle, reading,
                                              (int32_t)max_candidates);
    if (joined == NULL) return NULL;
    size_t len = strlen(joined);
    jbyteArray result = (*env)->NewByteArray(env, (jsize)len);
    if (result != NULL) {
        (*env)->SetByteArrayRegion(env, result, 0, (jsize)len, (const jbyte *)joined);
    }
    hangulji_string_free(joined);
    return result;
}

JNIEXPORT void JNICALL
Java_com_mastergear_hangulji_engine_KanjiConverterNative_nativeFree(
    JNIEnv *env, jclass clazz, jlong handle) {
    if (handle != 0) hangulji_converter_free((void *)(intptr_t)handle);
}
```

`android/app/src/main/cpp/CMakeLists.txt`:
```cmake
cmake_minimum_required(VERSION 3.22)
project(hangulji_jni C)

set(JNILIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

add_library(hangulji-engine SHARED IMPORTED)
set_target_properties(hangulji-engine PROPERTIES
    IMPORTED_LOCATION ${JNILIBS_DIR}/libHanguljiEngine.so)

add_library(hangulji_jni SHARED hangulji_jni.c)
target_link_libraries(hangulji_jni hangulji-engine)
```

- [ ] **Step 3: build.gradle.kts에 조건부 externalNativeBuild 추가** (`android { }` 블록 안, `buildFeatures` 다음)

```kotlin
    // 엔진 .so가 있는 ABI만 네이티브 빌드 — 없으면(예: CI) 글루도 빼고 순수 Kotlin 앱으로 빌드.
    // KanjiConverterNative.isLoaded=false 경로가 런타임 폴백을 담당한다 (Task 6 Kotlin 래퍼).
    val engineAbis = listOf("arm64-v8a", "x86_64")
        .filter { file("src/main/jniLibs/$it/libHanguljiEngine.so").exists() }
    if (engineAbis.isNotEmpty()) {
        ndkVersion = "27.2.12479018"
        externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }
        defaultConfig { ndk { abiFilters.addAll(engineAbis) } }
    }
```

- [ ] **Step 4: Kotlin 래퍼 + 사전 설치기 구현**

`android/app/src/main/kotlin/com/mastergear/hangulji/engine/KanjiConverter.kt`:
```kotlin
package com.mastergear.hangulji.engine

internal object KanjiConverterNative {
    val isLoaded: Boolean = try {
        // libhangulji_jni.so 로드 → DT_NEEDED로 libHanguljiEngine.so + Swift 런타임이 연쇄 로드됨
        System.loadLibrary("hangulji_jni")
        true
    } catch (e: UnsatisfiedLinkError) {
        false   // 엔진 없이 빌드된 APK(CI 등) — 변환 비활성 폴백
    }

    external fun nativeInit(dictionaryPath: String): Long
    external fun nativeConvert(handle: Long, readingUtf8: ByteArray, maxCandidates: Int): ByteArray?
    external fun nativeFree(handle: Long)
}

/** 후보 목록 계약은 core-swift KanjiConverter와 동일(한자 최대 max + 가나·가타카나 폴백).
 *  엔진 미탑재/초기화 실패 시 isAvailable=false, candidateList는 빈 목록. */
class KanjiConverter(dictionaryPath: String) {
    private var handle: Long =
        if (KanjiConverterNative.isLoaded) KanjiConverterNative.nativeInit(dictionaryPath) else 0L

    val isAvailable: Boolean get() = handle != 0L

    @Synchronized
    fun candidateList(reading: String, max: Int = 9): List<String> {
        if (handle == 0L) return emptyList()
        val bytes = KanjiConverterNative.nativeConvert(
            handle, reading.toByteArray(Charsets.UTF_8), max) ?: return emptyList()
        return bytes.toString(Charsets.UTF_8).split('\n').filter { it.isNotEmpty() }
    }

    @Synchronized
    fun close() {
        if (handle != 0L) {
            KanjiConverterNative.nativeFree(handle)
            handle = 0L
        }
    }
}
```

`android/app/src/main/kotlin/com/mastergear/hangulji/engine/DictionaryInstaller.kt`:
```kotlin
package com.mastergear.hangulji.engine

import android.content.Context
import java.io.File

/** assets/azooKey_dictionary → filesDir/azooKey_dictionary 1회 복사.
 *  엔진은 mmap 가능한 실파일 경로가 필요해 assets에서 직접 열 수 없다.
 *  APK가 갱신되면(lastUpdateTime 변동) 재복사한다. 최초 복사 ~35MB. */
object DictionaryInstaller {
    private const val ASSET_DIR = "azooKey_dictionary"

    fun ensureInstalled(context: Context): File {
        val target = File(context.filesDir, ASSET_DIR)
        val stamp = File(target, ".installed-version")
        val expected = context.packageManager
            .getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
        if (stamp.exists() && stamp.readText() == expected) return target
        target.deleteRecursively()
        copyAssetDir(context, ASSET_DIR, target)
        stamp.writeText(expected)
        return target
    }

    private fun copyAssetDir(context: Context, assetPath: String, target: File) {
        val names = context.assets.list(assetPath) ?: return
        if (names.isEmpty()) {   // leaf = 파일 (사전에 빈 디렉터리 없음)
            target.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            return
        }
        target.mkdirs()
        for (name in names) copyAssetDir(context, "$assetPath/$name", File(target, name))
    }
}
```

- [ ] **Step 5: 에뮬레이터에서 스모크 테스트 실행**

```bash
source android/scripts/env.sh
"$ANDROID_HOME/emulator/emulator" -avd hangulji -netdelay none -netspeed full &
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'
cd android && ./gradlew :app:connectedDebugAndroidTest
```
Expected: `BUILD SUCCESSFUL` — EngineSmokeTest 1개 통과(東京·とうきょう·トウキョウ 전부 후보에 존재). 초회는 사전 복사+로드로 수십 초 걸릴 수 있음. 실패 시 `adb logcat -d | grep -iE 'hangulji|UnsatisfiedLink|swift'`로 원인 확인(전형: 런타임 .so 누락 → build-engine.sh Step 3의 복사 목록 점검).

- [ ] **Step 6: 그레이스풀 디그레이드 빌드 확인** — jniLibs를 임시로 치우고 빌드만 검증

```bash
mv android/app/src/main/jniLibs /tmp/jniLibs.bak
(cd android && ./gradlew :app:assembleDebug)   # Expected: BUILD SUCCESSFUL (.so 없이)
mv /tmp/jniLibs.bak android/app/src/main/jniLibs
```

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/cpp android/app/src/main/kotlin/com/mastergear/hangulji/engine android/app/src/androidTest android/app/build.gradle.kts
git commit -m "feat(android): JNI 글루 + KanjiConverter 래퍼 + 사전 설치 + 에뮬레이터 스모크(東京)"
```

---

### Task 7: KeyboardModel — 상태머신 Kotlin 포트 (iOS 14테스트 계약 + 엔진부재 폴백)

**Files:**
- Create: `android/app/src/main/kotlin/com/mastergear/hangulji/keyboard/KeyboardModel.kt`, `android/app/src/test/kotlin/com/mastergear/hangulji/keyboard/KeyboardModelTest.kt`

**Interfaces:**
- Consumes: Task 4의 `HanguljiComposer`, Task 3의 `toKatakana`(테스트 페이크에서)
- Produces (Task 8의 IMS·View가 소비):
  - `interface TextOutput { fun setMarkedText(s: String); fun commitText(s: String); fun clearMarkedText(); fun insertText(s: String); fun deleteBackward() }`
  - `fun interface CandidateSource { fun candidateList(reading: String, max: Int): List<String> }`
  - `class KeyboardModel(candidateSource: CandidateSource)` — Compose 상태 `preview: String`, `candidates: List<String>`, `selectedIndex: Int`, `isShifted: Boolean`(외부 쓰기 가능), `var output: TextOutput?`, 메서드 `tapKey(latin: Char)`, `toggleShift()`, `tapSpace()`, `tapCandidate(index: Int)`, `tapEnter()`, `tapBackspace()`, `tapSymbol(s: String)`, `commitAll()`, `discardComposition()`

**의미론 = 현재 `ios/Keyboard/KeyboardModel.swift`와 동일** (초기 iOS 계획이 아니라 리뷰 반영 후의 현행 코드가 기준): 스페이스=변환/다음 후보, 후보 탭=확정, 새 타이핑=현재 후보 확정 후 새 조합, 백스페이스=선택 취소→가나 복귀/자모 1개/프록시 위임, 조합·선택과 함께 삽입되는 구두점은 **하나의 원자적 commitText**(iOS의 비동기 배칭 레이스 교훈 — Android InputConnection도 commitText 1회가 조합 영역 치환+확정+삽입을 원자적으로 처리하므로 같은 구조가 그대로 옳다), `discardComposition`=출력 호출 없이 상태만 파기. iOS와의 유일한 의도적 차이: 엔진 미탑재로 `candidateList`가 빈 목록이면 가나를 그대로 확정한다(그레이스풀 디그레이드 — iOS는 엔진이 항상 폴백을 보장해 이 분기가 없다).

- [ ] **Step 1: 실패하는 테스트 작성** (`android/app/src/test/kotlin/com/mastergear/hangulji/keyboard/KeyboardModelTest.kt`)

iOS `KeyboardModelTests.swift`의 14개 테스트를 1:1 포트 + 15번째(엔진부재 폴백). JVM에서는 Android `.so`를 로드할 수 없으므로 후보 공급은 페이크(`CandidateSource`) — 실엔진의 東京 검증은 Task 6의 EngineSmokeTest가 담당한다.

```kotlin
package com.mastergear.hangulji.keyboard

import com.mastergear.hangulji.core.toKatakana
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeOutput : TextOutput {
    val marked = mutableListOf<String>()
    val committed = mutableListOf<String>()
    val inserted = mutableListOf<String>()
    var clearedCount = 0
    var deletions = 0

    override fun setMarkedText(s: String) { marked.add(s) }
    override fun commitText(s: String) { committed.add(s) }
    override fun clearMarkedText() { clearedCount++ }
    override fun insertText(s: String) { inserted.add(s) }
    override fun deleteBackward() { deletions++ }
}

/** JVM 테스트용 후보 공급 페이크 — 계약(한자들 + 가나 + 가타카나 폴백)만 흉내낸다 */
private class FakeCandidateSource : CandidateSource {
    override fun candidateList(reading: String, max: Int): List<String> = when (reading) {
        "とうきょう" -> listOf("東京", "東教", "とうきょう", "トウキョウ")
        else -> listOf(reading, reading.toKatakana()).distinct()
    }
}

class KeyboardModelTest {
    private fun makeModel(
        source: CandidateSource = FakeCandidateSource(),
    ): Pair<KeyboardModel, FakeOutput> {
        val model = KeyboardModel(source)
        val out = FakeOutput()
        model.output = out
        return model to out
    }

    @Test
    fun typingShowsKanaPreview() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)   // 토우쿄우
        assertEquals("とうきょう", model.preview)
        assertTrue(model.candidates.isEmpty())
        assertEquals("とうきょう", out.marked.last())   // 조합 영역에도 반영
    }

    @Test
    fun shiftIsOneShot() {
        val (model, _) = makeModel()
        model.toggleShift()
        assertTrue(model.isShifted)
        model.tapKey('R')   // View가 시프트 상태의 라틴 대문자를 전달
        assertFalse(model.isShifted)
        assertEquals("ㄲ", model.preview)
    }

    @Test
    fun spaceConverts() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        assertTrue(model.candidates.isNotEmpty())
        assertTrue("${model.candidates}", model.candidates.contains("東京"))
        assertEquals(0, model.selectedIndex)
        assertEquals(model.candidates[0], model.preview)
        assertEquals(model.candidates[0], out.marked.last())
        model.tapSpace()   // 다음 후보
        assertEquals(1, model.selectedIndex)
        assertEquals(model.candidates[1], model.preview)
        assertEquals(model.candidates[1], out.marked.last())
    }

    @Test
    fun candidateTapCommits() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        val tokyoIndex = model.candidates.indexOf("東京")
        assertTrue(tokyoIndex >= 0)
        model.tapCandidate(tokyoIndex)
        assertEquals(listOf("東京"), out.committed)
        assertTrue(out.inserted.isEmpty())
        assertEquals("", model.preview)
        assertTrue(model.candidates.isEmpty())
    }

    @Test
    fun enterCommitsKanaWhileComposing() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapEnter()
        assertEquals(listOf("とうきょう"), out.committed)
        assertTrue(out.inserted.isEmpty())
        assertEquals("", model.preview)
    }

    @Test
    fun enterInsertsNewlineWhenIdle() {
        val (model, out) = makeModel()
        model.tapEnter()
        assertEquals(listOf("\n"), out.inserted)
    }

    @Test
    fun typingDuringSelectionCommitsCurrentCandidate() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        val first = model.candidates[0]
        model.tapKey('z')   // 새 타이핑
        assertEquals(listOf(first), out.committed)
        assertEquals("ㅋ", model.preview)
        assertEquals("ㅋ", out.marked.last())
        assertTrue(model.candidates.isEmpty())
    }

    @Test
    fun backspaceJamoThenProxy() {
        val (model, out) = makeModel()
        model.tapKey('z'); model.tapKey('k')   // 카
        model.tapBackspace()                   // ㅏ 제거 → ㅋ
        assertEquals("ㅋ", model.preview)
        model.tapBackspace()                   // 조합 비움 → 조합 영역 제거(프록시 위임 아님)
        assertEquals("", model.preview)
        assertTrue(out.clearedCount >= 1)
        assertEquals(0, out.deletions)
        model.tapBackspace()                   // 프록시로 위임
        assertEquals(1, out.deletions)
    }

    @Test
    fun backspaceCancelsSelection() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        model.tapBackspace()
        assertTrue(model.candidates.isEmpty())
        assertEquals("とうきょう", model.preview)          // 가나로 복귀
        assertEquals("とうきょう", out.marked.last())      // 조합 영역도 다시 표시
    }

    @Test
    fun spaceWhenIdleInsertsSpace() {
        val (model, out) = makeModel()
        model.tapSpace()
        assertEquals(listOf(" "), out.inserted)
    }

    @Test
    fun unmappableCommitsAsIs() {
        val (model, out) = makeModel()
        for (ch in "quf") model.tapKey(ch)   // 별 (매핑 불가 → reading null)
        model.tapSpace()                      // 변환 불가 → 그대로 확정
        assertEquals(listOf("별"), out.committed)
        assertTrue(out.inserted.isEmpty())
    }

    @Test
    fun discardCompositionClearsWithoutOutputCalls() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        val counts = listOf(
            out.marked.size, out.committed.size, out.inserted.size, out.clearedCount, out.deletions)

        model.discardComposition()   // 필드 전환 시뮬레이션 — 아무것도 확정하지 않음

        assertEquals("", model.preview)
        assertTrue(model.candidates.isEmpty())
        assertEquals(counts, listOf(
            out.marked.size, out.committed.size, out.inserted.size, out.clearedCount, out.deletions))

        model.tapKey('z')   // 이후 새 조합은 정상 시작
        assertEquals("ㅋ", model.preview)
    }

    @Test
    fun symbols() {
        val (model, out) = makeModel()
        model.tapSymbol("。")
        assertEquals(listOf("。"), out.inserted)
        for (ch in "fk") model.tapKey(ch)     // 라
        model.tapSymbol("ー")                  // 조합 중 ー는 조합에 들어감
        assertEquals("らー", model.preview)
        assertEquals("らー", out.marked.last())
        model.tapSymbol("。")                  // 조합 확정+。를 하나의 원자적 commitText로
        assertEquals(listOf("らー。"), out.committed)
        assertEquals(listOf("。"), out.inserted)   // 두 번째 。는 별도 insertText로 나가지 않음
        assertEquals("", model.preview)
    }

    @Test
    fun symbolWhileSelectingCommitsCandidateAndSymbolAtomically() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        val first = model.candidates[0]
        model.tapSymbol("。")
        assertEquals(listOf(first + "。"), out.committed)
        assertTrue(out.inserted.isEmpty())
        assertTrue(model.candidates.isEmpty())
        assertEquals("", model.preview)
    }

    @Test
    fun engineUnavailableCommitsKanaAsIs() {   // Android 고유: .so 미탑재 그레이스풀 디그레이드
        val (model, out) = makeModel(source = { _, _ -> emptyList() })
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        assertEquals(listOf("とうきょう"), out.committed)
        assertTrue(model.candidates.isEmpty())
        assertEquals("", model.preview)
    }
}
```

- [ ] **Step 2: 실패 확인** — `source android/scripts/env.sh && (cd android && ./gradlew :app:testDebugUnitTest)` → 컴파일 실패 (`Unresolved reference 'KeyboardModel'`)

- [ ] **Step 3: KeyboardModel.kt 구현** (`android/app/src/main/kotlin/com/mastergear/hangulji/keyboard/KeyboardModel.kt`)

```kotlin
package com.mastergear.hangulji.keyboard

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mastergear.hangulji.core.HanguljiComposer

/** IMS가 구현하는 텍스트 출력 추상화 — iOS TextOutput과 동일 계약 */
interface TextOutput {
    fun setMarkedText(s: String)   // 조합/선택 후보를 조합 영역(밑줄)으로 표시
    fun commitText(s: String)      // 조합 영역을 s로 치환·확정 (원자적)
    fun clearMarkedText()          // 조합 취소 — 아무것도 확정하지 않고 조합 영역 제거
    fun insertText(s: String)      // 조합과 무관한 직접 삽입 (공백·개행·구두점)
    fun deleteBackward()
}

/** 한자 후보 공급자 — 실기는 KanjiConverter 어댑터, JVM 테스트는 페이크 */
fun interface CandidateSource {
    fun candidateList(reading: String, max: Int): List<String>
}

/** 키보드 상태머신. Android 프레임워크 비의존(Compose 스냅숏 상태만) — JVM 유닛테스트 대상.
 *  의미론은 ios/Keyboard/KeyboardModel.swift(현행)와 동일. 유일한 의도적 차이:
 *  candidateList가 빈 목록(엔진 미탑재)이면 가나를 그대로 확정한다. */
class KeyboardModel(private val candidateSource: CandidateSource) {
    var preview by mutableStateOf(""); private set
    var candidates by mutableStateOf<List<String>>(emptyList()); private set
    var selectedIndex by mutableIntStateOf(0); private set
    var isShifted by mutableStateOf(false)

    var output: TextOutput? = null

    private val composer = HanguljiComposer()

    private val isSelecting: Boolean get() = candidates.isNotEmpty()

    fun tapKey(latin: Char) {
        if (isSelecting) commitCandidate(selectedIndex)
        if (composer.insert(latin)) {
            isShifted = false
            refreshPreview()
        }
    }

    fun toggleShift() { isShifted = !isShifted }

    fun tapSpace() {
        if (isSelecting) {
            selectedIndex = (selectedIndex + 1) % candidates.size
            preview = candidates[selectedIndex]
            output?.setMarkedText(candidates[selectedIndex])
            return
        }
        if (composer.isEmpty) {
            output?.insertText(" ")
            return
        }
        val reading = composer.reading
        if (reading == null) {
            commitComposition()   // 매핑 불가 포함 → 그대로 확정
            return
        }
        val list = candidateSource.candidateList(reading, 9)
        if (list.isEmpty()) {
            commitComposition()   // 엔진 미탑재 폴백 — 가나 그대로 확정
            return
        }
        candidates = list
        selectedIndex = 0
        preview = list[0]
        output?.setMarkedText(list[0])
    }

    fun tapCandidate(index: Int) {
        if (index !in candidates.indices) return
        commitCandidate(index)
    }

    fun tapEnter() {
        if (isSelecting) { commitCandidate(selectedIndex); return }
        if (!composer.isEmpty) { commitComposition(); return }
        output?.insertText("\n")
    }

    fun tapBackspace() {
        if (isSelecting) {   // 변환 취소 → 가나 조합으로 복귀
            candidates = emptyList()
            selectedIndex = 0
            refreshPreview()   // composer는 그대로라 가나가 다시 조합 영역에 표시됨
            return
        }
        if (composer.backspace()) {
            refreshPreview()   // 조합이 비면 refreshPreview가 clearMarkedText 호출
        } else {
            output?.deleteBackward()
        }
    }

    /** 조합/선택 확정과 함께 삽입되는 구두점·기호는 하나의 원자적 commitText로 합친다
     *  (iOS 프록시 배칭 레이스의 교훈 — InputConnection에서도 같은 구조가 안전하다). */
    fun tapSymbol(s: String) {
        if (s == "ー") {
            if (isSelecting) commitCandidate(selectedIndex)
            if (composer.insert('-')) refreshPreview()
            return
        }
        if (isSelecting) {
            output?.commitText(candidates[selectedIndex] + s)
            composer.clear()
            candidates = emptyList()
            selectedIndex = 0
            preview = ""
            return
        }
        if (!composer.isEmpty) {
            output?.commitText(composer.markedText + s)
            composer.clear()
            preview = ""
            return
        }
        output?.insertText(s)
    }

    /** 포커스 이탈 등 — 조합/선택 중이면 조합 영역 내용을 그대로 확정 */
    fun commitAll() {
        if (isSelecting) { commitCandidate(selectedIndex); return }
        if (!composer.isEmpty) commitComposition()
    }

    /** 필드 전환 등 외부 요인 — 아무것도 확정하지 않고 상태만 파기 (output 호출 없음) */
    fun discardComposition() {
        composer.clear()
        candidates = emptyList()
        selectedIndex = 0
        preview = ""
    }

    private fun commitComposition() {
        output?.commitText(composer.markedText)
        composer.clear()
        preview = ""
    }

    private fun commitCandidate(index: Int) {
        output?.commitText(candidates[index])
        composer.clear()
        candidates = emptyList()
        selectedIndex = 0
        preview = ""
    }

    private fun refreshPreview() {
        preview = composer.markedText
        if (preview.isEmpty()) {
            output?.clearMarkedText()
        } else {
            output?.setMarkedText(preview)
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인** — Step 2와 같은 명령, Expected: `BUILD SUCCESSFUL` — KeyboardModelTest 15개 전부(+기존 코어 테스트) 그린. 코어 회귀 `swift test --package-path core-swift` 통과.

- [ ] **Step 5: Commit**

```bash
git add android/app/src
git commit -m "feat(android): KeyboardModel 상태머신 — iOS 14테스트 계약 + 엔진부재 폴백"
```

---

### Task 8: InputMethodService + Compose 키보드 UI + 에뮬레이터 설치 (완료 정의 달성)

**Files:**
- Create: `android/app/src/main/kotlin/com/mastergear/hangulji/keyboard/HanguljiInputMethodService.kt`, `.../keyboard/KeyboardView.kt`, `android/app/src/main/res/xml/method.xml`, `android/scripts/install-emu.sh`
- Modify: `android/app/src/main/AndroidManifest.xml`(IME 서비스 등록), `android/app/src/main/kotlin/com/mastergear/hangulji/MainActivity.kt`(스텁 → 설치 안내 본 구현)

**Interfaces:**
- Consumes: Task 7의 `KeyboardModel`/`TextOutput`/`CandidateSource`, Task 6의 `KanjiConverter`/`DictionaryInstaller`
- Produces: 완성된 IME. 레이아웃(문서 상단 키 표 기준):
  - 후보/프리뷰 바(상단 44dp): 조합 중=preview 가나, 선택 중=후보 가로 스크롤(선택 강조, 탭=`tapCandidate`)
  - 1행 ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ / 2행 ㅁㄴㅇㄹㅎㅗㅓㅏㅣ / 3행 [⇧]ㅋㅌㅊㅍㅠㅜㅡ[⌫] / 4행 [🌐][ー][스페이스·변환][。][⏎]
  - 시프트 원샷 + **롱프레스 변형 팝업**(ㅂㅈㄷㄱㅅㅐㅔ 키: 롱프레스→기본/변형 두 칸 팝업, 좌우 슬라이드로 선택, 떼면 입력 — iOS 팝업의 Android 번역)
  - 키 탭은 라틴 문자 전송: 평상시 소문자, 시프트/팝업 변형 시 해당 키만 대문자(QWERTOP)

- [ ] **Step 1: method.xml + 매니페스트 IME 등록**

`android/app/src/main/res/xml/method.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<input-method xmlns:android="http://schemas.android.com/apk/res/android"
    android:supportsSwitchingToNextInputMethod="true">
    <subtype
        android:label="한글지"
        android:imeSubtypeLocale="ja_JP"
        android:imeSubtypeMode="keyboard" />
</input-method>
```

`AndroidManifest.xml`의 `<!-- IME 서비스는 Task 8에서 추가 -->` 주석을 다음으로 교체:
```xml
        <service
            android:name=".keyboard.HanguljiInputMethodService"
            android:label="한글지"
            android:permission="android.permission.BIND_INPUT_METHOD"
            android:exported="true">
            <intent-filter>
                <action android:name="android.view.InputMethod" />
            </intent-filter>
            <meta-data android:name="android.view.im" android:resource="@xml/method" />
        </service>
```

- [ ] **Step 2: HanguljiInputMethodService.kt 구현**

```kotlin
package com.mastergear.hangulji.keyboard

import android.inputmethodservice.InputMethodService
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.mastergear.hangulji.engine.DictionaryInstaller
import com.mastergear.hangulji.engine.KanjiConverter
import kotlin.concurrent.thread

/** InputMethodService + ComposeView 호스팅.
 *  IMS는 LifecycleOwner가 아니므로 직접 소유해야 Compose가 붙는다(FlorisBoard 패턴 —
 *  Apache-2.0이라 구조 인용 가능). setContent 전에 ViewTree 오너 지정이 필수. */
class HanguljiInputMethodService :
    InputMethodService(), LifecycleOwner, SavedStateRegistryOwner, TextOutput {

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry

    private lateinit var model: KeyboardModel
    @Volatile private var converter: KanjiConverter? = null

    override fun onCreate() {
        super.onCreate()
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)

        model = KeyboardModel(CandidateSource { reading, max ->
            converter?.takeIf { it.isAvailable }?.candidateList(reading, max) ?: emptyList()
        })
        model.output = this

        // 사전 복사(최초 ~35MB) + 컨버터 로드는 무거움 — 백그라운드 1회.
        // 로드 완료 전 변환 시도는 빈 목록 → 가나 그대로 확정(그레이스풀 디그레이드)
        thread(name = "hangulji-engine-init") {
            val dictionary = DictionaryInstaller.ensureInstalled(this)
            converter = KanjiConverter(dictionary.absolutePath)
        }
    }

    override fun onCreateInputView(): View {
        val view = ComposeView(this)
        window?.window?.decorView?.let {
            it.setViewTreeLifecycleOwner(this)
            it.setViewTreeSavedStateRegistryOwner(this)
        }
        view.setViewTreeLifecycleOwner(this)
        view.setViewTreeSavedStateRegistryOwner(this)
        view.setContent {
            KeyboardScreen(model = model, onSwitchKeyboard = ::showImePicker)
        }
        return view
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        if (!restarting) model.discardComposition()   // 새 필드 — 이전 조합 상태를 끌고 가지 않음
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        model.commitAll()   // 포커스 이탈 — 조합 영역을 그대로 확정 (IC가 아직 유효한 시점)
        super.onFinishInputView(finishingInput)
    }

    override fun onDestroy() {
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        converter?.close()
        super.onDestroy()
    }

    private fun showImePicker() {
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
    }

    // MARK: TextOutput — InputConnection 대응 (iOS 프록시보다 단순: 동기적 조합 영역 API)
    override fun setMarkedText(s: String) { currentInputConnection?.setComposingText(s, 1) }
    override fun commitText(s: String) { currentInputConnection?.commitText(s, 1) }
    override fun clearMarkedText() {
        currentInputConnection?.apply {
            setComposingText("", 1)   // 조합 영역 삭제
            finishComposingText()
        }
    }
    override fun insertText(s: String) { currentInputConnection?.commitText(s, 1) }
    override fun deleteBackward() {
        // deleteSurroundingText(1,0)는 서로게이트 쌍을 반쪽만 지울 수 있어 KEYCODE_DEL 사용
        sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
    }
}
```

- [ ] **Step 3: KeyboardView.kt 구현** (`android/app/src/main/kotlin/com/mastergear/hangulji/keyboard/KeyboardView.kt`)

```kotlin
package com.mastergear.hangulji.keyboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.material3.Text
import kotlin.math.roundToInt

/** 키 정의: 표시 자모·전송 라틴 + 시프트/롱프레스 변형 (변형 없으면 base와 동일) */
private data class KeyDef(
    val label: String, val latin: Char,
    val variantLabel: String, val variantLatin: Char,
) {
    val hasVariant: Boolean get() = latin != variantLatin
}

private val row1 = listOf(
    KeyDef("ㅂ", 'q', "ㅃ", 'Q'), KeyDef("ㅈ", 'w', "ㅉ", 'W'), KeyDef("ㄷ", 'e', "ㄸ", 'E'),
    KeyDef("ㄱ", 'r', "ㄲ", 'R'), KeyDef("ㅅ", 't', "ㅆ", 'T'), KeyDef("ㅛ", 'y', "ㅛ", 'y'),
    KeyDef("ㅕ", 'u', "ㅕ", 'u'), KeyDef("ㅑ", 'i', "ㅑ", 'i'), KeyDef("ㅐ", 'o', "ㅒ", 'O'),
    KeyDef("ㅔ", 'p', "ㅖ", 'P'),
)
private val row2 = "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".zip("asdfghjkl".toList())
    .map { (label, latin) -> KeyDef(label.toString(), latin, label.toString(), latin) }
private val row3 = "ㅋㅌㅊㅍㅠㅜㅡ".zip("zxcvbnm".toList())
    .map { (label, latin) -> KeyDef(label.toString(), latin, label.toString(), latin) }

/** 롱프레스 팝업 상태 — 동시에 하나만 존재 */
private class CalloutState(val key: KeyDef, val keyBounds: Rect) {
    var variantSelected by mutableStateOf(true)   // 팝업이 뜨는 순간엔 변형 칸 선택
}

@Composable
fun KeyboardScreen(model: KeyboardModel, onSwitchKeyboard: () -> Unit) {
    val dark = isSystemInDarkTheme()
    val background = if (dark) Color(0xFF2B2B2B) else Color(0xFFD1D4DA)
    val keyColor = if (dark) Color(0xFF6B6B6B) else Color.White
    val specialColor = if (dark) Color(0xFF474747) else Color(0xFFADB3BD)
    val textColor = if (dark) Color.White else Color.Black
    var callout by remember { mutableStateOf<CalloutState?>(null) }

    Box {
        Column(
            modifier = Modifier.fillMaxWidth().background(background).padding(3.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            CandidateBar(model, keyColor, textColor)
            KeyRow(row1, model, keyColor, textColor, onCallout = { callout = it })
            KeyRow(row2, model, keyColor, textColor, onCallout = { callout = it })
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SpecialKey(if (model.isShifted) "⬆" else "⇧", specialColor, textColor,
                    Modifier.width(44.dp)) { model.toggleShift() }
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (key in row3) {
                        KeyCap(key, model, keyColor, textColor, Modifier.weight(1f),
                            onCallout = { callout = it })
                    }
                }
                SpecialKey("⌫", specialColor, textColor, Modifier.width(44.dp)) {
                    model.tapBackspace()
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SpecialKey("🌐", specialColor, textColor, Modifier.width(44.dp), onSwitchKeyboard)
                SpecialKey("ー", specialColor, textColor, Modifier.width(40.dp)) {
                    model.tapSymbol("ー")
                }
                SpecialKey(
                    if (model.candidates.isEmpty()) "변환·스페이스" else "다음 후보",
                    keyColor, textColor, Modifier.weight(1f)) { model.tapSpace() }
                SpecialKey("。", specialColor, textColor, Modifier.width(40.dp)) {
                    model.tapSymbol("。")
                }
                SpecialKey("⏎", specialColor, textColor, Modifier.width(44.dp)) {
                    model.tapEnter()
                }
            }
        }
        callout?.let { CalloutPopup(it, keyColor, textColor) }
    }
}

@Composable
private fun CandidateBar(model: KeyboardModel, keyColor: Color, textColor: Color) {
    Box(
        Modifier.fillMaxWidth().height(44.dp)
            .background(keyColor, RoundedCornerShape(6.dp)),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (model.candidates.isEmpty()) {
            Text(model.preview, color = textColor, fontSize = 20.sp,
                modifier = Modifier.padding(horizontal = 10.dp))
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.padding(horizontal = 10.dp)) {
                itemsIndexed(model.candidates) { index, candidate ->
                    Text(
                        candidate, color = textColor, fontSize = 20.sp,
                        modifier = Modifier
                            .background(
                                if (index == model.selectedIndex) Color(0x3345A0FF)
                                else Color.Transparent,
                                RoundedCornerShape(4.dp))
                            .padding(horizontal = 6.dp)
                            .clickable { model.tapCandidate(index) },
                    )
                }
            }
        }
    }
}

@Composable
private fun KeyRow(
    keys: List<KeyDef>, model: KeyboardModel, keyColor: Color, textColor: Color,
    onCallout: (CalloutState?) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (key in keys) {
            KeyCap(key, model, keyColor, textColor, Modifier.weight(1f), onCallout)
        }
    }
}

/** 키캡: 탭=기본(시프트 시 변형) 라틴 전송, 변형 키 롱프레스=두 칸 팝업(슬라이드 선택, 릴리스 확정) */
@Composable
private fun KeyCap(
    key: KeyDef, model: KeyboardModel, keyColor: Color, textColor: Color,
    modifier: Modifier, onCallout: (CalloutState?) -> Unit,
) {
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Box(
        modifier = modifier.height(43.dp)
            .background(keyColor, RoundedCornerShape(5.dp))
            .onGloballyPositioned { bounds = it.boundsInParent() }
            .pointerInput(key) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    if (!key.hasVariant) {
                        // 변형 없는 키 — 눌림 즉시 입력(네이티브 키보드 감각)
                        model.tapKey(if (model.isShifted) key.variantLatin else key.latin)
                        do {
                            val event = awaitPointerEvent()
                        } while (event.changes.any { it.pressed })
                        return@awaitEachGesture
                    }
                    val longPress = awaitLongPressOrCancellation(down.id)
                    if (longPress == null) {
                        // 롱프레스 타임아웃 전에 뗌 → 탭
                        model.tapKey(if (model.isShifted) key.variantLatin else key.latin)
                        return@awaitEachGesture
                    }
                    val state = CalloutState(key, bounds)
                    onCallout(state)
                    var selectVariant = true
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: continue
                        // 키 중심 기준 좌=기본, 우=변형 (팝업 두 칸과 좌우 일치)
                        selectVariant = change.position.x >= size.width / 2f
                        state.variantSelected = selectVariant
                        if (!change.pressed) break
                    }
                    onCallout(null)
                    model.tapKey(if (selectVariant) key.variantLatin else key.latin)
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (model.isShifted) key.variantLabel else key.label,
            color = textColor, fontSize = 20.sp, textAlign = TextAlign.Center,
        )
    }
}

/** 롱프레스 두 칸 팝업 — 키 위 26dp, [기본|변형], 선택 칸 강조 */
@Composable
private fun CalloutPopup(state: CalloutState, keyColor: Color, textColor: Color) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val yOffset = with(density) { (state.keyBounds.top - 56.dp.toPx()).roundToInt() }
    val xOffset = with(density) {
        (state.keyBounds.left + state.keyBounds.width / 2 - 55.dp.toPx()).roundToInt()
    }
    Row(
        Modifier
            .offset { IntOffset(xOffset.coerceAtLeast(0), yOffset.coerceAtLeast(0)) }
            .background(keyColor, RoundedCornerShape(8.dp))
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for ((label, selected) in listOf(
            state.key.label to !state.variantSelected,
            state.key.variantLabel to state.variantSelected,
        )) {
            Box(
                Modifier.width(48.dp).height(48.dp)
                    .background(
                        if (selected) Color(0xFF45A0FF) else Color.Transparent,
                        RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, color = if (selected) Color.White else textColor, fontSize = 22.sp)
            }
        }
    }
}
```

- [ ] **Step 4: MainActivity 본 구현** (스텁 교체)

```kotlin
package com.mastergear.hangulji

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                var testInput by remember { mutableStateOf("") }
                Column(
                    Modifier.fillMaxSize().padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("한글지 설치", style = MaterialTheme.typography.headlineSmall)
                    Text("1. 키보드 활성화: 설정 → 시스템 → 키보드 → 화면 키보드 관리 → 한글지 켜기")
                    Button(onClick = {
                        startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                    }) { Text("키보드 설정 열기") }
                    Text("2. 키보드 전환: 아래 버튼 또는 입력 중 🌐 키")
                    Button(onClick = {
                        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
                            .showInputMethodPicker()
                    }) { Text("키보드 선택창 열기") }
                    Text("3. 테스트: 토우쿄우(xhdnzydn) → 변환·스페이스 → 東京")
                    OutlinedTextField(
                        value = testInput, onValueChange = { testInput = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("타이핑 테스트") },
                    )
                    Text("입력 규칙: 카=か 가=が (위치 무관) · 받침ㅅ=っ · 받침ㄴ=ん · 장음은 ー 키 또는 철자대로(토우쿄우)")
                }
            }
        }
    }
}
```

- [ ] **Step 5: install-emu.sh 작성** (`android/scripts/install-emu.sh`)

```bash
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
adb shell ime list -s | grep -q "$IME_ID" && echo "IME 활성: $IME_ID"
adb shell am start -n com.mastergear.hangulji/.MainActivity
echo "앱의 테스트 입력창에서: xhdnzydn → 변환·스페이스 → 東京 탭"
```

`chmod +x android/scripts/install-emu.sh`

- [ ] **Step 6: 전체 검증 (완료 정의)**

```bash
source android/scripts/env.sh
(cd android && ./gradlew :app:testDebugUnitTest)   # 코어+모델 전부 그린
./android/scripts/install-emu.sh
```

에뮬레이터 수동 E2E 체크리스트 (완료 정의 — 전부 통과해야 Task 완료):
1. 안내 앱의 테스트 입력창 탭 → 한글지 키보드가 올라온다 (안 올라오면 install-emu.sh의 `ime set` 출력 확인)
2. `xhdnzydn` 타이핑 → 조합 영역(밑줄)에 `とうきょう`
3. 변환·스페이스 → 후보 바에 후보들, 첫 후보가 조합 영역에 표시. **東京이 후보에 있다**
4. 東京 탭(또는 스페이스로 이동 후 ⏎) → **東京 확정 입력** ← §7 SP4 완료 정의
5. `fk` → `ら`, ー 키 → `らー`, 。키 → `らー。`가 한 번에 확정(순서 뒤집힘 없음)
6. 백스페이스: 조합 중 자모 1개씩 → 비면 문서 삭제로 위임
7. ㄱ 키 롱프레스 → [ㄱ|ㄲ] 팝업, 슬라이드로 ㄲ 선택 후 릴리스 → 조합에 ㄲ
8. ⇧ 후 ㄱ → ㄲ (원샷 — 다음 키부터 해제)
9. 🌐 → 키보드 선택창 표시
10. `adb logcat -d | grep -i 'hangulji-engine-init'`에 크래시 없음

- [ ] **Step 7: Commit**

```bash
git add android/app/src android/scripts/install-emu.sh
git commit -m "feat(android): IMS + Compose 2벌식 키보드 UI + 에뮬레이터 설치 — 토우쿄우→東京"
```

---

### Task 9: CI(android.yml) + 생성물 최신성 + README

**Files:**
- Create: `.github/workflows/android.yml`
- Modify: `.github/workflows/core.yml`(생성물 최신성 스텝에 gen-kotlin 추가 — 명시 허용 범위), `README.md`(Android 섹션 + 로드맵)

**CI 결정과 근거**: android.yml은 **ubuntu 러너에서 Swift `.so` 없이** JVM conformance 테스트 + assembleDebug만 돈다. 근거: ① 매핑 드리프트를 막는 실제 게이트는 픽스처 러너(순수 JVM)이고, ② CI에서 Swift 크로스컴파일은 swift.org 툴체인+SDK 다운로드(~2GB, 10분+)가 필요한데 산출물(.so)의 실효 검증(에뮬레이터 스모크)은 별도 러너 구성 없이는 불가능해 비용 대비 이득이 없다. ③ Task 6의 조건부 externalNativeBuild + 런타임 폴백 덕에 `.so` 없는 assembleDebug가 제품 코드 경로 그대로 컴파일된다. 엔진 빌드는 macOS 로컬 `android/scripts/build-engine.sh`로 수행(문서화된 수동 절차) — 엔진 저장소 CI가 이미 같은 조합의 크로스컴파일을 상시 검증 중이므로 중복 투자하지 않는다. gen-kotlin 최신성 검사는 Swift가 이미 있는 core.yml macOS 잡의 기존 스텝에 얹는다(ubuntu에 Swift 설치 회피).

- [ ] **Step 1: android.yml 작성** (`.github/workflows/android.yml`)

```yaml
name: android
on:
  push:
    branches: [main]
  pull_request:

jobs:
  jvm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - uses: gradle/actions/setup-gradle@v4
      - name: Conformance + 모델 테스트 (JVM — spec/fixtures 45+8 포함)
        run: cd android && ./gradlew :app:testDebugUnitTest
      - name: assembleDebug (엔진 .so 없이 — 그레이스풀 디그레이드 빌드 검증)
        run: cd android && ./gradlew :app:assembleDebug
```

- [ ] **Step 2: core.yml 최신성 스텝 확장** — `생성물 최신성 (테이블·픽스처)` 스텝의 run 블록을 다음으로 교체 (gen-kotlin 실행 1줄 + diff 경로 1개 추가):

```yaml
        run: |
          swift spec/generators/gen-swift.swift
          swift spec/generators/gen-mozc-table.swift
          swift spec/generators/gen-kotlin.swift
          swift run --package-path core-swift fixture-export
          git diff --exit-code -- spec windows core-swift/Sources/HanguljiCore/KanaTable.generated.swift android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt
```

- [ ] **Step 3: README 갱신** — ① 설치 섹션에 Android 추가: `./android/scripts/setup-env.sh` → `./android/scripts/build-engine.sh` → `./android/scripts/install-emu.sh` 3단계와 "엔진 .so 없이도 빌드·설치 가능(가나 전용 동작)" 명시, Task 8 Step 6의 E2E 체크리스트 요약(활성화 경로 + 토우쿄우→東京) 포함. ② 로드맵에서 Android를 "완료(에뮬레이터)"로 이동. ③ 저장소 구조 트리에 `android/` 실제 구조 반영.

- [ ] **Step 4: 최종 검증**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/android.yml')); yaml.safe_load(open('.github/workflows/core.yml')); print('yaml OK')"
swift spec/generators/gen-kotlin.swift && git diff --exit-code -- android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt   # 최신성 로컬 재현
source android/scripts/env.sh && (cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug)
swift test --package-path core-swift
```
Expected: 전부 성공.

- [ ] **Step 5: Commit**

```bash
git add .github README.md
git commit -m "ci(android): ubuntu JVM conformance + assembleDebug 잡, gen-kotlin 최신성 게이트"
```

---

## Self-Review 결과

**1. 스펙 커버리지**
- 설계 §5.3 전 항목: Kotlin IMS+Compose ✓(T8), 코어 Kotlin 이디엄 포트+생성 테이블+픽스처 러너 ✓(T2–T4), Swift Android SDK로 arm64-v8a/x86_64 `.so` + `@_cdecl` 심 + JNI 래퍼 + assets 사전 ✓(T5–T6), CLI 전용 개발 루프(sdkmanager/avdmanager/gradle/adb, `adb shell ime enable/set`) ✓(T1·T8), 최대 리스크 폴백 순서(① 검증된 CI 레시피 복제·버전 고정 — T5가 엔진 저장소 CI 레시피와 finagolfin 번들을 그대로 사용, ② libmozc — BLOCKED 프로토콜로 위임) ✓(T5 Step 7)
- SPEC.md: §1 키맵 33항목+대문자 폴백 ✓(T2, KeymapTest가 폴백·비자모 검증), §2 automaton 전이·받침 재해석·복합모음·종성 불가·백스페이스·렌더링 공식 ✓(T3, 테스트가 각 규칙 커버), §3 몸통/종성 독립 조회·전체 실패 원칙 ✓(T3 KanaMapperTest), §4 `-`는 코어·`.`/`,`는 셸 ✓(T4 Prolonged 토큰 / T7 tapSymbol), §5 토큰 스트림·markedText·reading ✓(T4), §6 러너 의무(두 파일 모두, 개수 하드코딩 금지) ✓(T4), §7 변경 절차(생성기·수기 수정 금지) ✓(T2 생성기 + T9 CI 최신성 게이트)
- §7 SP4 완료 정의(에뮬레이터 토우쿄우→東京): 자동화 절반은 T6 EngineSmokeTest, 수동 확정은 T8 Step 6 체크리스트 항목 4 ✓
- 지시 사항 대비: 5개 태스크 묶음(부트스트랩/코어+생성기/엔진/셸/CI)을 9개로 세분 ✓, C 시그니처 명시 ✓(T5 Interfaces), `candidateList(reading): List<String>` ✓(T6), `-DfixturesDir` ✓(T1 build.gradle+T4 Step 4), CI에서 .so 제외 결정+근거 ✓(T9), 엔진 0.11.x 고정 ✓(exact 0.11.2)

**2. 플레이스홀더 스캔**: "TBD/TODO/나중에/적절히" 없음. 외부 불확실성 두 곳은 구체 행동으로 봉인 — ① Swift SDK 다운로드 URL은 공식/finagolfin 2후보를 스크립트가 순차 시도(로컬 파일 설치로 체크섬 의존 제거), ② 0.11.2 API는 로컬 체크아웃에서 시그니처를 확인해 심 코드에 반영했고 어긋나면 Shim.swift 한 파일만 수정한다는 봉쇄 규칙 명시(T5 Step 2).

**3. 타입 일관성 대조**
- `Consonant/Vowel/Jamo/Keymap`(T2 정의) ↔ T3 JamoComposer·T4 HanguljiComposer·gen-kotlin 산출 KanaTable ✓ (enum 이름 G/GG/…, A/AE/… 생성기 맵과 선언 일치)
- `KanaTable.body: List<Triple<Consonant, Vowel, String>>`·`finals: List<Pair<Consonant, String>>`(T2 생성기) ↔ T3 KanaMapper의 `associate {(initial, vowel, kana) -> …}`·`toMap()` ✓
- `HanguljiComposer`(T4: isEmpty/insert/backspace/clear/markedText/reading) ↔ T7 KeyboardModel 사용부 ✓
- C ABI 4함수(T5 심의 @_cdecl 이름) ↔ T6 hangulji_jni.c extern 선언 ✓; JNI 심볼 `Java_com_mastergear_hangulji_engine_KanjiConverterNative_nativeInit/Convert/Free` ↔ Kotlin `KanjiConverterNative`(패키지 com.mastergear.hangulji.engine) external 시그니처(jstring/jbyteArray·jlong·jint) ✓ — nativeConvert는 양방향 ByteArray(UTF-8)로 통일
- `KanjiConverter(dictionaryPath)`·`isAvailable`·`candidateList(reading, max)`·`close()`(T6) ↔ T8 IMS의 CandidateSource 어댑터·onDestroy ✓
- `TextOutput` 5메서드·`CandidateSource`(T7) ↔ T8 IMS 구현·T7 테스트 페이크 ✓; `KeyboardModel` 공개 메서드(tapKey/toggleShift/tapSpace/tapCandidate/tapEnter/tapBackspace/tapSymbol/commitAll/discardComposition) ↔ T8 KeyboardScreen 호출부 ✓
- IME_ID `com.mastergear.hangulji/.keyboard.HanguljiInputMethodService`(T8 스크립트) ↔ 매니페스트 서비스 이름 `.keyboard.HanguljiInputMethodService` ✓

**4. 검산**: mapping.tsv 데이터 행 = body 159 + final 7 = 166 → T2 Step 6 기대 출력과 일치 ✓. kana.json 45케이스·composition.json 8케이스(실측) → "45+8 전부 그린" 문구와 일치, 러너 최소치는 SPEC대로 38/8 ✓. 로컬 환경 실측 반영: JDK 17(코레토) 존재·jenv 기본 11 → env.sh 필수 ✓, `~/Library/Android/sdk`에 cmdline-tools 부재 → setup-env.sh가 설치 ✓, Swift SDK 미설치(`swift sdk list` 빈 결과) → T5가 설치 ✓, 사전 35MB(cb/louds/mm.binary/p) 경로는 체크아웃 실측 ✓.





