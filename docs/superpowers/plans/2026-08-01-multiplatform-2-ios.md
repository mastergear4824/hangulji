# 멀티플랫폼 서브프로젝트 2: iOS 키보드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 커스텀 키보드(컨테이너 앱 + 키보드 익스텐션) — 2벌식 한글 키로 가나 철자를 치면 프리뷰에 가나가 표시되고, 변환 키로 한자 후보를 골라 입력한다. macOS와 동일한 코어·엔진 재사용.

**Architecture:** `ios/`에 XcodeGen(project.yml)으로 앱+익스텐션 2타깃 생성, 둘 다 `../core-swift` 패키지의 얇은 셸. 키보드 로직은 `KeyboardModel`(ObservableObject, `TextOutput` 프로토콜로 프록시 추상화 → 유닛테스트 가능)에 집중, UI는 SwiftUI `KeyboardView`. 키 버튼은 자모를 표시하되 **2벌식 라틴 문자를 전송**해 HanguljiComposer·픽스처를 무수정 재사용.

**Tech Stack:** Swift(언어모드 v5)/SwiftUI, XcodeGen 2.x, xcodebuild(시뮬레이터), AzooKeyKanaKanjiConverter(기존 의존성)

**Spec:** `docs/superpowers/specs/2026-07-31-hangulji-multiplatform-design.md` §5.2, §7(SP2 완료 정의)

## Global Constraints

- 확인된 환경: Xcode 26.6(`/Applications/Xcode.app`), xcodegen(`/opt/homebrew/bin`), iPhone 17 시뮬레이터. 배포 타깃 iOS 17.0
- `RequestsOpenAccess = false` 고정 (번들 사전·자체 샌드박스만 사용 — 스펙 §5.2)
- Zenzai 트레이트 사용 금지 (기본 사전 경로만)
- 익스텐션 번들 ID는 앱 번들 ID의 접두 확장: `com.mastergear.hangulji-ios` / `com.mastergear.hangulji-ios.keyboard`
- 코어 무수정: `core-swift/`·`spec/` 파일 변경 금지. 키 버튼→라틴 문자 매핑은 Keymap과 동일해야 한다(아래 표)
- 시뮬레이터 빌드만 (서명·실기기·스토어 비목표). xcodebuild에 `CODE_SIGNING_ALLOWED=NO`
- 생성물 `ios/Hangulji.xcodeproj`는 커밋하지 않는다(.gitignore) — project.yml이 원천, 빌드 스크립트가 xcodegen을 실행
- 커밋 메시지에 Co-Authored-By 트레일러 넣지 않는다
- 각 태스크 완료 전: 해당 검증 명령 + `swift test --package-path core-swift`(코어 회귀 55+) 통과

## 2벌식 키 → 라틴 문자 (UI 버튼 정의의 유일한 근거 — Keymap과 동일)

```
ㅂq ㅈw ㄷe ㄱr ㅅt ㅛy ㅕu ㅑi ㅐo ㅔp
ㅁa ㄴs ㅇd ㄹf ㅎg ㅗh ㅓj ㅏk ㅣl
ㅋz ㅌx ㅊc ㅍv ㅠb ㅜn ㅡm
시프트: ㅃQ ㅉW ㄸE ㄲR ㅆT ㅒO ㅖP (그 외 키는 시프트 무시)
```

## File Structure

```
ios/
├── project.yml
├── .gitignore                  # Hangulji.xcodeproj, build/
├── App/
│   ├── HanguljiApp.swift       # @main SwiftUI 앱 (설치 안내 + 테스트 입력창)
│   └── Info.plist (xcodegen info: 로 생성 선언)
├── Keyboard/
│   ├── KeyboardViewController.swift   # UIInputViewController + TextOutput
│   ├── KeyboardModel.swift            # 상태머신 (테스트 대상)
│   ├── KeyboardView.swift             # SwiftUI 레이아웃
│   └── GlobeButton.swift              # UIKit 지구본 키 래퍼
├── KeyboardModelTests/
│   └── KeyboardModelTests.swift
└── scripts/
    ├── build-sim.sh            # xcodegen + xcodebuild (시뮬레이터)
    └── install-sim.sh          # 부팅 + simctl install + 앱 실행
```

---

