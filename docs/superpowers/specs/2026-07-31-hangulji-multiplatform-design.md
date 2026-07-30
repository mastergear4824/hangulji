# Hangulji 멀티플랫폼 확장 설계

날짜: 2026-07-31
상태: 승인됨 (서브프로젝트 1 구현 계획 대기)
상위 문서: [2026-07-31-hangulji-ime-design.md](2026-07-31-hangulji-ime-design.md) — 입력 방식·매핑 규칙의 원 스펙 (전 플랫폼 공통 규범)

## 1. 개요

macOS에서 완성된 한글지(한글로 일본어 입력 + 한자 변환)를 **iOS, Android, Windows**로 확장한다. 사용자 결정:

- **전 플랫폼 처음부터 한자 변환 지원** (가나 전용 MVP 없음)
- 테스트 환경: 실기기·계정 없음 → 전부 시뮬레이터/에뮬레이터/CI 기반, 실기기 검증은 보류
- 매핑 규칙은 기존 스펙 §4를 전 플랫폼이 동일하게 따른다 — 플랫폼별 방언 금지

## 2. 전략 요약 (리서치 근거)

| 플랫폼 | 셸 | 한자 엔진 | 근거 |
|---|---|---|---|
| macOS | IMKit (완성) | AzooKeyKanaKanjiConverter | 완료 |
| iOS | 키보드 익스텐션 (Swift) | **같은 엔진 그대로** | azooKey iOS가 같은 엔진을 익스텐션 내에서 실전 운용 중. mmap 사전 샤딩으로 메모리 제한(~60-70MB) 해결됨 |
| Android | InputMethodService (Kotlin) | **같은 엔진을 Swift .so + JNI로** | 엔진 자체 CI가 2024년부터 Android 크로스컴파일+에뮬레이터 테스트 수행. Swift 6.3(2026.3) 공식 Android SDK |
| Windows | 1단계: Google 일본어 입력 커스텀 로마자 테이블<br>2단계: 키 변환 브리지 (Rust) | **호스트 IME(Google/MS)의 변환을 그대로 사용** | 커스텀 테이블은 코드 제로. 브리지는 일본 엄지시프트 커뮤니티(DvorakJ·yamabuki·Benizara)가 수십 년 검증한 패턴. 밑바닥 TSF IME는 솔로 기준 수개월~수년 + 실기기 없음 → 배제 |

Windows 대안 비교(기각 사유): mozc 포크(조합 테이블 교체) — 완전한 독립 IME가 되지만 Bazel 대형 코드베이스 + VM 없는 디버깅 부담; TSF 신규 개발 — COM 인터페이스 100+, 검증 불가. 나중에 "진짜 Windows IME"가 필요해지면 mozc 포크가 1순위.

## 3. 저장소 구조

```
hangulji/
├── spec/                        # ★ 단일 진실 원천
│   ├── mapping.tsv              # 한글 음절 → 가나 전체 매핑 (기본표+별칭+확장)
│   ├── fixtures/                # 언어 중립 골든 픽스처 (JSON)
│   │   ├── composition.json     # 키 시퀀스 → 음절 분해 (자모 automaton)
│   │   └── kana.json            # 키 시퀀스 → 가나 출력 (문장 골든 포함)
│   ├── SPEC.md                  # automaton 상태·전이 명세 (포팅 지침)
│   └── generators/              # TSV → 각 언어 상수/산출물 생성기 (Swift 스크립트)
│       ├── gen-swift.swift      #   → core-swift 테이블 상수
│       ├── gen-kotlin.swift     #   → android 테이블 상수
│       └── gen-mozc-table.swift #   → windows/ Google IME 로마자 테이블
├── core-swift/                  # 공용 Swift 패키지 (기존 Package.swift 이동)
│   ├── Sources/HanguljiCore/            # 레퍼런스 구현 (불변의 기준)
│   ├── Sources/HanguljiConversion/
│   └── Tests/                           # 기존 테스트 + 픽스처 러너
├── macos/                       # 기존 IMKit 앱 (Sources/Hangulji, AppBundle, scripts 이동)
├── ios/                         # 컨테이너 앱 + 키보드 익스텐션
├── android/                     # Kotlin IMS + JNI + Swift .so 빌드
├── windows/                     # 1단계 테이블 + 가이드, 2단계 브리지
├── docs/
└── .github/workflows/           # conformance CI
```

