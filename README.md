# 한글지 (Hangulji)

**한글로 일본어를 치는 macOS 입력기.**
일본어 발음을 한글(가나 철자 그대로)로 타이핑하면 실시간으로 가나가 되고, 스페이스를 누르면 한자로 변환됩니다. 로마지 입력(toukyou → とうきょう → 東京)의 한글 버전입니다.

```
토우쿄우니이키마스  →  とうきょうにいきます  →  [Space]  →  東京に行きます
```

일본어 자판을 새로 외울 필요 없이, 한국인에게 가장 익숙한 2벌식 자판과 한글 표기 감각으로 일본어를 입력하는 것이 목표입니다.

## 동작 원리

로마지 입력이 발음(Tokyo)이 아니라 **철자**(toukyou)를 치듯, 한글지도 가나 철자를 한글로 그대로 적습니다.

- 격음(ㅋㅌㅍㅊ) = 청음, 평음(ㄱㄷㅂㅈ) = 탁음 — **위치와 무관하게 항상**: 카=か, 가=が, 칸=かん, 간=がん
- 장음은 철자 그대로: 토우쿄우=とうきょう, 오오사카=おおさか, 에이가=えいが
- 받침 ㅅ=っ, 받침 ㄴ=ん: 삿포로=さっぽろ, 칸=かん
- 한글의 초성 ㅇ 덕분에 로마지의 n 모호성 문제가 없습니다: **칸이**(칸+이)=かんい, **카니**(카+니)=かに — 아포스트로피 없이 자동 구분

> 국립국어원 외래어 표기법(도쿄, 삿포로식)은 어두/어중에 따라 표기가 바뀌고 장음이 사라지는 **비가역** 표기라서 입력 규칙으로 쓰지 않습니다. 대신 자주 쓰는 관용 표기(홋까이도, 쯔, 망가 등)는 별칭으로 받아줍니다.

## 설치

### macOS

**요구사항:** macOS 14 이상, Swift 툴체인(Xcode 또는 Command Line Tools)

```bash
git clone https://github.com/mastergear4824/hangulji.git
cd hangulji
./macos/scripts/install-dev.sh
```

첫 빌드는 변환 사전을 내려받아 몇 분 걸릴 수 있습니다. 설치 후:

1. **시스템 설정 → 키보드 → 입력 소스 → 편집 → `+` → 일본어 → 한글지** 추가
2. 목록에 안 보이면 **로그아웃 후 다시 로그인** (새 입력기 등록 시 알려진 macOS 동작)
3. 입력 소스를 한글지로 전환하고 아무 앱에서나 타이핑

### iOS (시뮬레이터)

**요구사항:** Xcode 16 이상, XcodeGen(`brew install xcodegen`)

> 스크립트(`ios/scripts/*.sh`)는 시뮬레이터 기기명이 **iPhone 17**이라고 가정합니다. 기기명이 다르면 스크립트 안의 이름을 실제 기기명으로 수정하세요.

```bash
git clone https://github.com/mastergear4824/hangulji.git
cd hangulji
./ios/scripts/install-sim.sh
```

설치 후 iOS 시뮬레이터에서:

1. **설정 → 일반 → 키보드 → 키보드** → `+` → **일본어** 추가
2. **한글지** 추가 (일본어 아래에 있음)
3. **설정 → 일반 → 키보드 → 하드웨어 키보드** → **하드웨어 키보드 비활성화** (⌘⇧K)
4. 앱에서 입력 소스를 한글지로 전환하고 타이핑

> **실기기 사용:** 무료 Apple 개발자 계정으로 7일 테스트 프로비저닝 가능합니다.

### Android (에뮬레이터)

**요구사항:** JDK 17+, Swift 툴체인(swiftly), macOS — 나머지(cmdline-tools, API 35 AVD)는 `android/scripts/setup-env.sh`가 설치, Swift 툴체인

```bash
git clone https://github.com/mastergear4824/hangulji.git
cd hangulji
source android/scripts/env.sh
./android/scripts/setup-env.sh
./android/scripts/build-engine.sh
./android/scripts/install-emu.sh
```

**엔진 빌드는 로컬에서만 수행합니다:** 한자 변환 엔진(.so)은 macOS/Linux에서만 Swift로 크로스컴파일할 수 있어 CI에서는 검증하지 않습니다. 대신 엔진 저장소의 CI가 같은 조합을 상시 검증하고 있습니다. 엔진 .so가 없어도 **가나 입력/조합은 완전히 동작합니다** (JVM 폴백).

**설치 후 활성화:**
1. **설정 → 언어 및 입력 → 가상 키보드** → **모두 관리 → 한글지** 활성화
2. **기본 입력기를 한글지로 설정** (또는 개별 앱에서 입력 소스 전환)
3. 에뮬레이터에서 아무 앱을 열고 타이핑 (예: 메모 앱)

**확인 (E2E 테스트):**
- **입력:** `토우쿄우` (한글로 타이핑)
- **실시간 표시:** `とうきょう` (가나 자동 합성)
- **Space 후:** `東京` (한자 변환)