### Task 1: XcodeGen 스캐폴드 — 앱 셸 + 익스텐션 스텁이 시뮬레이터에서 돈다

**Files:**
- Create: `ios/project.yml`, `ios/.gitignore`, `ios/App/HanguljiApp.swift`, `ios/Keyboard/KeyboardViewController.swift`(스텁), `ios/scripts/build-sim.sh`, `ios/scripts/install-sim.sh`

**Interfaces:**
- Produces: 빌드·설치 파이프라인. `HanguljiKeyboard` 익스텐션이 시뮬레이터 설정의 키보드 목록에 나타난다. Task 2–3이 Keyboard/ 소스를 채운다.

- [ ] **Step 1: ios/project.yml 작성**

```yaml
name: Hangulji
options:
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
packages:
  hangulji-core:
    path: ../core-swift
targets:
  HanguljiApp:
    type: application
    platform: iOS
    sources: [App]
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: 한글지
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mastergear.hangulji-ios
        SWIFT_VERSION: "5.0"
        CODE_SIGN_IDENTITY: ""
        CODE_SIGNING_ALLOWED: "NO"
    dependencies:
      - target: HanguljiKeyboard
        embed: true
  HanguljiKeyboard:
    type: app-extension
    platform: iOS
    sources: [Keyboard]
    info:
      path: Keyboard/Info.plist
      properties:
        CFBundleDisplayName: 한글지
        NSExtension:
          NSExtensionPointIdentifier: com.apple.keyboard-service
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).KeyboardViewController
          NSExtensionAttributes:
            PrimaryLanguage: ja-JP
            RequestsOpenAccess: false
            IsASCIICapable: false
            PrefersRightToLeft: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mastergear.hangulji-ios.keyboard
        SWIFT_VERSION: "5.0"
        CODE_SIGN_IDENTITY: ""
        CODE_SIGNING_ALLOWED: "NO"
        APPLICATION_EXTENSION_API_ONLY: "YES"
    dependencies:
      - package: hangulji-core
        product: HanguljiCore
      - package: hangulji-core
        product: HanguljiConversion
  KeyboardModelTests:
    type: bundle.unit-test
    platform: iOS
    sources: [KeyboardModelTests, Keyboard]
    settings:
      base:
        SWIFT_VERSION: "5.0"
        CODE_SIGNING_ALLOWED: "NO"
    dependencies:
      - package: hangulji-core
        product: HanguljiCore
      - package: hangulji-core
        product: HanguljiConversion
schemes:
  HanguljiApp:
    build:
      targets: { HanguljiApp: all }
    test:
      targets: [KeyboardModelTests]
```

주: KeyboardModelTests는 익스텐션 소스를 직접 컴파일(호스트 앱 불요)하는 로직 테스트 번들. Keyboard/ 소스는 UIKit import가 있어도 시뮬레이터 테스트 번들에서 컴파일된다. Task 1 시점에는 KeyboardModelTests 디렉터리가 없으므로 **이 타깃·test 스킴 항목은 Task 2에서 추가**하고, 지금은 두 타깃+build 스킴만 넣는다.

`ios/.gitignore`:
```
Hangulji.xcodeproj/
build/
DerivedData/
```

- [ ] **Step 2: 앱 셸 작성** (`ios/App/HanguljiApp.swift`)

```swift
import SwiftUI

@main
struct HanguljiApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var testInput = ""

    var body: some View {
        NavigationStack {
            List {
                Section("설치") {
                    Text("설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → **한글지**")
                    Text("입력창에서 지구본 키를 길게 눌러 한글지로 전환")
                }
                Section("테스트") {
                    TextField("여기서 타이핑 테스트 (토우쿄우 → 変換 → 東京)", text: $testInput)
                }
                Section("입력 규칙 요약") {
                    Text("카=か 가=が (위치 무관) · 받침ㅅ=っ · 받침ㄴ=ん · 장음은 철자대로(토우쿄우) · を=워 は=하")
                }
            }
            .navigationTitle("한글지")
        }
    }
}
```

- [ ] **Step 3: 익스텐션 스텁 작성** (`ios/Keyboard/KeyboardViewController.swift`)

```swift
import UIKit

final class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = "한글지 (구현 중)"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 240),
        ])
    }
}
```

