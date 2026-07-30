# Hangulji macOS IME Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 한글 자판으로 일본어 가나 철자를 치면(토우쿄우) 가나(とうきょう)로 실시간 표시되고 스페이스로 한자 변환(東京)까지 되는 macOS 입력기.

**Architecture:** 순수 Swift SPM 라이브러리(HanguljiCore: 자모 조합 + 가나 매핑, 전부 유닛테스트)를 얇은 IMKit 셸(Hangulji.app)이 감싸고, 한자 변환은 AzooKeyKanaKanjiConverter SPM 패키지에 위임한다. Xcode 프로젝트 없이 SPM + 수동 .app 번들 조립 스크립트로 빌드한다(전 과정 CLI 자동화, 유닛테스트 CLI 실행 가능).

**Tech Stack:** Swift (언어 모드 5), SwiftPM, InputMethodKit, AppKit(셸만), AzooKeyKanaKanjiConverter (MIT)

**Spec:** `docs/superpowers/specs/2026-07-31-hangulji-ime-design.md` — 매핑 규칙·키 동작·Info.plist 키의 근거는 전부 스펙 §3–§5.

## Global Constraints

- 플랫폼: macOS 14+ (`.macOS(.v14)`), Swift 6.x 툴체인 + **언어 모드 `.v5`** (IMKit은 Swift 6 strict concurrency와 상극 — 스펙 §5)
- 번들 ID: `com.mastergear.inputmethod.Hangulji` (`.inputmethod.` 포함 필수)
- `InputMethodConnectionName` = `com.mastergear.inputmethod.Hangulji_Connection` (정확히 `<번들ID>_Connection` 패턴)
- 외부 의존성은 `AzooKeyKanaKanjiConverter` 하나만, `.upToNextMinor` 고정. HanguljiCore 타깃은 **AppKit/Foundation 외 의존성 금지, `import AppKit` 금지**
- `IMKCandidates` 사용 금지 — 후보창은 자체 NSPanel (스펙 §2.3)
- IME 프로세스에 디버거 부착 금지(데스크톱 키보드 얼어붙음) — 로직 검증은 `swift test`, 셸은 `NSLog` + Console.app
- 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 커밋 전 `swift test` 통과 확인

## File Structure

```
hangulji/
├── Package.swift                       # 루트 SPM 패키지 (라이브러리+실행파일+테스트)
├── .gitignore
├── Sources/
│   ├── HanguljiCore/                   # 순수 Swift, AppKit 금지
│   │   ├── Jamo.swift                  # 자모 enum + 2벌식 키맵
│   │   ├── JamoComposer.swift          # 자모→음절 조합 automaton
│   │   ├── KanaMapper.swift            # 음절→가나 테이블
│   │   ├── HanguljiComposer.swift      # 셸이 쓰는 파사드 (문자 입력→마크드텍스트/reading)
│   │   └── Katakana.swift              # 히라가나→가타카나 변환
│   ├── HanguljiConversion/
│   │   └── KanjiConverter.swift        # AzooKeyKanaKanjiConverter 어댑터
│   └── Hangulji/                       # 실행파일 (IMKit 셸)
│       ├── main.swift                  # NSApplication + IMKServer 기동
│       ├── HanguljiInputController.swift
│       └── CandidatePanel.swift        # 자체 후보창 NSPanel
├── Tests/HanguljiCoreTests/
│   ├── KeymapTests.swift
│   ├── JamoComposerTests.swift
│   ├── KanaMapperTests.swift
│   ├── HanguljiComposerTests.swift
│   └── KatakanaTests.swift
├── Tests/HanguljiConversionTests/
│   └── KanjiConverterTests.swift       # 사전 로드 통합 테스트
├── AppBundle/
│   └── Info.plist                      # 수동 관리 (SPM은 plist 생성 안 함)
└── scripts/
    ├── make-icon.swift                 # 메뉴바 아이콘 tiff 생성 (1회성)
    ├── build-app.sh                    # swift build + .app 번들 조립 + ad-hoc 서명
    └── install-dev.sh                  # ~/Library/Input Methods 설치 + killall
```

---

### Task 1: SPM 패키지 스캐폴드 + 자모 모델 + 2벌식 키맵

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/HanguljiCore/Jamo.swift`, `Tests/HanguljiCoreTests/KeymapTests.swift`

**Interfaces:**
- Produces: `enum Consonant: Character` (choseong 정규 순서로 선언), `enum Vowel: Character` (jungseong 정규 순서), `enum Jamo { case consonant(Consonant); case vowel(Vowel) }`, `enum Keymap { static func jamo(for: Character) -> Jamo? }`

- [ ] **Step 1: Package.swift와 .gitignore 작성**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HanguljiCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HanguljiCoreTests",
            dependencies: ["HanguljiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`.gitignore`:
```
.build/
build/
.DS_Store
*.xcodeproj
```

- [ ] **Step 2: 실패하는 키맵 테스트 작성** (`Tests/HanguljiCoreTests/KeymapTests.swift`)

```swift
import XCTest
@testable import HanguljiCore