## 4. 코어 동일성 보장 (conformance)

CommonMark/toml-test/Unicode 방식 — 공유 바이너리가 아니라 **공유 픽스처**로 동일성을 강제한다 (300줄 코어에 Rust FFI/KMP는 인프라가 본체보다 커짐 — 기각).

- `spec/mapping.tsv`가 유일한 매핑 정의. 각 언어의 테이블 상수는 생성기로 만든다 (수기 수정 금지)
- `spec/fixtures/*.json`: 기존 53개 골든을 언어 중립 포맷으로 변환한 것 + 이후 추가분
  ```json
  { "name": "tokyo", "keys": "xhdnzydn", "kana": "とうきょう", "fullyMapped": true }
  ```
- **Swift 구현이 레퍼런스**: 매핑·규칙 변경은 반드시 spec(TSV/픽스처) → Swift → 다른 포트 순서로 전파
- 각 플랫폼 포트는 자기 언어의 픽스처 러너 테스트를 가지며, CI에서 같은 픽스처 디렉터리를 읽는다
- 픽스처 확장: Swift 레퍼런스를 property-test로 두드려 출력을 새 골든으로 녹화

## 5. 플랫폼별 설계

### 5.1 macOS (재구성만)

`git mv`로 이동(히스토리 보존): Package.swift·Sources·Tests → `core-swift/`(공용부)와 `macos/`(IMKit 셸·AppBundle·scripts). 동작 변경 없음 — 이동 후 53개 테스트 통과 + `install-dev.sh` 정상 동작이 완료 조건. KanaMapper의 테이블 리터럴은 생성기 산출물로 대체하되 결과가 바이트 동일해야 한다.

### 5.2 iOS

- 구조: 컨테이너 앱(SwiftUI, 설정·안내) + 키보드 익스텐션. 둘 다 `core-swift/` 패키지의 얇은 셸
- 프로젝트 생성: **XcodeGen** (`project.yml` 선언형 — .xcodeproj 수기 관리 회피)
- 키보드 UI: 자체 SwiftUI 2벌식 레이아웃 + 후보 바 (KeyboardKit은 v10부터 유료화 — 기각. azooKey의 MIT 키보드 뷰 코드를 참고)
- 엔진: KanaKanjiConverterModuleWithDefaultDictionary를 익스텐션에 직접 링크, Zenzai 트레이트 미사용, 사전은 익스텐션 번들 리소스
- `RequestsOpenAccess = false` (번들 사전 + 익스텐션 자체 샌드박스 저장이라 Full Access 불요 — 프라이버시 스토리 우수)
- 개발 루프: 시뮬레이터 (설정→키보드 추가→글로브 전환). **한계: 시뮬레이터는 메모리 제한(jetsam)을 강제하지 않음 → 실기기 검증 항목으로 명시 보류**

### 5.3 Android

- 셸: Kotlin `InputMethodService` + Compose UI (2벌식 레이아웃 + 후보 바). 아키텍처 참고: FlorisBoard(Apache-2.0 — 코드 인용 가능), HeliBoard는 GPL이라 열람만
- 자모 automaton + 매핑: **Kotlin 이디엄 포트** (~1-2일 규모, 테이블은 생성기 산출물, 픽스처 러너로 동일성 검증)
- 한자 엔진: AzooKeyKanaKanjiConverter를 Swift Android SDK(6.3)로 arm64-v8a/x86_64 `.so` 빌드, `@_cdecl` C 심(~200줄: init/setKana/getCandidates/select) + Kotlin JNI 래퍼. 사전은 assets로 번들
- 개발 루프: CLI 전용 (sdkmanager/avdmanager/gradle/adb — Android Studio 불요). `adb shell ime enable/set`으로 활성화
- **리스크(프로그램 전체에서 최대)**: Swift-on-Android는 신생. 폴백 순서: ① 엔진 버전 고정 + CI의 검증된 빌드 레시피 복제 → ② libmozc.so (bazel oss_android, JNI 재구성 부담 큼)

### 5.4 Windows