- [ ] **Step 4: 빌드/설치 스크립트 작성**

`ios/scripts/build-sim.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Hangulji.xcodeproj -scheme HanguljiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | tail -5
echo "built: build/Build/Products/Debug-iphonesimulator/HanguljiApp.app"
```

`ios/scripts/install-sim.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-sim.sh
xcrun simctl bootstatus "iPhone 17" -b
xcrun simctl install "iPhone 17" build/Build/Products/Debug-iphonesimulator/HanguljiApp.app
open -a Simulator
xcrun simctl launch "iPhone 17" com.mastergear.hangulji-ios || true
echo "설치 완료. 시뮬레이터 설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → 한글지"
```

`chmod +x ios/scripts/*.sh`

- [ ] **Step 5: 검증** — `./ios/scripts/build-sim.sh` → BUILD SUCCEEDED. `./ios/scripts/install-sim.sh` → 설치 성공, `xcrun simctl listapps "iPhone 17" | grep -A2 hangulji` 로 앱+익스텐션 등록 확인. 코어 회귀 `swift test --package-path core-swift` 통과.

- [ ] **Step 6: Commit** — `git add ios && git commit -m "feat(ios): XcodeGen 스캐폴드 — 앱 셸 + 키보드 익스텐션 스텁"`

---

### Task 2: KeyboardModel — 키보드 상태머신 (+유닛테스트)

**Files:**
- Create: `ios/Keyboard/KeyboardModel.swift`, `ios/KeyboardModelTests/KeyboardModelTests.swift`
- Modify: `ios/project.yml` (KeyboardModelTests 타깃 + test 스킴 추가 — Task 1 Step 1의 블록 그대로)

**Interfaces:**
- Consumes: `HanguljiComposer`, `KanjiConverter.candidateList(for:max:)` (core-swift)
- Produces (Task 3의 View가 소비):
  - `protocol TextOutput: AnyObject { func insertText(_ s: String); func deleteBackward() }`
  - `final class KeyboardModel: ObservableObject` — `@Published preview: String`, `@Published candidates: [String]`, `@Published selectedIndex: Int`, `@Published isShifted: Bool`, `weak var output: TextOutput?`, 메서드 `tapKey(_ latin: Character)`, `tapSpace()`, `tapEnter()`, `tapBackspace()`, `tapCandidate(_ index: Int)`, `tapSymbol(_ s: String)`(ー·。·、), `toggleShift()`

동작 의미론은 macOS 스펙 §3을 iOS 관례로 옮긴 것: 스페이스=변환 시작/다음 후보, 후보 탭=확정, Enter=조합 중이면 가나 확정·아니면 개행, 새 타이핑=현재 후보 확정 후 새 조합, 변환 불가(reading nil)면 markedText 그대로 확정. 시프트는 원샷(키 하나 입력 후 자동 해제).

- [ ] **Step 1: 실패하는 테스트 작성** (`ios/KeyboardModelTests/KeyboardModelTests.swift`)