### Windows

**코드 제로** — Google 일본어 입력의 커스텀 로마자 테이블로 한글지 방식을 사용합니다.

상세한 설치 방법은 [windows/README.md](windows/README.md)를 참고하세요.

**설치형 브리지(2단계)** — 상주 프로그램(`hangulji-bridge.exe`)이 2벌식 키를 로마자로
변환해 MS-IME에 주입합니다. 테이블 교체 없이 시스템 기본 일본어 IME를 그대로 씁니다.
빌드·사용법·한계는 [windows/bridge/README.md](windows/bridge/README.md)를 참고하세요
(CI 빌드 + 변환 로직 conformance까지 검증됨, 실기기 실행 검증은 보류).

## 사용법

| 키 | 조합 중 (가나 표시) | 후보 선택 중 |
|---|---|---|
| 한글 키 | 자모 입력, 가나 실시간 표시 | 현재 후보 확정 후 새 조합 시작 |
| **Space** | 한자 변환 시작 | 다음 후보 |
| **Enter** | 가나 그대로 확정 | 현재 후보 확정 |
| **Esc** | 조합 취소 | 변환 취소 (가나로 복귀) |
| **Backspace** | 자모 1개 삭제 | 변환 취소 |
| **1–9** | — | 후보 직접 선택 |
| **↑ / ↓** | — | 후보 이동 |
| `-` | ー (장음 기호) | — |
| `.` `,` | 。 、 | 후보 확정 후 。 、 |

- 조합 중 밑줄로 표시되는 가나가 실시간 피드백입니다. 오타(특히 자/쟈 계열)는 여기서 바로 확인하세요.
- 가타카나는 변환 후보 목록에 항상 포함됩니다 (예: 라-멘 → Space → ラーメン 선택).
- 첫 변환은 사전 로드 때문에 1–2초 걸릴 수 있습니다. 이후에는 즉시 변환됩니다.

## 입력 규칙

### 기본 음절표

| 행 | あ단 | い단 | う단 | え단 | お단 | 요음 (ゃ/ゅ/ょ) |
|---|---|---|---|---|---|---|
| あ | 아 | 이 | 우 | 에 | 오 | 야=や 유=ゆ 요=よ |
| か/が | 카/가 | 키/기 | 쿠/구 | 케/게 | 코/고 | 캬 큐 쿄 / 갸 규 교 |
| さ/ざ | 사/자 | 시/지 | 스/즈 | 세/제 | 소/조 | 샤 슈 쇼 / 쟈 쥬 죠 |
| た/だ | 타/다 | 치/디* | 츠/두* | 테/데 | 토/도 | 챠 츄 쵸 |
| な | 나 | 니 | 누 | 네 | 노 | 냐 뉴 뇨 |
| は/ば/ぱ | 하/바/파 | 히/비/피 | 후/부/푸 | 헤/베/페 | 호/보/포 | 햐 휴 효 / 뱌 뷰 뵤 / 퍄 퓨 표 |
| ま | 마 | 미 | 무 | 메 | 모 | 먀 뮤 묘 |
| ら | 라 | 리 | 루 | 레 | 로 | 랴 류 료 |
| わ행 | 와=わ | | | | **워=を** | |

\* 디/두는 ディ/ドゥ(외래어용). だ행의 ぢ/づ는 아래 특수 음절 참고.

### 받침과 특수 규칙

| 입력 | 출력 | 예 |
|---|---|---|
| 받침 ㅅ (별칭: ㄱ ㅂ ㄷ) | っ | 삿포로=さっぽろ, 홋카이도우=ほっかいどう |
| 받침 ㄴ (별칭: ㅇ ㅁ) | ん | 칸=かん, 망가=まんが, 돔부리=どんぶり |
| 장음 | 철자 그대로 | 토우쿄우=とうきょう, 오네에상=おねえさん |
| `-` | ー | 라-멘=らーめん |
| 조사 | 철자대로 | は=**하**, へ=**헤**, を=**워** |
| ぢ / づ | 띠 / 뜨 | 하나띠=はなぢ, 츠뜨쿠=つづく |
| 확장 가타카나 | 티=ティ 디=ディ 투=トゥ 두=ドゥ 화=ファ 휘=フィ 훼=フェ 훠=フォ 위=ウィ 웨=ウェ | 파-티-=パーティー |

### 관용 별칭 (익숙한 표기도 그대로 통함)

| 별칭 | 결과 | 예 |
|---|---|---|
| 된소리 ㄲㄸㅃㅆㅉ | 청음 취급 | 홋**까**이도, 잇**빠**이, ~**짱**(ちゃん), 곤니**찌**와의 찌=ち |
| 쓰, 쯔 | つ | 표기법·통용 표기 모두 수용 |
| ㅜ↔ㅡ (う단) | 동일 취급 | 수=스=す, 흐=후=ふ |
| 차/추/초 | 챠/츄/쵸와 동일 | ちゃ/ちゅ/ちょ |