final class KeymapTests: XCTestCase {
    func testLowercaseConsonants() {
        XCTAssertEqual(Keymap.jamo(for: "q"), .consonant(.b))   // ㅂ
        XCTAssertEqual(Keymap.jamo(for: "r"), .consonant(.g))   // ㄱ
        XCTAssertEqual(Keymap.jamo(for: "t"), .consonant(.s))   // ㅅ
        XCTAssertEqual(Keymap.jamo(for: "d"), .consonant(.ng))  // ㅇ
        XCTAssertEqual(Keymap.jamo(for: "z"), .consonant(.k))   // ㅋ
        XCTAssertEqual(Keymap.jamo(for: "g"), .consonant(.h))   // ㅎ
    }
    func testVowels() {
        XCTAssertEqual(Keymap.jamo(for: "k"), .vowel(.a))    // ㅏ
        XCTAssertEqual(Keymap.jamo(for: "h"), .vowel(.o))    // ㅗ
        XCTAssertEqual(Keymap.jamo(for: "n"), .vowel(.u))    // ㅜ
        XCTAssertEqual(Keymap.jamo(for: "m"), .vowel(.eu))   // ㅡ
        XCTAssertEqual(Keymap.jamo(for: "l"), .vowel(.i))    // ㅣ
        XCTAssertEqual(Keymap.jamo(for: "y"), .vowel(.yo))   // ㅛ
    }
    func testShiftedKeys() {
        XCTAssertEqual(Keymap.jamo(for: "Q"), .consonant(.bb)) // ㅃ
        XCTAssertEqual(Keymap.jamo(for: "R"), .consonant(.gg)) // ㄲ
        XCTAssertEqual(Keymap.jamo(for: "T"), .consonant(.ss)) // ㅆ
        XCTAssertEqual(Keymap.jamo(for: "W"), .consonant(.jj)) // ㅉ
        XCTAssertEqual(Keymap.jamo(for: "E"), .consonant(.dd)) // ㄸ
        XCTAssertEqual(Keymap.jamo(for: "P"), .vowel(.ye))     // ㅖ
        // 별도 배정 없는 대문자는 소문자와 동일
        XCTAssertEqual(Keymap.jamo(for: "A"), .consonant(.m))  // ㅁ
    }
    func testNonHangulKeysReturnNil() {
        XCTAssertNil(Keymap.jamo(for: "1"))
        XCTAssertNil(Keymap.jamo(for: " "))
        XCTAssertNil(Keymap.jamo(for: "-"))
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 실패 ("cannot find 'Keymap'" 류)

- [ ] **Step 4: Jamo.swift 구현**

```swift
// Sources/HanguljiCore/Jamo.swift

/// 초성(choseong) 유니코드 정규 순서로 선언 — allCases 인덱스가 곧 초성 인덱스
public enum Consonant: Character, CaseIterable {
    case g = "ㄱ", gg = "ㄲ", n = "ㄴ", d = "ㄷ", dd = "ㄸ", r = "ㄹ", m = "ㅁ"
    case b = "ㅂ", bb = "ㅃ", s = "ㅅ", ss = "ㅆ", ng = "ㅇ", j = "ㅈ", jj = "ㅉ"
    case ch = "ㅊ", k = "ㅋ", t = "ㅌ", p = "ㅍ", h = "ㅎ"
}

/// 중성(jungseong) 유니코드 정규 순서로 선언
public enum Vowel: Character, CaseIterable {
    case a = "ㅏ", ae = "ㅐ", ya = "ㅑ", yae = "ㅒ", eo = "ㅓ", e = "ㅔ"
    case yeo = "ㅕ", ye = "ㅖ", o = "ㅗ", wa = "ㅘ", wae = "ㅙ", oe = "ㅚ"
    case yo = "ㅛ", u = "ㅜ", wo = "ㅝ", we = "ㅞ", wi = "ㅟ", yu = "ㅠ"
    case eu = "ㅡ", ui = "ㅢ", i = "ㅣ"
}

public enum Jamo: Equatable {
    case consonant(Consonant)
    case vowel(Vowel)
}

/// 2벌식 키맵: 라틴 문자(하드웨어 자판) → 자모
public enum Keymap {
    private static let table: [Character: Jamo] = [
        "q": .consonant(.b), "w": .consonant(.j), "e": .consonant(.d), "r": .consonant(.g),
        "t": .consonant(.s), "y": .vowel(.yo), "u": .vowel(.yeo), "i": .vowel(.ya),
        "o": .vowel(.ae), "p": .vowel(.e),
        "a": .consonant(.m), "s": .consonant(.n), "d": .consonant(.ng), "f": .consonant(.r),
        "g": .consonant(.h), "h": .vowel(.o), "j": .vowel(.eo), "k": .vowel(.a), "l": .vowel(.i),
        "z": .consonant(.k), "x": .consonant(.t), "c": .consonant(.ch), "v": .consonant(.p),
        "b": .vowel(.yu), "n": .vowel(.u), "m": .vowel(.eu),
        "Q": .consonant(.bb), "W": .consonant(.jj), "E": .consonant(.dd), "R": .consonant(.gg),
        "T": .consonant(.ss), "O": .vowel(.yae), "P": .vowel(.ye),
    ]

    public static func jamo(for ch: Character) -> Jamo? {
        if let j = table[ch] { return j }
        // 별도 배정 없는 대문자는 소문자와 동일 취급
        if ch.isUppercase, let lower = ch.lowercased().first { return table[lower] }
        return nil
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources/ Tests/
git commit -m "feat: SPM 스캐폴드 + 자모 모델 + 2벌식 키맵

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: JamoComposer — 자모→음절 조합 automaton

**Files:**
- Create: `Sources/HanguljiCore/JamoComposer.swift`, `Tests/HanguljiCoreTests/JamoComposerTests.swift`

**Interfaces:**
- Consumes: `Jamo`, `Consonant`, `Vowel` (Task 1)
- Produces:
  - `struct Syllable: Equatable { var initial: Consonant?; var vowel: Vowel?; var final: Consonant?; var hangul: String }`
  - `struct JamoComposer { private(set) var jamos: [Jamo]; mutating func append(_: Jamo); @discardableResult mutating func backspace() -> Bool; mutating func clear(); var syllables: [Syllable]; var isEmpty: Bool }`

핵심 동작(스펙 §2.1): 받침 재해석 — ㄱㅏㄴㅣ는 [가,니](모음이 오면 받침이 다음 음절 초성으로), ㄱㅏㄴㅇㅣ는 [간,이](초성 ㅇ이 명시돼 있으므로). 백스페이스는 자모 1개 단위(전체 스트림 유지 후 재계산 — 스트림이 짧으므로 매번 재계산이 가장 단순·정확).

- [ ] **Step 1: 실패하는 테스트 작성** (`Tests/HanguljiCoreTests/JamoComposerTests.swift`)

```swift
import XCTest
@testable import HanguljiCore

final class JamoComposerTests: XCTestCase {
    private func compose(_ jamos: [Jamo]) -> [Syllable] {
        var c = JamoComposer()
        jamos.forEach { c.append($0) }
        return c.syllables
    }

    func testSimpleSyllable() {
        // ㅋㅏ → 카
        let s = compose([.consonant(.k), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["카"])
    }
    func testBatchimReanalysisOnVowel() {
        // ㄱㅏㄴㅣ → 가니 (받침 ㄴ이 모음 앞에서 초성으로 이동)
        let s = compose([.consonant(.g), .vowel(.a), .consonant(.n), .vowel(.i)])
        XCTAssertEqual(s.map(\.hangul), ["가", "니"])
    }
    func testExplicitNgKeepsBatchim() {
        // ㄱㅏㄴㅇㅣ → 간이 (かんい/かに 구분의 핵심)
        let s = compose([.consonant(.g), .vowel(.a), .consonant(.n), .consonant(.ng), .vowel(.i)])
        XCTAssertEqual(s.map(\.hangul), ["간", "이"])
    }
    func testCompoundVowelWo() {
        // ㅇㅜㅓ → 워 (を 전용 음절)
        let s = compose([.consonant(.ng), .vowel(.u), .vowel(.eo)])
        XCTAssertEqual(s.map(\.hangul), ["워"])
    }
    func testCompoundVowelHwa() {
        // ㅎㅗㅏ → 화
        let s = compose([.consonant(.h), .vowel(.o), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["화"])
    }
    func testUncombinableVowelStartsNewSyllable() {
        // ㅋㅏㅏ → 카 + 독립모음 ㅏ (조합 불가 → 새 요소)
        let s = compose([.consonant(.k), .vowel(.a), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["카", "ㅏ"])
    }
    func testConsonantAfterFinalFlushes() {
        // ㅅㅏㅅㅍㅗ → 삿 + 포 (받침 뒤 자음은 새 음절)
        let s = compose([.consonant(.s), .vowel(.a), .consonant(.s), .consonant(.p), .vowel(.o)])
        XCTAssertEqual(s.map(\.hangul), ["삿", "포"])
    }
    func testDoubleConsonantCannotBeFinal() {
        // ㄸ는 받침 불가: ㅋㅏㄸㅏ → 카 + 따
        let s = compose([.consonant(.k), .vowel(.a), .consonant(.dd), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["카", "따"])
    }
    func testLoneConsonant() {
        // ㅋ 하나 → 미완성 음절 ㅋ
        XCTAssertEqual(compose([.consonant(.k)]).map(\.hangul), ["ㅋ"])
    }
    func testBackspaceRemovesOneJamo() {
        var c = JamoComposer()
        [Jamo.consonant(.g), .vowel(.a), .consonant(.n)].forEach { c.append($0) }
        XCTAssertEqual(c.syllables.map(\.hangul), ["간"])
        XCTAssertTrue(c.backspace())
        XCTAssertEqual(c.syllables.map(\.hangul), ["가"])
        XCTAssertTrue(c.backspace())
        XCTAssertEqual(c.syllables.map(\.hangul), ["ㄱ"])
        XCTAssertTrue(c.backspace())
        XCTAssertTrue(c.isEmpty)
        XCTAssertFalse(c.backspace())
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 실패 ("cannot find 'JamoComposer'")

- [ ] **Step 3: JamoComposer.swift 구현**

```swift
// Sources/HanguljiCore/JamoComposer.swift

public struct Syllable: Equatable {
    public var initial: Consonant?
    public var vowel: Vowel?
    public var final: Consonant?

    public init(initial: Consonant? = nil, vowel: Vowel? = nil, final: Consonant? = nil) {
        self.initial = initial
        self.vowel = vowel
        self.final = final
    }

    /// 종성 인덱스 (유니코드 한글 조합 공식용). ㄸㅃㅉ은 종성 불가 → nil
    private static let jongseongIndex: [Consonant: Int] = [
        .g: 1, .gg: 2, .n: 4, .d: 7, .r: 8, .m: 16, .b: 17, .s: 19, .ss: 20,
        .ng: 21, .j: 22, .ch: 23, .k: 24, .t: 25, .p: 26, .h: 27,
    ]

    static func canBeFinal(_ c: Consonant) -> Bool { jongseongIndex[c] != nil }

    /// 화면 표시용 한글 (완성형 블록, 미완성이면 자모 낱자)
    public var hangul: String {
        if let i = initial, let v = vowel {
            let ci = Consonant.allCases.firstIndex(of: i)!
            let vi = Vowel.allCases.firstIndex(of: v)!
            let fi = final.flatMap { Self.jongseongIndex[$0] } ?? 0
            let code = 0xAC00 + (ci * 21 + vi) * 28 + fi
            return String(UnicodeScalar(code)!)
        }
        if let i = initial { return String(i.rawValue) }
        if let v = vowel { return String(v.rawValue) }
        return ""
    }
}

public struct JamoComposer {
    public private(set) var jamos: [Jamo] = []

    public init() {}

    public var isEmpty: Bool { jamos.isEmpty }

    public mutating func append(_ jamo: Jamo) { jamos.append(jamo) }

    @discardableResult
    public mutating func backspace() -> Bool {
        guard !jamos.isEmpty else { return false }
        jamos.removeLast()
        return true
    }

    public mutating func clear() { jamos.removeAll() }

    /// 모음 조합 (일본어 표기에 필요한 것 + 표준 몇 개)
    private static let vowelCombinations: [Vowel: [Vowel: Vowel]] = [
        .o: [.a: .wa, .ae: .wae, .i: .oe],
        .u: [.eo: .wo, .e: .we, .i: .wi],
        .eu: [.i: .ui],
    ]

    /// 자모 스트림 전체를 다시 조합 (스트림이 짧으므로 매번 재계산)
    public var syllables: [Syllable] {
        var result: [Syllable] = []
        var cur = Syllable()

        func flush() {
            if cur != Syllable() { result.append(cur) }
            cur = Syllable()
        }

        for jamo in jamos {
            switch jamo {
            case .consonant(let c):
                if cur.vowel == nil {
                    if cur.initial == nil {
                        cur.initial = c
                    } else {
                        flush()
                        cur.initial = c
                    }
                } else if cur.initial != nil, cur.final == nil, Syllable.canBeFinal(c) {
                    cur.final = c
                } else {
                    flush()
                    cur.initial = c
                }
            case .vowel(let v):
                if let f = cur.final {
                    // 받침 재해석: 받침을 다음 음절 초성으로
                    cur.final = nil
                    flush()
                    cur.initial = f
                    cur.vowel = v
                } else if cur.vowel == nil {
                    cur.vowel = v
                } else if let combined = Self.vowelCombinations[cur.vowel!]?[v] {
                    cur.vowel = combined
                } else {
                    flush()
                    cur.vowel = v
                }
            }
        }
        flush()
        return result
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: PASS (전체)

- [ ] **Step 5: Commit**

```bash
git add Sources/HanguljiCore/JamoComposer.swift Tests/HanguljiCoreTests/JamoComposerTests.swift
git commit -m "feat: 자모→음절 조합 automaton (받침 재해석 포함)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: KanaMapper — 음절→가나 매핑 테이블

**Files:**
- Create: `Sources/HanguljiCore/KanaMapper.swift`, `Tests/HanguljiCoreTests/KanaMapperTests.swift`

**Interfaces:**
- Consumes: `Syllable`, `Consonant`, `Vowel` (Task 1–2)
- Produces:
  - `struct MappedSyllable: Equatable { let display: String; let isMapped: Bool }`
  - `enum KanaMapper { static func map(_: [Syllable]) -> [MappedSyllable] }`

매핑 표는 스펙 §4 전체를 코드로 옮긴 것. **여기의 테이블이 이 프로젝트의 심장이다** — 스펙 표와 한 글자라도 다르면 안 된다.

- [ ] **Step 1: 실패하는 테스트 작성** (`Tests/HanguljiCoreTests/KanaMapperTests.swift`)

```swift
import XCTest
@testable import HanguljiCore

final class KanaMapperTests: XCTestCase {
    /// 편의: 한글 문자열 → 음절 배열 (완성형 분해)
    private func syllables(_ text: String) -> [Syllable] {
        text.unicodeScalars.map { scalar in
            let code = Int(scalar.value) - 0xAC00
            precondition(code >= 0 && code < 11172, "완성형 한글만: \(scalar)")
            let ci = code / (21 * 28), vi = (code % (21 * 28)) / 28, fi = code % 28
            let finals: [Int: Consonant] = [1: .g, 2: .gg, 4: .n, 7: .d, 8: .r, 16: .m,
                                            17: .b, 19: .s, 20: .ss, 21: .ng, 22: .j, 23: .ch,
                                            24: .k, 25: .t, 26: .p, 27: .h]
            return Syllable(initial: Consonant.allCases[ci],
                            vowel: Vowel.allCases[vi],
                            final: fi == 0 ? nil : finals[fi])
        }
    }
    private func kana(_ text: String) -> String {
        KanaMapper.map(syllables(text)).map(\.display).joined()
    }

    // 기본표 (스펙 §4.1) — 행별 골든
    func testVowelRow()      { XCTAssertEqual(kana("아이우에오야유요와워"), "あいうえおやゆよわを") }
    func testKRow()          { XCTAssertEqual(kana("카키쿠케코캬큐쿄"), "かきくけこきゃきゅきょ") }
    func testGRow()          { XCTAssertEqual(kana("가기구게고갸규교"), "がぎぐげごぎゃぎゅぎょ") }
    func testSRow()          { XCTAssertEqual(kana("사시스세소샤슈쇼"), "さしすせそしゃしゅしょ") }
    func testZRow()          { XCTAssertEqual(kana("자지즈제조쟈쥬죠"), "ざじずぜぞじゃじゅじょ") }
    func testTRow()          { XCTAssertEqual(kana("타치츠테토챠츄쵸"), "たちつてとちゃちゅちょ") }
    func testDRow()          { XCTAssertEqual(kana("다데도띠뜨"), "だでどぢづ") }
    func testNRow()          { XCTAssertEqual(kana("나니누네노냐뉴뇨"), "なにぬねのにゃにゅにょ") }
    func testHRow()          { XCTAssertEqual(kana("하히후헤호햐휴효"), "はひふへほひゃひゅひょ") }
    func testBRow()          { XCTAssertEqual(kana("바비부베보뱌뷰뵤"), "ばびぶべぼびゃびゅびょ") }
    func testPRow()          { XCTAssertEqual(kana("파피푸페포퍄퓨표"), "ぱぴぷぺぽぴゃぴゅぴょ") }
    func testMRow()          { XCTAssertEqual(kana("마미무메모먀뮤묘"), "まみむめもみゃみゅみょ") }
    func testRRow()          { XCTAssertEqual(kana("라리루레로랴류료"), "らりるれろりゃりゅりょ") }

    // 받침 (스펙 §4.1) — 청탁 규칙은 받침과 무관: 칸=かん, 간=がん
    func testFinalN()        {
        XCTAssertEqual(kana("칸"), "かん")
        XCTAssertEqual(kana("간"), "がん")
    }
    func testFinalSSokuon()  { XCTAssertEqual(kana("삿포로"), "さっぽろ") }
    func testFinalAliases()  {
        XCTAssertEqual(kana("혹카이도"), "ほっかいど")   // 받침 ㄱ → っ
        XCTAssertEqual(kana("잇파이"), "いっぱい")       // 받침 ㅅ → っ
        XCTAssertEqual(kana("망가"), "まんが")           // 받침 ㅇ → ん
        XCTAssertEqual(kana("돔부리"), "どんぶり")       // 받침 ㅁ → ん
    }

    // 관용 별칭 (스펙 §4.2)
    func testTenseAliases()  {
        XCTAssertEqual(kana("까"), "か")
        XCTAssertEqual(kana("홋까이도우"), "ほっかいどう")
        XCTAssertEqual(kana("빠"), "ぱ")
        XCTAssertEqual(kana("따"), "た")
        XCTAssertEqual(kana("싸"), "さ")
    }
    func testTsuVariants()   {
        XCTAssertEqual(kana("츠"), "つ")
        XCTAssertEqual(kana("쓰"), "つ")
        XCTAssertEqual(kana("쯔"), "つ")
    }
    func testJjRow()         {
        XCTAssertEqual(kana("찌"), "ち")
        XCTAssertEqual(kana("짜"), "ちゃ")   // ~짱 습관
    }
    func testChAliases()     {
        XCTAssertEqual(kana("차"), "ちゃ")
        XCTAssertEqual(kana("추"), "ちゅ")
        XCTAssertEqual(kana("초"), "ちょ")
    }
    func testUEuEquivalence() {
        XCTAssertEqual(kana("수"), "す")
        XCTAssertEqual(kana("주"), "ず")
        XCTAssertEqual(kana("흐"), "ふ")
        XCTAssertEqual(kana("크"), "く")
    }

    // 확장 가타카나 음절 (스펙 §4.3) — 히라가나 소문자 조합으로 출력
    func testExtendedSyllables() {
        XCTAssertEqual(kana("티"), "てぃ")
        XCTAssertEqual(kana("디"), "でぃ")
        XCTAssertEqual(kana("투"), "とぅ")
        XCTAssertEqual(kana("두"), "どぅ")
        XCTAssertEqual(kana("화"), "ふぁ")
        XCTAssertEqual(kana("휘"), "ふぃ")
        XCTAssertEqual(kana("훼"), "ふぇ")
        XCTAssertEqual(kana("훠"), "ふぉ")
        XCTAssertEqual(kana("위"), "うぃ")
        XCTAssertEqual(kana("웨"), "うぇ")
    }

    // 자↔쟈 구분 유지 (스펙 §4.4)
    func testZaVsJa() {
        XCTAssertEqual(kana("자"), "ざ")
        XCTAssertEqual(kana("쟈"), "じゃ")
    }

    // 매핑 불가 음절은 한글 그대로 + isMapped=false (스펙 §3)
    func testUnmappableSyllable() {
        let mapped = KanaMapper.map(syllables("별"))
        XCTAssertEqual(mapped, [MappedSyllable(display: "별", isMapped: false)])
        // 받침 ㄹ은 매핑 불가 → 몸통이 매핑 가능해도 음절 전체 불가
        let mapped2 = KanaMapper.map(syllables("갈"))
        XCTAssertEqual(mapped2, [MappedSyllable(display: "갈", isMapped: false)])
    }

    // 미완성 음절 (조합 중): 자모 낱자 표시, isMapped=false
    func testIncompleteSyllable() {
        let mapped = KanaMapper.map([Syllable(initial: .k)])
        XCTAssertEqual(mapped, [MappedSyllable(display: "ㅋ", isMapped: false)])
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 실패 ("cannot find 'KanaMapper'")

- [ ] **Step 3: KanaMapper.swift 구현**

```swift
// Sources/HanguljiCore/KanaMapper.swift

public struct MappedSyllable: Equatable {
    public let display: String
    public let isMapped: Bool

    public init(display: String, isMapped: Bool) {
        self.display = display
        self.isMapped = isMapped
    }
}

public enum KanaMapper {
    private struct BodyKey: Hashable {
        let initial: Consonant
        let vowel: Vowel
    }

    /// 스펙 §4.1(기본표) + §4.2(별칭) + §4.3(확장) 전체.
    /// 행(초성)별로 [모음: 가나] — 스펙 표와 1:1 대응하도록 유지할 것.
    private static let rows: [(Consonant, [Vowel: String])] = [
        (.ng, [.a: "あ", .i: "い", .u: "う", .e: "え", .o: "お",
               .ya: "や", .yu: "ゆ", .yo: "よ", .wa: "わ", .wo: "を",
               .wi: "うぃ", .we: "うぇ"]),
        (.k,  [.a: "か", .i: "き", .u: "く", .e: "け", .o: "こ",
               .ya: "きゃ", .yu: "きゅ", .yo: "きょ", .eu: "く"]),
        (.gg, [.a: "か", .i: "き", .u: "く", .e: "け", .o: "こ",
               .ya: "きゃ", .yu: "きゅ", .yo: "きょ", .eu: "く"]),
        (.g,  [.a: "が", .i: "ぎ", .u: "ぐ", .e: "げ", .o: "ご",
               .ya: "ぎゃ", .yu: "ぎゅ", .yo: "ぎょ", .eu: "ぐ"]),
        (.s,  [.a: "さ", .i: "し", .eu: "す", .u: "す", .e: "せ", .o: "そ",
               .ya: "しゃ", .yu: "しゅ", .yo: "しょ"]),
        (.ss, [.a: "さ", .i: "し", .eu: "つ", .e: "せ", .o: "そ"]),  // 쓰=つ 예외
        (.j,  [.a: "ざ", .i: "じ", .eu: "ず", .u: "ず", .e: "ぜ", .o: "ぞ",
               .ya: "じゃ", .yu: "じゅ", .yo: "じょ"]),
        (.jj, [.a: "ちゃ", .i: "ち", .eu: "つ", .yu: "ちゅ", .yo: "ちょ"]),
        (.ch, [.a: "ちゃ", .ya: "ちゃ", .u: "ちゅ", .yu: "ちゅ", .o: "ちょ", .yo: "ちょ",
               .i: "ち", .eu: "つ"]),
        (.t,  [.a: "た", .e: "て", .o: "と", .i: "てぃ", .u: "とぅ", .eu: "とぅ"]),
        (.dd, [.a: "た", .e: "て", .o: "と", .i: "ぢ", .eu: "づ"]),
        (.d,  [.a: "だ", .e: "で", .o: "ど", .i: "でぃ", .u: "どぅ", .eu: "どぅ"]),
        (.h,  [.a: "は", .i: "ひ", .u: "ふ", .eu: "ふ", .e: "へ", .o: "ほ",
               .ya: "ひゃ", .yu: "ひゅ", .yo: "ひょ",
               .wa: "ふぁ", .wi: "ふぃ", .we: "ふぇ", .wo: "ふぉ"]),
        (.b,  [.a: "ば", .i: "び", .u: "ぶ", .eu: "ぶ", .e: "べ", .o: "ぼ",
               .ya: "びゃ", .yu: "びゅ", .yo: "びょ"]),
        (.bb, [.a: "ぱ", .i: "ぴ", .u: "ぷ", .eu: "ぷ", .e: "ぺ", .o: "ぽ",
               .ya: "ぴゃ", .yu: "ぴゅ", .yo: "ぴょ"]),
        (.p,  [.a: "ぱ", .i: "ぴ", .u: "ぷ", .eu: "ぷ", .e: "ぺ", .o: "ぽ",
               .ya: "ぴゃ", .yu: "ぴゅ", .yo: "ぴょ"]),
        (.n,  [.a: "な", .i: "に", .u: "ぬ", .eu: "ぬ", .e: "ね", .o: "の",
               .ya: "にゃ", .yu: "にゅ", .yo: "にょ"]),
        (.m,  [.a: "ま", .i: "み", .u: "む", .eu: "む", .e: "め", .o: "も",
               .ya: "みゃ", .yu: "みゅ", .yo: "みょ"]),
        (.r,  [.a: "ら", .i: "り", .u: "る", .eu: "る", .e: "れ", .o: "ろ",
               .ya: "りゃ", .yu: "りゅ", .yo: "りょ"]),
    ]

    private static let bodyTable: [BodyKey: String] = {
        var table: [BodyKey: String] = [:]
        for (initial, vowels) in rows {
            for (vowel, kana) in vowels {
                table[BodyKey(initial: initial, vowel: vowel)] = kana
            }
        }
        return table
    }()

    /// 받침 → っ/ん (스펙 §4.1–4.2). 그 외 받침은 매핑 불가.
    private static let finalTable: [Consonant: String] = [
        .n: "ん", .ng: "ん", .m: "ん",
        .s: "っ", .g: "っ", .b: "っ", .d: "っ",
    ]

    public static func map(_ syllables: [Syllable]) -> [MappedSyllable] {
        syllables.map { syllable in
            guard let initial = syllable.initial, let vowel = syllable.vowel,
                  let body = bodyTable[BodyKey(initial: initial, vowel: vowel)]
            else {
                return MappedSyllable(display: syllable.hangul, isMapped: false)
            }
            if let final = syllable.final {
                guard let finalKana = finalTable[final] else {
                    return MappedSyllable(display: syllable.hangul, isMapped: false)
                }
                return MappedSyllable(display: body + finalKana, isMapped: true)
            }
            return MappedSyllable(display: body, isMapped: true)
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: PASS (전체)

- [ ] **Step 5: Commit**

```bash
git add Sources/HanguljiCore/KanaMapper.swift Tests/HanguljiCoreTests/KanaMapperTests.swift
git commit -m "feat: 음절→가나 매핑 테이블 (기본표+별칭+확장, 스펙 §4)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: HanguljiComposer 파사드 + 문장 골든 테스트

**Files:**
- Create: `Sources/HanguljiCore/HanguljiComposer.swift`, `Tests/HanguljiCoreTests/HanguljiComposerTests.swift`

**Interfaces:**
- Consumes: `Keymap`, `JamoComposer`, `KanaMapper` (Task 1–3)
- Produces (셸이 사용하는 유일한 Core 진입점):
  - `struct HanguljiComposer { mutating func insert(_ ch: Character) -> Bool; @discardableResult mutating func backspace() -> Bool; mutating func clear(); var isEmpty: Bool; var markedText: String; var reading: String? }`
  - `insert`는 소비했으면 true (한글 자모 키 + `-`). `.`/`,`/공백/영숫자는 false → 셸이 처리.
  - `markedText`: 가나 + 매핑불가 한글 혼합 표시용. `reading`: **전부** 매핑됐을 때만 가나 문자열, 아니면 nil (변환 가능 여부 판단용).

- [ ] **Step 1: 실패하는 테스트 작성** (`Tests/HanguljiCoreTests/HanguljiComposerTests.swift`)

```swift
import XCTest
@testable import HanguljiCore

final class HanguljiComposerTests: XCTestCase {
    /// 라틴 키 시퀀스를 입력 (2벌식 자판 기준)
    private func type(_ keys: String) -> HanguljiComposer {
        var c = HanguljiComposer()
        for ch in keys { _ = c.insert(ch) }
        return c
    }

    func testMarkedTextIsKana() {
        // 토우쿄우 = xh dn zy dn
        XCTAssertEqual(type("xhdnzydn").markedText, "とうきょう")
    }
    func testReadingWhenFullyMapped() {
        XCTAssertEqual(type("xhdnzydn").reading, "とうきょう")
    }
    func testReadingNilWhenUnmappable() {
        // quf = ㅂㅕㄹ → 별: ㅕ는 일본어에 없음 → 매핑 불가 → reading nil, 한글 그대로 노출
        let c = type("quf")
        XCTAssertNil(c.reading)
        XCTAssertEqual(c.markedText, "별")
    }
    func testProlongedSoundMark() {
        // 라-멘: fk - aps
        var c = HanguljiComposer()
        for ch in "fk" { XCTAssertTrue(c.insert(ch)) }
        XCTAssertTrue(c.insert("-"))
        for ch in "aps" { _ = c.insert(ch) }
        XCTAssertEqual(c.markedText, "らーめん")
        XCTAssertEqual(c.reading, "らーめん")
    }
    func testNonJamoKeysNotConsumed() {
        var c = HanguljiComposer()
        XCTAssertFalse(c.insert("1"))
        XCTAssertFalse(c.insert("."))
        XCTAssertFalse(c.insert(" "))
        XCTAssertTrue(c.isEmpty)
    }
    func testBackspaceJamoLevel() {
        var c = type("xhdn")           // ㅌㅗㅇㅜ → 토우 → とう
        XCTAssertEqual(c.markedText, "とう")
        XCTAssertTrue(c.backspace())   // ㅜ 삭제 → ㅌㅗㅇ은 '통'으로 재조합 → とん
        // (2벌식 표준 동작: 토우 타이핑 중에도 '통(とん)' 상태를 지나간다)
        XCTAssertEqual(c.markedText, "とん")
        XCTAssertTrue(c.backspace())   // ㅇ 제거 → 토 → と
        XCTAssertEqual(c.markedText, "と")
    }
    func testClear() {
        var c = type("xhdn")
        c.clear()
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(c.markedText, "")
    }

    // ── 문장 골든 (스펙 §7) ──
    private func kana(_ keys: String) -> String { type(keys).markedText }

    func testSentenceGoldens() {
        XCTAssertEqual(kana("xhdnzydnsldlzlaktm"), "とうきょうにいきます")   // 토우쿄우니이키마스
        XCTAssertEqual(kana("dkfl rkxhdnrhwkdlaktm".replacingOccurrences(of: " ", with: "")),
                       "ありがとうございます")                                // 아리가토우고자이마스
        XCTAssertEqual(kana("zhsslclgk"), "こんにちは")                       // 콘니치하 (こ=콘, は는 철자대로 '하')
        XCTAssertEqual(kana("rktRhdn"), "がっこう")                           // 갓코우
        XCTAssertEqual(kana("tkttlqnfl"), "さっしぶり")                       // 삿시부리 (받침 ㅅ→っ; 부=qn)
        XCTAssertEqual(kana("dhspdptkd"), "おねえさん")                       // 오네에상 (네=sp; 장음+받침ㅇ→ん)
        XCTAssertEqual(kana("dhdhtkzk"), "おおさか")                          // 오오사카
        XCTAssertEqual(kana("dpdlrk"), "えいが")                              // 에이가
        XCTAssertEqual(kana("rkdnjdlaktm"), "がをいます")                     // 가워이마스 → を 확인 (가=が)
    }
}
```

**주의:** 골든 테스트의 키 시퀀스는 2벌식 배열로 검산할 것 (예: 토=xh, 우=dn, 쿄=zy, 니=sl, 이=dl, 키=zl, 마=ak, 스=tm). 구현 단계에서 시퀀스 오타가 발견되면 **키 시퀀스를** 고치고(기대 가나 문자열이 정답의 기준), 스펙 표와 대조한다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 실패 ("cannot find 'HanguljiComposer'")

- [ ] **Step 3: HanguljiComposer.swift 구현**

```swift
// Sources/HanguljiCore/HanguljiComposer.swift

/// 셸(IMKit 컨트롤러)이 사용하는 파사드.
/// 내부 스트림은 자모와 기호(ー)의 혼합 — 백스페이스가 자모 1개 단위로 동작한다.
public struct HanguljiComposer {
    private enum Token: Equatable {
        case jamo(Jamo)
        case prolonged // ー
    }

    private var tokens: [Token] = []

    public init() {}

    public var isEmpty: Bool { tokens.isEmpty }

    /// 문자를 소비했으면 true. 자모 키와 '-'만 소비한다.
    public mutating func insert(_ ch: Character) -> Bool {
        if let jamo = Keymap.jamo(for: ch) {
            tokens.append(.jamo(jamo))
            return true
        }
        if ch == "-" {
            tokens.append(.prolonged)
            return true
        }
        return false
    }

    @discardableResult
    public mutating func backspace() -> Bool {
        guard !tokens.isEmpty else { return false }
        tokens.removeLast()
        return true
    }

    public mutating func clear() { tokens.removeAll() }

    /// 자모 연속 구간별로 조합→매핑하고 ー를 사이에 끼운다.
    private var mappedElements: [MappedSyllable] {
        var elements: [MappedSyllable] = []
        var composer = JamoComposer()

        func flushJamoRun() {
            guard !composer.isEmpty else { return }
            elements.append(contentsOf: KanaMapper.map(composer.syllables))
            composer.clear()
        }

        for token in tokens {
            switch token {
            case .jamo(let j):
                composer.append(j)
            case .prolonged:
                flushJamoRun()
                elements.append(MappedSyllable(display: "ー", isMapped: true))
            }
        }
        flushJamoRun()
        return elements
    }

    /// 조합 중 표시 문자열 (가나 + 매핑불가 한글 혼합)
    public var markedText: String {
        mappedElements.map(\.display).joined()
    }

    /// 전부 매핑됐을 때만 가나 reading, 아니면 nil (한자 변환 가능 여부)
    public var reading: String? {
        let elements = mappedElements
        guard !elements.isEmpty, elements.allSatisfy(\.isMapped) else { return nil }
        return elements.map(\.display).joined()
    }
}
```

- [ ] **Step 4: 테스트 실행, 골든 키 시퀀스 검산**

Run: `swift test 2>&1 | tail -30`
Expected: PASS. 실패 시 실패한 골든의 키 시퀀스를 2벌식 표로 손 검산(위 주의사항)하고, 시퀀스 오류면 테스트를, 매핑 오류면 KanaMapper 테이블을 스펙과 대조해 수정.

- [ ] **Step 5: Commit**

```bash
git add Sources/HanguljiCore/HanguljiComposer.swift Tests/HanguljiCoreTests/HanguljiComposerTests.swift
git commit -m "feat: 입력 파사드 + 문장 골든 테스트

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 가타카나 변환 헬퍼

**Files:**
- Create: `Sources/HanguljiCore/Katakana.swift`, `Tests/HanguljiCoreTests/KatakanaTests.swift`

**Interfaces:**
- Produces: `extension String { func toKatakana() -> String }` (히라가나만 가타카나로, 그 외 문자 보존)

후보창에서 "가타카나 후보"를 만들 때 사용 (스펙 §4.3 — 가타카나는 후보창으로 1차 해결).

- [ ] **Step 1: 실패하는 테스트 작성** (`Tests/HanguljiCoreTests/KatakanaTests.swift`)

```swift
import XCTest
@testable import HanguljiCore

final class KatakanaTests: XCTestCase {
    func testBasicConversion() {
        XCTAssertEqual("とうきょう".toKatakana(), "トウキョウ")
        XCTAssertEqual("らーめん".toKatakana(), "ラーメン")   // ー 보존
        XCTAssertEqual("ふぁ".toKatakana(), "ファ")          // 소문자 가나 포함
    }
    func testNonHiraganaPreserved() {
        XCTAssertEqual("東京abc".toKatakana(), "東京abc")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test 2>&1 | tail -10`
Expected: 컴파일 실패

- [ ] **Step 3: Katakana.swift 구현**

```swift
// Sources/HanguljiCore/Katakana.swift

public extension String {
    /// 히라가나(U+3041–U+3096)를 가타카나(+0x60)로. 그 외 문자는 보존.
    func toKatakana() -> String {
        String(String.UnicodeScalarView(unicodeScalars.map { scalar in
            if (0x3041...0x3096).contains(scalar.value) {
                return UnicodeScalar(scalar.value + 0x60)!
            }
            return scalar
        }))
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/HanguljiCore/Katakana.swift Tests/HanguljiCoreTests/KatakanaTests.swift
git commit -m "feat: 히라가나→가타카나 변환 헬퍼

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: KanjiConverter — AzooKeyKanaKanjiConverter 어댑터

**Files:**
- Modify: `Package.swift` (의존성 + HanguljiConversion 타깃 + 테스트 타깃 추가)
- Create: `Sources/HanguljiConversion/KanjiConverter.swift`, `Tests/HanguljiConversionTests/KanjiConverterTests.swift`

**Interfaces:**
- Consumes: `String.toKatakana()` (Task 5)
- Produces: `final class KanjiConverter { init(); func candidateList(for reading: String, max: Int) -> [String] }` — 한자 후보들 + 가나 원문 + 가타카나를 중복 제거해 순서대로 반환. **셸(Task 9)은 이 시그니처만 사용.**

**주의:** 이 패키지는 pre-1.0이라 `ConvertRequestOptions` 파라미터 목록이 마이너 버전마다 다를 수 있다. 아래 코드는 v0.11 기준 — 컴파일 에러가 나면 `.build/checkouts/AzooKeyKanaKanjiConverter/README.md`와 `Sources/KanaKanjiConverterModule/ConvertRequestOptions.swift`를 열어 실제 시그니처에 맞추되, **N_best·learningType(.nothing)·기본 사전 사용이라는 의도는 유지**한다. 최초 `swift package resolve`는 사전 데이터 때문에 수 분 걸릴 수 있다.

- [ ] **Step 1: Package.swift에 의존성과 타깃 추가**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", .upToNextMinor(from: "0.11.0")),
    ],
    targets: [
        .target(
            name: "HanguljiCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "HanguljiConversion",
            dependencies: [
                "HanguljiCore",
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary",
                         package: "AzooKeyKanaKanjiConverter"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HanguljiCoreTests",
            dependencies: ["HanguljiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HanguljiConversionTests",
            dependencies: ["HanguljiConversion"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

주: `0.11.0`이 존재하지 않으면 `swift package resolve` 에러 메시지가 알려주는 최신 0.x 마이너로 조정한다 (예: `.upToNextMinor(from: "0.12.0")`).

- [ ] **Step 2: 실패하는 통합 테스트 작성** (`Tests/HanguljiConversionTests/KanjiConverterTests.swift`)

```swift
import XCTest
@testable import HanguljiConversion

final class KanjiConverterTests: XCTestCase {
    func testTokyoConversion() {
        let converter = KanjiConverter()
        let candidates = converter.candidateList(for: "とうきょう", max: 9)
        XCTAssertTrue(candidates.contains("東京"), "candidates: \(candidates)")
        XCTAssertTrue(candidates.contains("とうきょう"), "가나 원문 후보 포함")
        XCTAssertTrue(candidates.contains("トウキョウ"), "가타카나 후보 포함")
    }
    func testSentenceConversion() {
        let converter = KanjiConverter()
        let candidates = converter.candidateList(for: "とうきょうにいきます", max: 9)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.contains("東京") }, "candidates: \(candidates)")
    }
    func testNoDuplicates() {
        let converter = KanjiConverter()
        let candidates = converter.candidateList(for: "とうきょう", max: 9)
        XCTAssertEqual(candidates.count, Set(candidates).count)
    }
}
```

- [ ] **Step 3: 테스트 실패 확인 (의존성 해석 포함)**

Run: `swift test --filter HanguljiConversionTests 2>&1 | tail -20`
Expected: 컴파일 실패 ("cannot find 'KanjiConverter'"). 의존성 해석/빌드에 수 분 소요될 수 있음.

- [ ] **Step 4: KanjiConverter.swift 구현**

```swift
// Sources/HanguljiConversion/KanjiConverter.swift
import Foundation
import HanguljiCore
import KanaKanjiConverterModuleWithDefaultDictionary

/// AzooKeyKanaKanjiConverter 어댑터.
/// pre-1.0 API 변동을 이 파일 한 곳에 가둔다 — 셸은 candidateList(for:max:)만 안다.
public final class KanjiConverter {
    private let converter = KanaKanjiConverter.withDefaultDictionary()

    public init() {}

    public func candidateList(for reading: String, max: Int = 9) -> [String] {
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)

        let options: ConvertRequestOptions = .withDefaultDictionary(
            N_best: max,
            requireJapanesePrediction: false,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: FileManager.default.temporaryDirectory,
            sharedContainerURL: FileManager.default.temporaryDirectory,
            metadata: nil
        )
        let results = converter.requestCandidates(composing, options: options)

        var seen = Set<String>()
        var list: [String] = []
        for text in results.mainResults.map(\.text) + [reading, reading.toKatakana()] {
            if seen.insert(text).inserted { list.append(text) }
        }
        return Array(list.prefix(max + 2))  // 한자 max개 + 가나/가타카나 폴백
    }
}
```

- [ ] **Step 5: 테스트 통과 확인 (API 시그니처 조정 포함)**

Run: `swift test --filter HanguljiConversionTests 2>&1 | tail -10`
Expected: PASS. `ConvertRequestOptions` 컴파일 에러 시 위 "주의"대로 실제 시그니처에 맞춰 수정 후 재실행. `requestCandidates`가 MainActor 격리를 요구하면 `KanjiConverter`를 `@MainActor final class`로 바꾸고 테스트 메서드에 `@MainActor`를 붙인다 (셸은 어차피 메인 스레드).

- [ ] **Step 6: 전체 테스트 회귀 확인**

Run: `swift test 2>&1 | tail -5`
Expected: PASS (전체)

- [ ] **Step 7: Commit**

```bash
git add Package.swift Package.resolved Sources/HanguljiConversion/ Tests/HanguljiConversionTests/
git commit -m "feat: AzooKeyKanaKanjiConverter 어댑터 (한자 후보 + 가나/가타카나 폴백)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 앱 번들 스캐폴드 — main.swift + Info.plist + 빌드/설치 스크립트 + 스텁 컨트롤러

**Files:**
- Modify: `Package.swift` (executable 타깃 추가)
- Create: `Sources/Hangulji/main.swift`, `Sources/Hangulji/HanguljiInputController.swift` (스텁), `AppBundle/Info.plist`, `scripts/make-icon.swift`, `scripts/build-app.sh`, `scripts/install-dev.sh`

**Interfaces:**
- Consumes: 없음 (이 태스크는 IME 등록 인프라만)
- Produces: `~/Library/Input Methods/Hangulji.app` 설치 파이프라인. `HanguljiInputController`는 Task 8이 본문을 채울 껍데기.

- [ ] **Step 1: Package.swift에 executable 타깃 추가** (targets 배열에 추가)

```swift
        .executableTarget(
            name: "Hangulji",
            dependencies: ["HanguljiCore", "HanguljiConversion"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
```

- [ ] **Step 2: main.swift 작성**

```swift
// Sources/Hangulji/main.swift
import Cocoa
import InputMethodKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
            ?? "com.mastergear.inputmethod.Hangulji_Connection"
        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        NSLog("Hangulji: IMKServer started (%@)", connectionName)
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
```

- [ ] **Step 3: 스텁 컨트롤러 작성** (`Sources/Hangulji/HanguljiInputController.swift`)

```swift
// Sources/Hangulji/HanguljiInputController.swift
import Cocoa
import InputMethodKit

/// @objc 이름을 고정해 Info.plist의 InputMethodServerControllerClass에서
/// 모듈 접두사 없이 찾을 수 있게 한다.
@objc(HanguljiInputController)
public class HanguljiInputController: IMKInputController {
    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        return false  // Task 8에서 구현
    }
}
```

- [ ] **Step 4: AppBundle/Info.plist 작성**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>CFBundleExecutable</key><string>Hangulji</string>
    <key>CFBundleIdentifier</key><string>com.mastergear.inputmethod.Hangulji</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Hangulji</string>
    <key>CFBundleDisplayName</key><string>한글지</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSBackgroundOnly</key><true/>
    <key>InputMethodConnectionName</key><string>com.mastergear.inputmethod.Hangulji_Connection</string>
    <key>InputMethodServerControllerClass</key><string>HanguljiInputController</string>
    <key>TISIntendedLanguage</key><string>ja</string>
    <key>tsInputMethodCharacterRepertoireKey</key>
    <array><string>Jpan</string></array>
    <key>tsInputMethodIconFileKey</key><string>main.tiff</string>
</dict>
</plist>
```

- [ ] **Step 5: 아이콘 생성 스크립트 작성 및 실행** (`scripts/make-icon.swift`)

```swift
// scripts/make-icon.swift — 1회성: 메뉴바용 16pt 'じ' 아이콘 생성
// 실행: swift scripts/make-icon.swift
import AppKit

let size = NSSize(width: 16, height: 16)
let image = NSImage(size: size)
image.lockFocus()
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .bold),
    .foregroundColor: NSColor.black,
]
let str = NSAttributedString(string: "じ", attributes: attrs)
let strSize = str.size()
str.draw(at: NSPoint(x: (16 - strSize.width) / 2, y: (16 - strSize.height) / 2))
image.unlockFocus()

let tiff = image.tiffRepresentation!
try! tiff.write(to: URL(fileURLWithPath: "AppBundle/main.tiff"))
print("wrote AppBundle/main.tiff (\(tiff.count) bytes)")
```

Run: `swift scripts/make-icon.swift`
Expected: `wrote AppBundle/main.tiff` 출력, 파일 생성 확인 (`ls -la AppBundle/`)

- [ ] **Step 6: build-app.sh 작성**

```bash
#!/bin/bash
# scripts/build-app.sh — swift build + .app 번들 조립 + ad-hoc 서명
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
find .build/release -maxdepth 1 -name '*.bundle' -print -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --deep --sign - "$APP"
echo "built: $APP"
```

- [ ] **Step 7: install-dev.sh 작성**

```bash
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
```

Run: `chmod +x scripts/build-app.sh scripts/install-dev.sh`

- [ ] **Step 8: 빌드 및 설치 확인**

Run: `./scripts/install-dev.sh`
Expected: `installed: ...` 출력. 확인:
- `codesign -dv "$HOME/Library/Input Methods/Hangulji.app" 2>&1 | head -3` → 서명 정보 출력
- `ls "$HOME/Library/Input Methods/Hangulji.app/Contents/Resources/"` → main.tiff + *.bundle 존재

- [ ] **Step 9: 수동 확인 (사용자 개입 필요 — 안내 메시지 출력)**

시스템 설정 → 키보드 → 입력 소스 → '+' → 일본어 → **Hangulji(한글지)** 추가. 목록에 없으면 로그아웃/로그인 1회 (스펙 §6 — 알려진 macOS 동작). 이 시점에서는 스텁이라 키 입력이 그대로 통과하는 게 정상.

- [ ] **Step 10: Commit**

```bash
git add Package.swift Sources/Hangulji/ AppBundle/ scripts/
git commit -m "feat: IMKit 앱 번들 스캐폴드 + 빌드/설치 스크립트

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: HanguljiInputController — 조합 플로우 (마크드 텍스트/커밋)

**Files:**
- Modify: `Sources/Hangulji/HanguljiInputController.swift` (스텁 → 본 구현)

**Interfaces:**
- Consumes: `HanguljiComposer` (Task 4 — `insert(_:) -> Bool`, `backspace() -> Bool`, `clear()`, `isEmpty`, `markedText`, `reading`)
- Produces: composing 상태의 전체 키 처리. Task 9가 이 파일에 selecting 상태를 추가한다.

키 동작은 스펙 §3 표의 composing 열 그대로. Space는 이 태스크에서는 "조합 커밋 후 공백 통과"(Task 9에서 변환으로 교체).

- [ ] **Step 1: 컨트롤러 본 구현**

```swift
// Sources/Hangulji/HanguljiInputController.swift
import Cocoa
import InputMethodKit
import HanguljiCore

@objc(HanguljiInputController)
public class HanguljiInputController: IMKInputController {
    private var composer = HanguljiComposer()

    // macOS 가상 키코드
    private enum Key {
        static let enter: UInt16 = 36
        static let space: UInt16 = 49
        static let backspace: UInt16 = 51
        static let escape: UInt16 = 53
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown,
              let client = sender as? IMKTextInput & NSObjectProtocol else { return false }

        // 수정키 조합(cmd/ctrl/opt)은 조합만 커밋하고 통과
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            commitComposition(to: client)
            return false
        }

        switch event.keyCode {
        case Key.backspace:
            guard !composer.isEmpty else { return false }
            composer.backspace()
            updateMarkedText(client)
            return true
        case Key.enter:
            guard !composer.isEmpty else { return false }
            commitComposition(to: client)
            return true
        case Key.escape:
            guard !composer.isEmpty else { return false }
            composer.clear()
            updateMarkedText(client)
            return true
        case Key.space:
            guard !composer.isEmpty else { return false }
            commitComposition(to: client)   // Task 9에서 변환 시작으로 교체
            return false
        default:
            break
        }

        guard let chars = event.characters, chars.count == 1, let ch = chars.first else {
            commitComposition(to: client)
            return false
        }

        if composer.insert(ch) {
            updateMarkedText(client)
            return true
        }

        // 일본어 구두점 (스펙 §3)
        if ch == "." || ch == "," {
            commitComposition(to: client)
            insert(ch == "." ? "。" : "、", to: client)
            return true
        }

        // 그 외(영숫자 등): 조합 커밋 후 시스템에 넘김
        commitComposition(to: client)
        return false
    }

    // MARK: - 조합 표시/커밋

    private func updateMarkedText(_ client: IMKTextInput) {
        let text = composer.markedText
        let attributed = NSAttributedString(
            string: text,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func insert(_ text: String, to client: IMKTextInput) {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func commitComposition(to client: IMKTextInput) {
        guard !composer.isEmpty else { return }
        insert(composer.markedText, to: client)
        composer.clear()
        updateMarkedText(client)  // 빈 문자열로 마크드 텍스트 해제
    }

    // 포커스 이동/클릭 시 조합 커밋
    public override func commitComposition(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commitComposition(to: client) }
    }

    public override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commitComposition(to: client) }
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete

- [ ] **Step 3: 설치 및 수동 테스트 (TextEdit)**

Run: `./scripts/install-dev.sh`

수동 확인 (TextEdit, Hangulji 입력 소스 선택):
1. `xhdnzydn` 타이핑 → 밑줄 **とうきょう** 표시
2. Enter → とうきょう 확정(밑줄 해제)
3. `rkd` + Backspace → 밑줄이 かん → か 로 줄어듦 (자모 단위 확인: がㅇ→か 가 아니라 간→가 재계산)
4. Esc → 조합 사라짐
5. `.` → 。 입력됨
6. 조합 중 마우스로 다른 곳 클릭 → 조합 커밋됨

문제 시 Console.app에서 `Hangulji` 프로세스 로그 확인 (Global Constraints: 디버거 부착 금지).

- [ ] **Step 4: Commit**

```bash
git add Sources/Hangulji/HanguljiInputController.swift
git commit -m "feat: 조합 플로우 — 실시간 가나 마크드 텍스트, 커밋/취소/백스페이스

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: 후보창 + 변환(selecting) 상태

**Files:**
- Create: `Sources/Hangulji/CandidatePanel.swift`
- Modify: `Sources/Hangulji/HanguljiInputController.swift` (selecting 상태 추가, Space 동작 교체)

**Interfaces:**
- Consumes: `KanjiConverter.candidateList(for:max:)` (Task 6), `HanguljiComposer.reading` (Task 4)
- Produces: 스펙 §3 표의 selecting 열 전체. MVP 완성 지점.

- [ ] **Step 1: CandidatePanel.swift 작성**

```swift
// Sources/Hangulji/CandidatePanel.swift
import Cocoa

/// 자체 후보창. IMKCandidates는 사용 금지 (스펙 §2.3).
final class CandidatePanel {
    private let panel: NSPanel
    private let stack = NSStackView()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 10),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])
        panel.contentView = background
    }

    /// candidates를 표시하고 selected 행을 강조. topLeft는 화면 좌표(캐럿 아래).
    func show(candidates: [String], selected: Int, topLeft: NSPoint) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, candidate) in candidates.enumerated() {
            let label = NSTextField(labelWithString: "\(i + 1)  \(candidate)")
            label.font = .systemFont(ofSize: 16)
            label.drawsBackground = true
            label.backgroundColor = (i == selected) ? .selectedContentBackgroundColor : .clear
            label.textColor = (i == selected) ? .white : .labelColor
            stack.addArrangedSubview(label)
        }
        panel.layoutIfNeeded()
        let size = stack.fittingSize
        panel.setContentSize(NSSize(width: max(size.width, 120), height: size.height))
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}
```

- [ ] **Step 2: 컨트롤러에 selecting 상태 추가**

`HanguljiInputController.swift`에 다음을 추가/교체:

```swift
import HanguljiConversion  // 파일 상단 import에 추가

    // 프로퍼티 추가
    private enum Mode {
        case composing
        case selecting(candidates: [String], index: Int)
    }
    private var mode: Mode = .composing
    private let panel = CandidatePanel()
    /// 사전 로드가 무거우므로 lazy — 최초 변환에 지연이 있을 수 있음 (알려진 트레이드오프)
    private static let converter = KanjiConverter()
```

`handle`의 switch 앞에 selecting 분기 추가 (수정키 처리 직후):

```swift
        if case .selecting(let candidates, let index) = mode {
            return handleSelecting(event, client: client, candidates: candidates, index: index)
        }
```

`case Key.space:` 분기를 변환 시작으로 교체:

```swift
        case Key.space:
            guard !composer.isEmpty else { return false }
            startConversion(client)
            return true
```

selecting 처리/변환 메서드 추가:

```swift
    // MARK: - 변환 (selecting)

    private func startConversion(_ client: IMKTextInput) {
        guard let reading = composer.reading else {
            // 매핑 불가 음절 포함 → 변환 불가, 그대로 커밋 (스펙 §3)
            commitComposition(to: client)
            return
        }
        let candidates = Self.converter.candidateList(for: reading, max: 9)
        guard !candidates.isEmpty else { return }
        mode = .selecting(candidates: candidates, index: 0)
        showSelection(client)
    }

    private func handleSelecting(_ event: NSEvent, client: IMKTextInput,
                                 candidates: [String], index: Int) -> Bool {
        switch event.keyCode {
        case Key.space, 125:  // Space/↓: 다음 후보
            mode = .selecting(candidates: candidates, index: (index + 1) % candidates.count)
            showSelection(client)
            return true
        case 126:             // ↑: 이전 후보
            mode = .selecting(candidates: candidates,
                              index: (index - 1 + candidates.count) % candidates.count)
            showSelection(client)
            return true
        case Key.enter:
            commitCandidate(candidates[index], client)
            return true
        case Key.escape, Key.backspace:  // 변환 취소 → composing 복귀 (스펙 §3)
            mode = .composing
            panel.hide()
            updateMarkedText(client)
            return true
        default:
            break
        }

        if let chars = event.characters, chars.count == 1, let ch = chars.first {
            // 숫자키로 후보 직접 선택
            if let n = ch.wholeNumberValue, (1...candidates.count).contains(n) {
                commitCandidate(candidates[n - 1], client)
                return true
            }
            // 새 타이핑: 현재 후보 확정 후 새 조합 시작
            if Keymap.jamo(for: ch) != nil || ch == "-" {
                commitCandidate(candidates[index], client)
                _ = composer.insert(ch)
                updateMarkedText(client)
                return true
            }
        }
        // 그 외 키: 현재 후보 확정 후 시스템에 넘김
        commitCandidate(candidates[index], client)
        return false
    }

    private func showSelection(_ client: IMKTextInput) {
        guard case .selecting(let candidates, let index) = mode else { return }
        // 마크드 텍스트에 현재 후보 표시
        let attributed = NSAttributedString(
            string: candidates[index],
            attributes: [.underlineStyle: NSUnderlineStyle.thick.rawValue]
        )
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: candidates[index].utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        // 캐럿 위치 아래에 후보창
        var lineRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        panel.show(candidates: candidates, selected: index,
                   topLeft: NSPoint(x: lineRect.origin.x, y: lineRect.origin.y - 4))
    }

    private func commitCandidate(_ text: String, _ client: IMKTextInput) {
        insert(text, to: client)
        composer.clear()
        mode = .composing
        panel.hide()
        updateMarkedText(client)
    }
```

`commitComposition(to:)`와 `deactivateServer`에 패널 정리 추가:

```swift
    private func commitComposition(to client: IMKTextInput) {
        if case .selecting(let candidates, let index) = mode {
            commitCandidate(candidates[index], client)
            return
        }
        guard !composer.isEmpty else { return }
        insert(composer.markedText, to: client)
        composer.clear()
        updateMarkedText(client)
    }

    public override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commitComposition(to: client) }
        panel.hide()
    }
```

- [ ] **Step 3: 빌드 확인**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete. (KanjiConverter가 Task 6에서 `@MainActor`가 됐다면 컨트롤러 쪽 호출은 메인 스레드이므로 `MainActor.assumeIsolated { }`로 감싼다.)

- [ ] **Step 4: 설치 및 MVP 수동 테스트**

Run: `./scripts/install-dev.sh`

수동 확인 (TextEdit):
1. `xhdnzydn` → とうきょう 밑줄 표시
2. Space → 후보창 표시, 첫 후보 **東京** 이 마크드 텍스트에 표시
3. Space 반복 → 후보 순환 (とうきょう, トウキョウ 포함 확인)
4. Enter → 東京 확정
5. **MVP 시나리오**: `xhdnzydnsldlzlaktm` (토우쿄우니이키마스) → Space → **東京に行きます** 후보 확인 → Enter
6. Esc (selecting에서) → 가나 조합으로 복귀
7. 숫자 2 → 두 번째 후보 확정
8. 최초 변환이 사전 로드 때문에 1–2초 지연될 수 있음 — 두 번째부터 즉시인지 확인

- [ ] **Step 5: Commit**

```bash
git add Sources/Hangulji/
git commit -m "feat: 자체 후보창 + 한자 변환 — MVP 완성

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: README + 호환성 매트릭스 검증 + 마무리

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: 완성된 전체 시스템

- [ ] **Step 1: README.md 작성**

```markdown
# Hangulji (한글지)

macOS용 일본어 입력기 — 한글로 일본어 발음(가나 철자)을 치면 가나로 변환되고,
스페이스로 한자 변환까지. 로마지 입력의 한글 버전.

`토우쿄우니이키마스` → とうきょうにいきます → [Space] → **東京に行きます**

## 설치 (개인용)

```bash
./scripts/install-dev.sh
```

시스템 설정 → 키보드 → 입력 소스 → '+' → 일본어 → **한글지** 추가.
목록에 안 보이면 로그아웃/로그인 후 다시 확인.

## 입력 규칙 요약

- 가나 철자에 충실: 카=か 가=が (위치 무관), 장음은 그대로 (토우쿄우=とうきょう)
- 받침 ㅅ=っ (삿포로), 받침 ㄴ=ん (칸=かん) — 칸이=かんい / 카니=かに 자동 구분
- 관용 별칭: 홋까이도/혹카이도, 쓰·쯔=つ, 망가=まんが, 곤니찌와의 찌=ち
- を=워, は=하, へ=헤 (조사도 철자대로)
- ぢ=띠, づ=뜨 / ティ=티 ディ=디 トゥ=투 ファ=화 등
- `-`=ー, `.`=。 `,`=、
- 가타카나는 변환 후보에서 선택

전체 규칙: docs/superpowers/specs/2026-07-31-hangulji-ime-design.md §4

## 키

| 키 | 조합 중 | 후보 선택 중 |
|---|---|---|
| Space | 변환 시작 | 다음 후보 |
| Enter | 가나 그대로 확정 | 후보 확정 |
| Esc | 조합 취소 | 변환 취소 |
| 1–9 | — | 후보 직접 선택 |

## 개발

```bash
swift test          # 매핑/조합 로직 전체 테스트
./scripts/install-dev.sh   # 빌드+설치+프로세스 재시작
```

주의: IME 프로세스에 디버거를 붙이지 말 것 (키보드 전체가 얼어붙음).
로그는 NSLog → Console.app.
```

- [ ] **Step 2: 전체 테스트 최종 확인**

Run: `swift test 2>&1 | tail -5`
Expected: PASS (전체)

- [ ] **Step 3: 호환성 매트릭스 수동 검증 (스펙 §7)**

각 앱에서 `xhdnzydn` → Space → 東京 확정이 되는지:
- [ ] TextEdit
- [ ] Safari (주소창 아닌 웹 텍스트필드)
- [ ] Terminal (마크드 텍스트 표시가 어색할 수 있음 — 확정 결과만 정상이면 통과)
- [ ] VS Code (Electron)
- [ ] Spotlight
- [ ] 비밀번호 필드에서 IME가 우회되는지 (통과가 정상 동작)

문제 발견 시: 앱 이름과 증상을 README의 "알려진 문제" 섹션으로 기록 (수정은 별도 태스크로).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README — 설치법·입력 규칙·키 요약

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review 결과 (작성 후 점검)

1. **스펙 커버리지**: §2 아키텍처→Task 1–7, §3 상태머신→Task 8–9, §4 매핑 전체→Task 3(표)+4(파사드·골든), §5 셸 방침→Task 7–8, §6 개발루프→Task 7, §7 테스트→각 태스크+Task 10, §8 MVP 정의→Task 9 Step 4. 비목표(배포·가타카나 토글·설정 UI)는 의도적으로 미포함.
2. **플레이스홀더**: 없음. 단 Task 6의 `ConvertRequestOptions` 시그니처는 pre-1.0 API라 버전 차이가 있을 수 있어 "컴파일 에러 시 패키지 소스 확인" 지침을 명시 (구체적 파일 경로 포함) — 의도된 유일한 가변 지점.
3. **타입 일관성**: `HanguljiComposer.insert(_:) -> Bool`/`markedText`/`reading`(T4↔T8–9), `KanjiConverter.candidateList(for:max:)`(T6↔T9), `MappedSyllable.display/isMapped`(T3↔T4), `Syllable.hangul`(T2↔T3) 확인 완료. Task 9의 `Keymap.jamo(for:)` 사용은 Task 1 공개 API ✓.
```