```swift
import XCTest
// Keyboard/ 소스가 이 테스트 타깃에 직접 컴파일되므로 별도 import 불필요

final class FakeOutput: TextOutput {
    var inserted: [String] = []
    var deletions = 0
    func insertText(_ s: String) { inserted.append(s) }
    func deleteBackward() { deletions += 1 }
}

final class KeyboardModelTests: XCTestCase {
    private func makeModel() -> (KeyboardModel, FakeOutput) {
        let model = KeyboardModel()
        let out = FakeOutput()
        model.output = out
        return (model, out)
    }

    func testTypingShowsKanaPreview() {
        let (model, _) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }   // 토우쿄우
        XCTAssertEqual(model.preview, "とうきょう")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testShiftIsOneShot() {
        let (model, _) = makeModel()
        model.toggleShift()
        XCTAssertTrue(model.isShifted)
        model.tapKey("R")   // View가 시프트 상태의 라틴 대문자를 전달
        XCTAssertFalse(model.isShifted)
        XCTAssertEqual(model.preview, "ㄲ")
    }

    func testSpaceConverts() {
        let (model, _) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        XCTAssertFalse(model.candidates.isEmpty)
        XCTAssertTrue(model.candidates.contains("東京"), "\(model.candidates)")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.preview, model.candidates[0])
        model.tapSpace()   // 다음 후보
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.preview, model.candidates[1])
    }

    func testCandidateTapCommits() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        guard let tokyoIndex = model.candidates.firstIndex(of: "東京") else { return XCTFail() }
        model.tapCandidate(tokyoIndex)
        XCTAssertEqual(out.inserted, ["東京"])
        XCTAssertEqual(model.preview, "")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testEnterCommitsKanaWhileComposing() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapEnter()
        XCTAssertEqual(out.inserted, ["とうきょう"])
        XCTAssertEqual(model.preview, "")
    }

    func testEnterInsertsNewlineWhenIdle() {
        let (model, out) = makeModel()
        model.tapEnter()
        XCTAssertEqual(out.inserted, ["\n"])
    }

    func testTypingDuringSelectionCommitsCurrentCandidate() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        let first = model.candidates[0]
        model.tapKey("z")   // 새 타이핑
        XCTAssertEqual(out.inserted, [first])
        XCTAssertEqual(model.preview, "ㅋ")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testBackspaceJamoThenProxy() {
        let (model, out) = makeModel()
        model.tapKey("z"); model.tapKey("k")   // 카
        model.tapBackspace()                   // ㅏ 제거 → ㅋ
        XCTAssertEqual(model.preview, "ㅋ")
        model.tapBackspace()                   // 조합 비움
        XCTAssertEqual(model.preview, "")
        model.tapBackspace()                   // 프록시로 위임
        XCTAssertEqual(out.deletions, 1)
    }

    func testBackspaceCancelsSelection() {
        let (model, _) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        model.tapBackspace()
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(model.preview, "とうきょう")   // 가나로 복귀
    }

    func testSpaceWhenIdleInsertsSpace() {
        let (model, out) = makeModel()
        model.tapSpace()
        XCTAssertEqual(out.inserted, [" "])
    }

    func testUnmappableCommitsAsIs() {
        let (model, out) = makeModel()
        for ch in "quf" { model.tapKey(ch) }   // 별 (매핑 불가)
        model.tapSpace()                        // 변환 불가 → 그대로 확정
        XCTAssertEqual(out.inserted, ["별"])
    }

    func testSymbols() {
        let (model, out) = makeModel()
        model.tapSymbol("。")
        XCTAssertEqual(out.inserted, ["。"])
        for ch in "fk" { model.tapKey(ch) }    // 라
        model.tapSymbol("ー")                   // 조합 중 ー는 조합에 들어감
        XCTAssertEqual(model.preview, "らー")
        model.tapSymbol("。")                   // 조합 커밋 후 。
        XCTAssertEqual(out.inserted, ["。", "らー", "。"])
    }
}
```

- [ ] **Step 2: project.yml에 테스트 타깃 추가 후 테스트 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild -project Hangulji.xcodeproj -scheme HanguljiApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -15`
Expected: 컴파일 실패 ("cannot find 'KeyboardModel'")

- [ ] **Step 3: KeyboardModel.swift 구현**

```swift
// ios/Keyboard/KeyboardModel.swift
import Foundation
import HanguljiCore
import HanguljiConversion

protocol TextOutput: AnyObject {
    func insertText(_ s: String)
    func deleteBackward()
}

/// 키보드 상태머신. UIKit 비의존 — 유닛테스트 대상.
/// 의미론은 macOS 셸(스펙 §3)의 iOS 번역: 스페이스=변환/다음 후보, 후보 탭=확정.
final class KeyboardModel: ObservableObject {
    @Published private(set) var preview = ""
    @Published private(set) var candidates: [String] = []
    @Published private(set) var selectedIndex = 0
    @Published var isShifted = false

    weak var output: TextOutput?

    private var composer = HanguljiComposer()
    private static let converter = KanjiConverter()   // 사전 로드 무거움 — 공유 1회

    private var isSelecting: Bool { !candidates.isEmpty }

    func tapKey(_ latin: Character) {
        if isSelecting { commitCandidate(at: selectedIndex) }
        if composer.insert(latin) {
            isShifted = false
            refreshPreview()
        }
    }

    func toggleShift() { isShifted.toggle() }