**주의:** 자=ざ, 쟈=じゃ는 발음이 같아도 **표기로 구분**합니다 (조/죠, 주/쥬 동일). 밑줄 가나 프리뷰로 확인하세요.

전체 규칙과 설계 배경은 [설계 문서](docs/superpowers/specs/2026-07-31-hangulji-ime-design.md)에 있습니다.

## 문제 해결

| 증상 | 해결 |
|---|---|
| 입력 소스 목록에 한글지가 없음 | 로그아웃/로그인 후 다시 확인 (최초 등록 시 필요할 수 있음) |
| 첫 한자 변환이 느림 | 정상 — 사전 로드 1회. 이후 즉시 |
| 비밀번호 입력란에서 동작 안 함 | 정상 — macOS가 보안 입력에서 모든 서드파티 입력기를 우회함 |
| 코드 수정 후 반영 안 됨 | `./macos/scripts/install-dev.sh` 재실행 (killall 포함) |
| 매핑 안 되는 한글이 그대로 남음 | 의도된 동작 — 일본어에 없는 음절(예: 별)은 한글로 표시되어 오타를 알림 |

## 개발

```
spec/                           매핑 사양 (mapping.tsv, fixtures/, SPEC.md, generators/)
core-swift/                     공용 로직 + 엔진 어댑터 + 테스트 (순수 Swift)
macos/                          IMKit 셸 + 후보창 + 스크립트
ios/                            SwiftUI 자판 (App/, Keyboard/, KeyboardModelTests/, project.yml, scripts/)
windows/                        1단계: Google IME 커스텀 테이블 / 2단계: 키 변환 브리지 (bridge/, Rust)
android/                        Kotlin IME + 모델 테스트 (JVM)
  app/                          IME 앱 + 입력기 서비스 + JNI 래퍼
    src/main/kotlin/            Composable UI + KanaTable + KanjiConverter 어댑터
    src/main/jniLibs/           arm64-v8a/x86_64 .so (엔진 빌드)
    src/test/                   모델 테스트 (JVM, 픽스처 공유)
  engine/                        Swift 엔진 소스 (크로스컴파일용)
  scripts/                       env.sh, setup-env.sh, build-engine.sh, install-emu.sh
```

```bash
swift test --package-path core-swift        # 매핑/조합 로직 전체 테스트 (57개)
cargo test --manifest-path windows/bridge/Cargo.toml   # Windows 브리지 변환 로직 (OS 무관)
./macos/scripts/install-dev.sh              # 빌드 + ~/Library/Input Methods 설치 + 프로세스 재시작
```

- 매핑 변경은 `spec/`에서 시작하고, 모든 플랫폼 포트는 같은 픽스처를 통과해야 합니다.
- 매핑 규칙은 전부 `core-swift/Tests/`의 골든 테스트로 고정되어 있습니다. 규칙을 바꾸면 테스트부터 고치세요.
- **IME 프로세스에 디버거를 붙이지 마세요** — 데스크톱 전체 키보드가 얼어붙습니다. 로직은 `swift test --package-path core-swift`로, 셸은 `NSLog` + Console.app으로 확인합니다.
- Xcode 프로젝트 없이 SwiftPM + 번들 조립 스크립트로 빌드합니다.

## 로드맵

- **iOS:** 완료 (시뮬레이터). 실기기는 무료 Apple 개발자 계정으로 7일 테스트 프로비저닝 가능.
- **Android:** 완료 (에뮬레이터). 엔진 빌드는 로컬 Swift 크로스컴파일, JVM은 CI 자동화.
- **Windows:** 1단계 완료(Google 일본어 입력 커스텀 테이블) + 2단계 완료(키 변환 브리지 — CI에서 exe 빌드·픽스처 conformance 검증). 실기기 실행 검증은 Windows 기기 확보 시.

상세한 설계는 [멀티플랫폼 설계 문서](docs/superpowers/specs/2026-07-31-hangulji-multiplatform-design.md)를 참고하세요.

## 현재 제한

- 개인용 설치 전용 (Developer ID 서명/공증/pkg 배포는 미지원)
- 가타카나 전용 모드 토글 없음 (변환 후보로 선택)
- ヴ, 단독 소문자 가나(ぁ ゃ ッ 등), 학습·사용자 사전, 설정 UI 미지원
- 문절 단위 부분 변환 미지원 (문장 전체 변환 후 후보 선택)

## 크레딧

- 한자 변환: [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) (MIT, 사전 Apache-2.0) — [azooKey](https://github.com/azooKey/azooKey-Desktop) 프로젝트의 변환 엔진
- 참고한 오픈소스 입력기: [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop), [macSKK](https://github.com/mtgto/macSKK), [hangeul_ime](https://github.com/AlienKevin/hangeul_ime), [macOS_IMKitSample_2021](https://github.com/ensan-hcl/macOS_IMKitSample_2021)