- **1단계 (코드 제로, 즉시 한자)**: `spec/mapping.tsv` → Google 일본어 입력 로마자 테이블(input/output/next-input 상태머신) 생성기 작성. 산출물 = 테이블 파일 + 설치 가이드(Google 일본어 입력 설치 → 테이블 import → 영문 자판에서 한글지 방식 타이핑). 받침·복합모음을 next-input 체인으로 인코딩. 표현력 한계로 인코딩 불가한 규칙(있다면)은 가이드에 명시
- **2단계 (설치형 브리지)**: Rust WH_KEYBOARD_LL 훅 앱 (~1-2k LOC) — 2벌식 키입력을 로마자 키스트림으로 변환해 활성 일본어 IME에 주입. LLKHF_INJECTED 재귀 방지, 훅 타임아웃, 관리자 창·보안 데스크톱 한계는 문서화. 자체 토글 키 유지. CI(windows-2022 러너)로 빌드·서명 없는 exe 산출
- **검증 한계 (정직하게)**: Windows 기기가 없어 1·2단계 모두 **실행 검증 불가**. CI 빌드 + 유닛테스트(브리지의 변환 로직은 픽스처 러너로 검증 가능)까지가 이 프로젝트의 책임 범위이고, 실사용 검증은 Windows 사용자/기기 확보 후

## 6. Conformance CI (.github/workflows)

- `core.yml`: macOS 러너 — core-swift 전체 테스트(픽스처 러너 포함) + 생성기 산출물 최신성 검사(생성 후 diff 없어야 함)
- `android.yml`: ubuntu 러너 — Kotlin 유닛테스트(픽스처 러너) + gradle assembleDebug; Swift .so 크로스컴파일
- `windows.yml`: windows-2022 러너 — 브리지 빌드 + 변환 로직 픽스처 테스트 (2단계부터)
- iOS는 core.yml의 macOS 러너에서 시뮬레이터 빌드로 커버

## 7. 구축 순서와 완료 정의

| # | 서브프로젝트 | 완료 정의 |
|---|---|---|
| 1 | 재구성 + spec 추출 | 새 구조에서 53개 테스트 전부 통과, 생성기 산출물 = 기존 테이블과 동일, macOS 입력기 재설치 후 정상, conformance CI 녹색 |
| 2 | iOS | 시뮬레이터에서 한글지 키보드로 토우쿄우→東京 입력 성공 |
| 3 | Windows 1단계 | 생성된 테이블 + 가이드 커밋, 인코딩 커버리지 문서화 (실행 검증은 보류 명시) |
| 4 | Android | 에뮬레이터에서 한글지 키보드로 토우쿄우→東京 입력 성공 |
| 5 | Windows 2단계 | CI에서 브리지 exe 빌드 + 변환 로직 픽스처 테스트 통과 |

각 서브프로젝트는 독립된 계획(writing-plans) → 구현 → 리뷰 사이클로 진행한다.

## 8. 리스크

| 리스크 | 대응 |
|---|---|
| Swift Android SDK 신생 (Android 엔진) | 엔진 저장소의 검증된 CI 레시피 복제, 버전 고정. 폴백: libmozc |
| iOS 익스텐션 메모리 (실기기 검증 불가) | azooKey가 같은 엔진·같은 제약에서 운용 중이라는 선례에 의존. Zenzai 미사용으로 여유 확보. 실기기 확보 시 최우선 검증 |
| Google IME 테이블 표현력 (별칭·받침 전부 인코딩 가능한가) | 생성기 작성 시 커버리지 리포트 산출 — 인코딩 불가 규칙은 명시 문서화 |
| Windows 실행 검증 불가 | 책임 범위를 CI 빌드+로직 테스트로 한정 (완료 정의에 반영) |
| 4개 포트 간 매핑 드리프트 | spec 픽스처를 CI 필수 게이트로 — 구조적으로 드리프트 불가 |

## 9. 비목표

- 스토어 배포 (App Store/Play/서명·공증) — 전부 로컬/사이드로드 설치
- Zenzai 신경망 변환, 학습·개인 사전 동기화, 설정 UI 고도화
- Windows 밑바닥 TSF IME / mozc 포크 (필요해지면 별도 프로젝트)
- 태블릿/가로모드 UI 최적화 (기본 동작만)