    func tapSpace() {
        if isSelecting {
            selectedIndex = (selectedIndex + 1) % candidates.count
            preview = candidates[selectedIndex]
            return
        }
        guard !composer.isEmpty else {
            output?.insertText(" ")
            return
        }
        guard let reading = composer.reading else {
            commitComposition()   // 매핑 불가 포함 → 그대로 확정
            return
        }
        let list = Self.converter.candidateList(for: reading, max: 9)
        guard !list.isEmpty else { return }
        candidates = list
        selectedIndex = 0
        preview = list[0]
    }

    func tapCandidate(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        commitCandidate(at: index)
    }

    func tapEnter() {
        if isSelecting { return commitCandidate(at: selectedIndex) }
        if !composer.isEmpty { return commitComposition() }
        output?.insertText("\n")
    }

    func tapBackspace() {
        if isSelecting {   // 변환 취소 → 가나 조합으로 복귀
            candidates = []
            selectedIndex = 0
            refreshPreview()
            return
        }
        if composer.backspace() {
            refreshPreview()
        } else {
            output?.deleteBackward()
        }
    }

    func tapSymbol(_ s: String) {
        if isSelecting { commitCandidate(at: selectedIndex) }
        if s == "ー" {
            if composer.insert("-") { refreshPreview() }
            return
        }
        if !composer.isEmpty { commitComposition() }
        output?.insertText(s)
    }

    /// 포커스 이탈 등 — 조합 중이면 전부 확정
    func commitAll() {
        if isSelecting { return commitCandidate(at: selectedIndex) }
        if !composer.isEmpty { commitComposition() }
    }

    private func commitComposition() {
        output?.insertText(composer.markedText)
        composer.clear()
        refreshPreview()
    }

    private func commitCandidate(at index: Int) {
        output?.insertText(candidates[index])
        composer.clear()
        candidates = []
        selectedIndex = 0
        preview = ""
    }

    private func refreshPreview() { preview = composer.markedText }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: Task 2 Step 2와 같은 xcodebuild test 명령
Expected: `Test Suite 'All tests' passed` (12개). 최초 변환 테스트는 사전 로드로 수 초 걸릴 수 있음.

- [ ] **Step 5: Commit** — `git add ios && git commit -m "feat(ios): 키보드 상태머신 KeyboardModel + 유닛테스트"`

---

### Task 3: SwiftUI 키보드 UI + 컨트롤러 배선

**Files:**
- Create: `ios/Keyboard/KeyboardView.swift`, `ios/Keyboard/GlobeButton.swift`
- Modify: `ios/Keyboard/KeyboardViewController.swift` (스텁 → 본 구현)

**Interfaces:**
- Consumes: `KeyboardModel` 전체 공개 메서드 (Task 2)
- Produces: 완성된 키보드 익스텐션. 레이아웃(Global Constraints의 키 표 기준):
  - 후보/프리뷰 바(상단, 높이 44): 조합 중=preview 가나 표시, 선택 중=후보 가로 스크롤(선택 후보 강조, 탭=`tapCandidate`)
  - 1행 ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ / 2행 ㅁㄴㅇㄹㅎㅗㅓㅏㅣ / 3행 [⇧]ㅋㅌㅊㅍㅠㅜㅡ[⌫] / 4행 [🌐][ー][변환(스페이스)][。][⏎]
  - 시프트 시 1행 표시 ㅃㅉㄸㄲㅆ(q~t 위치)·ㅒㅖ(o·p 위치), 나머지 키는 동일
  - 키 탭은 라틴 문자 전송: 평상시 소문자, 시프트 시 해당 键만 대문자(QWERTOP)

- [ ] **Step 1: GlobeButton.swift 작성** (지구본 키는 UIKit 셀렉터 필수)

```swift
// ios/Keyboard/GlobeButton.swift
import SwiftUI
import UIKit

/// 키보드 전환 키 — handleInputModeList는 UIKit 타깃-액션이 필요해 래핑
struct GlobeButton: UIViewRepresentable {
    weak var controller: UIInputViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.backgroundColor = UIColor.secondarySystemBackground
        button.layer.cornerRadius = 6
        if let controller {
            button.addTarget(controller,
                             action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                             for: .allTouchEvents)
        }
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
```

- [ ] **Step 2: KeyboardView.swift 작성**

```swift
// ios/Keyboard/KeyboardView.swift
import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    weak var controller: KeyboardViewController?

    private let row1 = [("ㅂ", "q", "ㅃ", "Q"), ("ㅈ", "w", "ㅉ", "W"), ("ㄷ", "e", "ㄸ", "E"),
                        ("ㄱ", "r", "ㄲ", "R"), ("ㅅ", "t", "ㅆ", "T"), ("ㅛ", "y", "ㅛ", "y"),
                        ("ㅕ", "u", "ㅕ", "u"), ("ㅑ", "i", "ㅑ", "i"), ("ㅐ", "o", "ㅒ", "O"),
                        ("ㅔ", "p", "ㅖ", "P")]
    private let row2 = [("ㅁ", "a"), ("ㄴ", "s"), ("ㅇ", "d"), ("ㄹ", "f"), ("ㅎ", "g"),
                        ("ㅗ", "h"), ("ㅓ", "j"), ("ㅏ", "k"), ("ㅣ", "l")]
    private let row3 = [("ㅋ", "z"), ("ㅌ", "x"), ("ㅊ", "c"), ("ㅍ", "v"),
                        ("ㅠ", "b"), ("ㅜ", "n"), ("ㅡ", "m")]

    var body: some View {
        VStack(spacing: 6) {
            candidateBar
            keyRow(row1.map { model.isShifted ? ($0.2, $0.3) : ($0.0, $0.1) })
            keyRow(row2)
            HStack(spacing: 4) {
                controlKey(model.isShifted ? "⬆" : "⇧") { model.toggleShift() }
                keyRow(row3)
                controlKey("⌫") { model.tapBackspace() }
            }
            HStack(spacing: 4) {
                GlobeButton(controller: controller).frame(width: 44)
                controlKey("ー", width: 36) { model.tapSymbol("ー") }
                Button { model.tapSpace() } label: {
                    Text(model.candidates.isEmpty ? "변환·스페이스" : "다음 후보")
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(6)
                }
                controlKey("。", width: 36) { model.tapSymbol("。") }
                controlKey("⏎", width: 44) { model.tapEnter() }
            }
        }
        .padding(6)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var candidateBar: some View {
        Group {
            if model.candidates.isEmpty {
                Text(model.preview.isEmpty ? " " : model.preview)
                    .font(.system(size: 20))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
                            Button { model.tapCandidate(index) } label: {
                                Text(candidate)
                                    .font(.system(size: 20))
                                    .padding(.horizontal, 6)
                                    .background(index == model.selectedIndex
                                                ? Color.accentColor.opacity(0.25) : Color.clear)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: 44)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(6)
    }

    private func keyRow(_ keys: [(String, String)]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.1) { label, latin in
                Button { model.tapKey(Character(latin)) } label: {
                    Text(label)
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func controlKey(_ label: String, width: CGFloat? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18))
                .frame(minWidth: width ?? 44, minHeight: 42)
                .frame(maxWidth: width == nil ? 60 : width)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: KeyboardViewController 본 구현**

```swift
// ios/Keyboard/KeyboardViewController.swift
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, TextOutput {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.output = self
        let hostController = UIHostingController(
            rootView: KeyboardView(model: model, controller: self))
        host = hostController
        addChild(hostController)
        view.addSubview(hostController.view)
        hostController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: 300),
        ])
        hostController.didMove(toParent: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.commitAll()   // 포커스 이탈 시 조합 확정
        super.viewWillDisappear(animated)
    }

    // MARK: TextOutput
    func insertText(_ s: String) { textDocumentProxy.insertText(s) }
    func deleteBackward() { textDocumentProxy.deleteBackward() }
}
```

- [ ] **Step 4: 빌드·테스트·설치 검증**

```bash
./ios/scripts/build-sim.sh
cd ios && xcodebuild -project Hangulji.xcodeproj -scheme HanguljiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5; cd ..
./ios/scripts/install-sim.sh
```

Expected: BUILD SUCCEEDED, 테스트 12개 통과, 설치 성공.

- [ ] **Step 5: Commit** — `git add ios && git commit -m "feat(ios): SwiftUI 2벌식 키보드 UI + 컨트롤러 — iOS MVP"`

---

### Task 4: CI 확장 + 문서 + 최종 검증

**Files:**
- Modify: `.github/workflows/core.yml` (ios 잡 추가), `README.md` (iOS 설치 섹션 + 로드맵 갱신)

- [ ] **Step 1: core.yml에 ios 잡 추가** (기존 swift 잡 뒤에)

```yaml
  ios:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - uses: actions/cache@v4
        with:
          path: ios/build
          key: ios-${{ runner.os }}-${{ hashFiles('core-swift/Package.resolved') }}
      - name: Build (simulator)
        run: |
          cd ios && xcodegen generate
          xcodebuild -project Hangulji.xcodeproj -scheme HanguljiApp \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | tail -5
      - name: Model tests
        run: |
          cd ios && xcodebuild -project Hangulji.xcodeproj -scheme HanguljiApp \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -derivedDataPath build CODE_SIGNING_ALLOWED=NO test | tail -5
```

주: 러너의 시뮬레이터 기기명은 로컬(iPhone 17)과 다를 수 있어 iPhone 16으로 지정. 러너 실패 시 `xcrun simctl list devices available`을 잡에 추가해 실제 기기명으로 조정한다.

- [ ] **Step 2: README 갱신** — 설치 섹션을 macOS/iOS로 나누고 iOS: `./ios/scripts/install-sim.sh`(시뮬레이터) + 시뮬레이터 설정에서 키보드 추가 안내. 로드맵에서 iOS를 "완료(시뮬레이터)"로 이동, 실기기는 무료 프로비저닝(7일)로 가능하다고 명시. 개발 섹션 구조 트리의 `ios/` 항목을 "예정"에서 실제 구조로.

- [ ] **Step 3: 최종 검증** — Task 3 Step 4의 세 명령 + `swift test --package-path core-swift` 전부 통과. `python3 -c "import yaml..."` 또는 ruby로 core.yml 문법 확인.

- [ ] **Step 4: Commit** — `git add .github README.md && git commit -m "ci(ios): 시뮬레이터 빌드·테스트 잡 + README iOS 안내"`

---

## Self-Review 결과

1. **스펙 커버리지**: 설계 §5.2의 전 항목 — XcodeGen ✓(T1), 자체 SwiftUI UI ✓(T3), 엔진 직접 링크·Zenzai 미사용 ✓(project.yml 트레이트 미지정=기본), RequestsOpenAccess=false ✓(T1 plist), 시뮬레이터 루프 ✓(T1 스크립트), 메모리 실기기 검증 보류 ✓(비목표 유지). §7 SP2 완료 정의(시뮬레이터에서 토우쿄우→東京)는 T3 설치 후 수동 확인 항목 — 자동화 가능한 부분(모델 테스트의 東京 후보 검증)은 T2에 포함.
2. **플레이스홀더**: 없음. 전 태스크 실코드.
3. **타입 일관성**: `TextOutput`(T2 정의 ↔ T3 컨트롤러 채택), `KeyboardModel` 공개 메서드(T2 ↔ T3 View 호출: tapKey/tapSpace/tapEnter/tapBackspace/tapCandidate/tapSymbol/toggleShift/commitAll) 대조 완료. `KeyboardView(model:controller:)` 시그니처 T3 내부 일치. 테스트 타깃명 KeyboardModelTests(T2 project.yml ↔ 디렉터리) 일치. `@testable import HanguljiKeyboard` — 익스텐션 모듈명은 타깃명과 동일 ✓ (KeyboardModelTests 타깃이 Keyboard/ 소스를 직접 포함하므로 실제로는 자기 모듈 — @testable 불필요하지만 무해... **수정**: 소스 직접 포함 방식에서는 `@testable import` 제거 필요. 테스트 파일 첫 줄을 `@testable import HanguljiKeyboard` 대신 import 없음(동일 타깃 컴파일)으로 한다. → 테스트 코드의 import 줄을 `import XCTest`만 남기도록 반영했다고 간주하고 구현 시 그대로 따를 것.)
4. **검산**: 시프트 케이스 "R"→ㄲ ✓ (Keymap R=ㄲ). testSymbols 시퀀스: 。(빈 조합→직접 삽입), 라(fk), ー(조합 포함→らー), 。(조합 らー 커밋 후 。) → inserted ["。","らー","。"] ✓.
