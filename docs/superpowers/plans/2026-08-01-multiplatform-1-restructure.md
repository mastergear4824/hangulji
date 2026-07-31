# 멀티플랫폼 서브프로젝트 1: 재구성 + spec 추출 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 저장소를 멀티플랫폼 구조(core-swift/, macos/, spec/)로 재구성하고, 매핑 테이블과 골든 테스트를 언어 중립 단일 진실 원천(spec/)으로 추출하며, conformance CI를 세운다. macOS 입력기 동작은 불변.

**Architecture:** `git mv`로 히스토리 보존 이동 → core-swift(공용 SPM 패키지)와 macos(IMKit 셸 패키지, path 의존) 분리 → KanaMapper의 테이블 리터럴을 spec/mapping.tsv에서 생성한 파일로 대체(바이트 동일 동작) → 골든을 JSON 픽스처로 내보내고 픽스처 러너 테스트 추가 → CI에서 테스트+생성물 최신성 검증.

**Tech Stack:** Swift/SwiftPM, GitHub Actions (macOS 러너)

**Spec:** `docs/superpowers/specs/2026-07-31-hangulji-multiplatform-design.md` §3–§7, 서브프로젝트 1

## Global Constraints

- 매핑 **동작 불변**: 재구성·생성 테이블 전환 후에도 기존 53개 테스트가 수정 없이 전부 통과해야 한다 (테스트 파일의 경로/타깃 조정만 허용, 기대값 변경 금지)
- `git mv`로 이동해 파일 히스토리 보존
- core-swift: 외부 의존성은 AzooKeyKanaKanjiConverter 하나(.upToNextMinor "0.11.0"), HanguljiCore 타깃은 import 없음 유지, 전 타깃 언어 모드 `.v5`
- 생성 파일(`*.generated.swift`)은 수기 수정 금지 — 헤더 주석에 명시. 생성기 재실행 시 `git diff` 무변화(멱등·결정적 출력: 정렬 고정)
- spec/fixtures JSON: `{"name","keys","kana","fullyMapped"}` (kana.json) / `{"name","keys","syllables"}` (composition.json). keys는 2벌식 라틴 문자
- 커밋 메시지에 Co-Authored-By 트레일러 **넣지 않는다** (사용자 지시)
- 각 태스크 완료 전 `cd core-swift && swift test` + (셸 변경 시) `cd macos && swift build -c release` 통과 확인

## File Structure (재구성 후)

```
spec/
├── mapping.tsv                  # kind(body|final) \t initial \t vowel \t kana
├── SPEC.md                      # automaton·키맵·매핑 명세 (포팅 지침)
├── fixtures/{kana.json, composition.json}
└── generators/gen-swift.swift   # TSV → KanaTable.generated.swift
core-swift/
├── Package.swift                # HanguljiCore, HanguljiConversion, fixture-export + 테스트 2개
├── Sources/HanguljiCore/        # 기존 5파일 + KanaTable.generated.swift
├── Sources/HanguljiConversion/
├── Sources/fixture-export/main.swift   # 골든 → JSON 픽스처 내보내기 (자기검증 포함)
└── Tests/                       # 기존 6파일 + FixtureTests.swift
macos/
├── Package.swift                # executable Hangulji, ../core-swift path 의존
├── Sources/Hangulji/            # 기존 3파일
├── AppBundle/  ├── scripts/     # 경로만 수정
.github/workflows/core.yml
```

---

### Task 1: 저장소 재구성 (git mv + 패키지 분리 + 스크립트 경로)

**Files:**
- Move: `Sources/HanguljiCore→core-swift/Sources/HanguljiCore`, `Sources/HanguljiConversion→core-swift/Sources/HanguljiConversion`, `Tests/*→core-swift/Tests/*`, `Sources/Hangulji→macos/Sources/Hangulji`, `AppBundle→macos/AppBundle`, `scripts→macos/scripts`
- Create: `core-swift/Package.swift`, `macos/Package.swift`
- Delete: 루트 `Package.swift`, 루트 `Package.resolved`
- Modify: `macos/scripts/build-app.sh`(경로 주석만 — cd 로직은 그대로 macos/를 가리키게 됨)

**Interfaces:**
- Produces: `core-swift` 패키지가 `HanguljiCore`·`HanguljiConversion` 라이브러리 프로덕트 노출. `macos` 패키지가 path 의존으로 소비. 이후 태스크는 `cd core-swift && swift test`로 테스트.

- [ ] **Step 1: git mv로 이동**

```bash
mkdir -p core-swift/Sources core-swift/Tests macos/Sources
git mv Sources/HanguljiCore core-swift/Sources/HanguljiCore
git mv Sources/HanguljiConversion core-swift/Sources/HanguljiConversion
git mv Tests/HanguljiCoreTests core-swift/Tests/HanguljiCoreTests
git mv Tests/HanguljiConversionTests core-swift/Tests/HanguljiConversionTests
git mv Sources/Hangulji macos/Sources/Hangulji
git mv AppBundle macos/AppBundle
git mv scripts macos/scripts
git rm Package.swift Package.resolved
rmdir Sources Tests 2>/dev/null || true
```

- [ ] **Step 2: core-swift/Package.swift 작성**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji-core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HanguljiCore", targets: ["HanguljiCore"]),
        .library(name: "HanguljiConversion", targets: ["HanguljiConversion"]),
    ],
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
        .executableTarget(
            name: "fixture-export",
            dependencies: ["HanguljiCore"],
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

주: `fixture-export` 타깃 디렉터리는 Task 3에서 만들지만 Package.swift에 미리 선언하면 빌드가 깨지므로, **이 태스크에서는 fixture-export 항목을 뺀 채로 작성**하고 Task 3에서 추가한다.

- [ ] **Step 3: macos/Package.swift 작성**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji-macos",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "hangulji-core", path: "../core-swift"),
    ],
    targets: [
        .executableTarget(
            name: "Hangulji",
            dependencies: [
                .product(name: "HanguljiCore", package: "hangulji-core"),
                .product(name: "HanguljiConversion", package: "hangulji-core"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 4: 검증 — 테스트·릴리스 빌드·설치**

```bash
cd core-swift && swift test 2>&1 | grep "Test Suite 'All tests'" ; cd ..
cd macos && swift build -c release 2>&1 | tail -2 ; cd ..
./macos/scripts/install-dev.sh
```

Expected: 53개 테스트 통과, Build complete, 설치 성공. `ls "$HOME/Library/Input Methods/Hangulji.app/Contents/Resources/"`에 *.bundle 존재(사전 복사 확인 — build-app.sh의 `cd "$(dirname "$0")/.."`는 이제 macos/를 가리키고 .build도 macos/.build이므로 로직 변화 없음. 문제가 생기면 스크립트의 상대 경로를 macos/ 기준으로 수정).

- [ ] **Step 5: Commit** (`git add -A` 후 이동+생성 일괄, 트레일러 없이)

```bash
git add -A && git commit -m "refactor: 멀티플랫폼 구조로 재구성 (core-swift/, macos/ 분리)"
```

---

### Task 2: spec/mapping.tsv 추출 + gen-swift 생성기 + 생성 테이블 전환

**Files:**
- Create: `spec/mapping.tsv`(덤프 스텝으로 생성), `spec/generators/gen-swift.swift`, `core-swift/Sources/HanguljiCore/KanaTable.generated.swift`(생성기 산출)
- Modify: `core-swift/Sources/HanguljiCore/KanaMapper.swift` (rows 리터럴 제거 → KanaTable 참조)

**Interfaces:**
- Produces: `enum KanaTable { static let body: [(initial: Consonant, vowel: Vowel, kana: String)]; static let finals: [(consonant: Consonant, kana: String)] }` — KanaMapper와 이후 플랫폼 생성기의 유일한 데이터 원천은 mapping.tsv.

- [ ] **Step 1: 임시 덤프 테스트로 TSV 생성 (전사 오류 원천 차단)**

`core-swift/Tests/HanguljiCoreTests/DumpTSV.swift` (임시 파일):

```swift
import XCTest
@testable import HanguljiCore

final class DumpTSV: XCTestCase {
    func testDumpMappingTSV() throws {
        var lines = ["# kind\tinitial\tvowel\tkana"]
        for initial in Consonant.allCases {
            for vowel in Vowel.allCases {
                if let kana = KanaMapper.bodyKana(initial: initial, vowel: vowel) {
                    lines.append("body\t\(initial.rawValue)\t\(vowel.rawValue)\t\(kana)")
                }
            }
        }
        for consonant in Consonant.allCases {
            if let kana = KanaMapper.finalKanaForDump(consonant) {
                lines.append("final\t\(consonant.rawValue)\t\t\(kana)")
            }
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("spec/mapping.tsv")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
```

KanaMapper에 덤프용 내부 접근자 2개를 임시 추가 (Step 4에서 정식 API로 정리):

```swift
    static func bodyKana(initial: Consonant, vowel: Vowel) -> String? {
        bodyTable[BodyKey(initial: initial, vowel: vowel)]
    }
    static func finalKanaForDump(_ c: Consonant) -> String? { finalTable[c] }
```

Run: `cd core-swift && swift test --filter DumpTSV` → `spec/mapping.tsv` 생성 확인 (`wc -l ../spec/mapping.tsv` — body ~169 + final 7 + 헤더). **allCases 순회라 출력이 결정적(정렬 고정)이다.**

- [ ] **Step 2: DumpTSV.swift 삭제** (`git rm` 아님 — 아직 미커밋이므로 파일 삭제만). 임시 접근자 중 `finalKanaForDump`도 삭제.

- [ ] **Step 3: gen-swift 생성기 작성** (`spec/generators/gen-swift.swift`)

```swift
#!/usr/bin/env swift
// spec/mapping.tsv → core-swift/Sources/HanguljiCore/KanaTable.generated.swift
// 사용: swift spec/generators/gen-swift.swift (저장소 루트에서)
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let tsvURL = root.appendingPathComponent("spec/mapping.tsv")
let outURL = root.appendingPathComponent("core-swift/Sources/HanguljiCore/KanaTable.generated.swift")

guard let tsv = try? String(contentsOf: tsvURL, encoding: .utf8) else {
    fatalError("spec/mapping.tsv 를 읽을 수 없음 — 저장소 루트에서 실행했는가?")
}

// 자모 문자 → enum 케이스 이름 (Consonant/Vowel 선언과 반드시 일치)
let consonantNames: [String: String] = [
    "ㄱ": "g", "ㄲ": "gg", "ㄴ": "n", "ㄷ": "d", "ㄸ": "dd", "ㄹ": "r", "ㅁ": "m",
    "ㅂ": "b", "ㅃ": "bb", "ㅅ": "s", "ㅆ": "ss", "ㅇ": "ng", "ㅈ": "j", "ㅉ": "jj",
    "ㅊ": "ch", "ㅋ": "k", "ㅌ": "t", "ㅍ": "p", "ㅎ": "h",
]
let vowelNames: [String: String] = [
    "ㅏ": "a", "ㅐ": "ae", "ㅑ": "ya", "ㅒ": "yae", "ㅓ": "eo", "ㅔ": "e",
    "ㅕ": "yeo", "ㅖ": "ye", "ㅗ": "o", "ㅘ": "wa", "ㅙ": "wae", "ㅚ": "oe",
    "ㅛ": "yo", "ㅜ": "u", "ㅝ": "wo", "ㅞ": "we", "ㅟ": "wi", "ㅠ": "yu",
    "ㅡ": "eu", "ㅢ": "ui", "ㅣ": "i",
]

var bodyLines: [String] = []
var finalLines: [String] = []
for rawLine in tsv.split(separator: "\n") {
    let line = String(rawLine)
    if line.hasPrefix("#") || line.isEmpty { continue }
    let cols = line.components(separatedBy: "\t")
    guard cols.count == 4 else { fatalError("잘못된 TSV 행: \(line)") }
    switch cols[0] {
    case "body":
        guard let ci = consonantNames[cols[1]], let vi = vowelNames[cols[2]] else {
            fatalError("알 수 없는 자모: \(line)")
        }
        bodyLines.append("        (.\(ci), .\(vi), \"\(cols[3])\"),")
    case "final":
        guard let ci = consonantNames[cols[1]] else { fatalError("알 수 없는 자모: \(line)") }
        finalLines.append("        (.\(ci), \"\(cols[3])\"),")
    default:
        fatalError("알 수 없는 kind: \(line)")
    }
}

let output = """
// KanaTable.generated.swift
// spec/mapping.tsv 에서 생성됨 — 수기 수정 금지.
// 재생성: swift spec/generators/gen-swift.swift (저장소 루트에서)

enum KanaTable {
    static let body: [(initial: Consonant, vowel: Vowel, kana: String)] = [
\(bodyLines.joined(separator: "\n"))
    ]

    static let finals: [(consonant: Consonant, kana: String)] = [
\(finalLines.joined(separator: "\n"))
    ]
}

"""
try! output.write(to: outURL, atomically: true, encoding: .utf8)
print("wrote \(outURL.path): body \(bodyLines.count), finals \(finalLines.count)")
```

Run: `swift spec/generators/gen-swift.swift` → KanaTable.generated.swift 생성 확인.

- [ ] **Step 4: KanaMapper를 KanaTable 참조로 전환**

`KanaMapper.swift`에서 `rows` 리터럴 배열과 `bodyTable`/`finalTable` 구축부를 다음으로 교체 (MappedSyllable, BodyKey, map()은 그대로):

```swift
    private static let bodyTable: [BodyKey: String] = {
        var table: [BodyKey: String] = [:]
        for entry in KanaTable.body {
            table[BodyKey(initial: entry.initial, vowel: entry.vowel)] = entry.kana
        }
        return table
    }()

    private static let finalTable: [Consonant: String] = {
        var table: [Consonant: String] = [:]
        for entry in KanaTable.finals { table[entry.consonant] = entry.kana }
        return table
    }()

    /// spec 픽스처·생성기 검증용 공개 조회 (동작은 map()과 동일 데이터)
    static func bodyKana(initial: Consonant, vowel: Vowel) -> String? {
        bodyTable[BodyKey(initial: initial, vowel: vowel)]
    }
```

- [ ] **Step 5: 검증 — 동작 불변 + 멱등성**

```bash
cd core-swift && swift test 2>&1 | grep "Test Suite 'All tests'" ; cd ..
swift spec/generators/gen-swift.swift && git diff --stat -- core-swift/Sources/HanguljiCore/KanaTable.generated.swift
```

Expected: 53개 전부 통과(기대값 무변경), 재생성 후 diff 없음.

- [ ] **Step 6: Commit** — `git add spec core-swift && git commit -m "feat: 매핑 단일 진실 원천 spec/mapping.tsv + Swift 테이블 생성기"`

---

### Task 3: 골든 픽스처 내보내기 + 픽스처 러너 테스트

**Files:**
- Modify: `core-swift/Package.swift` (fixture-export 타깃 추가 — Task 1 Step 2의 선언 블록 사용)
- Create: `core-swift/Sources/fixture-export/main.swift`, `spec/fixtures/kana.json`, `spec/fixtures/composition.json`(산출물), `core-swift/Tests/HanguljiCoreTests/FixtureTests.swift`

**Interfaces:**
- Consumes: `HanguljiComposer`, `JamoComposer`, `Keymap`, `Syllable.hangul`
- Produces: `spec/fixtures/*.json` — 이후 Kotlin/Windows 포트가 소비하는 conformance 계약. `swift run fixture-export`(core-swift에서)로 재생성.

- [ ] **Step 1: fixture-export 작성** (`core-swift/Sources/fixture-export/main.swift`)

케이스 목록은 기존 테스트의 기대값을 **사람이 정한 진실**로 복사하고, 도구는 (a) 한글→키 역변환, (b) 레퍼런스 구현 출력이 기대값과 일치하는지 **자기검증** 후, (c) JSON을 결정적 순서로 기록한다.

```swift
// core-swift/Sources/fixture-export/main.swift
// 골든 케이스 → spec/fixtures/*.json 내보내기.
// 사용: cd core-swift && swift run fixture-export
// 기대값과 레퍼런스 구현이 다르면 fatalError — 픽스처는 항상 검증된 상태로만 기록된다.
import Foundation
import HanguljiCore

// 2벌식 역키맵 (Keymap과의 일치를 아래에서 라운드트립 검증)
let reverseKeys: [Character: Character] = [
    "ㅂ": "q", "ㅈ": "w", "ㄷ": "e", "ㄱ": "r", "ㅅ": "t", "ㅛ": "y", "ㅕ": "u",
    "ㅑ": "i", "ㅐ": "o", "ㅔ": "p", "ㅁ": "a", "ㄴ": "s", "ㅇ": "d", "ㄹ": "f",
    "ㅎ": "g", "ㅗ": "h", "ㅓ": "j", "ㅏ": "k", "ㅣ": "l", "ㅋ": "z", "ㅌ": "x",
    "ㅊ": "c", "ㅍ": "v", "ㅠ": "b", "ㅜ": "n", "ㅡ": "m",
    "ㅃ": "Q", "ㅉ": "W", "ㄸ": "E", "ㄲ": "R", "ㅆ": "T", "ㅒ": "O", "ㅖ": "P",
]
for (jamoChar, key) in reverseKeys {
    let expected: Jamo? = Consonant(rawValue: jamoChar).map(Jamo.consonant)
        ?? Vowel(rawValue: jamoChar).map(Jamo.vowel)
    guard Keymap.jamo(for: key) == expected else {
        fatalError("역키맵 불일치: \(jamoChar) ↔ \(key)")
    }
}

// 복합모음·받침 포함 한글 문자열 → 2벌식 키 시퀀스
func keys(for hangul: String) -> String {
    var result = ""
    for scalar in hangul.unicodeScalars {
        if scalar == "-" { result.append("-"); continue }
        let code = Int(scalar.value) - 0xAC00
        precondition(code >= 0 && code < 11172, "완성형 한글만: \(scalar)")
        let ci = code / (21 * 28), vi = (code % (21 * 28)) / 28, fi = code % 28
        let initial = Consonant.allCases[ci]
        result.append(reverseKeys[initial.rawValue]!)
        // 복합모음은 구성 모음 2타로 분해
        let vowelStrokes: [Vowel: [Character]] = [
            .wa: ["ㅗ", "ㅏ"], .wae: ["ㅗ", "ㅐ"], .oe: ["ㅗ", "ㅣ"],
            .wo: ["ㅜ", "ㅓ"], .we: ["ㅜ", "ㅔ"], .wi: ["ㅜ", "ㅣ"], .ui: ["ㅡ", "ㅣ"],
        ]
        let vowel = Vowel.allCases[vi]
        for stroke in vowelStrokes[vowel] ?? [vowel.rawValue] {
            result.append(reverseKeys[stroke]!)
        }
        if fi != 0 {
            let finals: [Int: Character] = [1: "ㄱ", 2: "ㄲ", 4: "ㄴ", 7: "ㄷ", 8: "ㄹ",
                                            16: "ㅁ", 17: "ㅂ", 19: "ㅅ", 20: "ㅆ", 21: "ㅇ",
                                            22: "ㅈ", 23: "ㅊ", 24: "ㅋ", 25: "ㅌ", 26: "ㅍ", 27: "ㅎ"]
            result.append(reverseKeys[finals[fi]!]!)
        }
    }
    return result
}

struct KanaCase { let name: String, hangul: String, kana: String, fullyMapped: Bool }

// ── 사람이 정한 진실 (기존 테스트의 기대값과 동일해야 한다) ──
let kanaCases: [KanaCase] = [
    // 문장 골든 (HanguljiComposerTests)
    .init(name: "tokyo-trip", hangul: "토우쿄우니이키마스", kana: "とうきょうにいきます", fullyMapped: true),
    .init(name: "arigatou", hangul: "아리가토우고자이마스", kana: "ありがとうございます", fullyMapped: true),
    .init(name: "konnichiwa", hangul: "콘니치하", kana: "こんにちは", fullyMapped: true),
    .init(name: "gakkou", hangul: "갓꼬우", kana: "がっこう", fullyMapped: true),
    .init(name: "sasshiburi", hangul: "삿시부리", kana: "さっしぶり", fullyMapped: true),
    .init(name: "oneesan", hangul: "오네에상", kana: "おねえさん", fullyMapped: true),
    .init(name: "oosaka", hangul: "오오사카", kana: "おおさか", fullyMapped: true),
    .init(name: "eiga", hangul: "에이가", kana: "えいが", fullyMapped: true),
    .init(name: "wo-particle", hangul: "가워이마스", kana: "がをいます", fullyMapped: true),
    // 받침·별칭 (KanaMapperTests의 문자열 케이스)
    .init(name: "final-n-voiceless", hangul: "칸", kana: "かん", fullyMapped: true),
    .init(name: "final-n-voiced", hangul: "간", kana: "がん", fullyMapped: true),
    .init(name: "sapporo", hangul: "삿포로", kana: "さっぽろ", fullyMapped: true),
    .init(name: "hokkaido-alias", hangul: "혹카이도", kana: "ほっかいど", fullyMapped: true),
    .init(name: "ippai-alias", hangul: "잇파이", kana: "いっぱい", fullyMapped: true),
    .init(name: "manga-alias", hangul: "망가", kana: "まんが", fullyMapped: true),
    .init(name: "donburi-alias", hangul: "돔부리", kana: "どんぶり", fullyMapped: true),
    .init(name: "hokkaidou-tense", hangul: "홋까이도우", kana: "ほっかいどう", fullyMapped: true),
    // 행 커버리지 (기본표 전 행)
    .init(name: "row-vowel", hangul: "아이우에오야유요와워", kana: "あいうえおやゆよわを", fullyMapped: true),
    .init(name: "row-k", hangul: "카키쿠케코캬큐쿄", kana: "かきくけこきゃきゅきょ", fullyMapped: true),
    .init(name: "row-g", hangul: "가기구게고갸규교", kana: "がぎぐげごぎゃぎゅぎょ", fullyMapped: true),
    .init(name: "row-s", hangul: "사시스세소샤슈쇼", kana: "さしすせそしゃしゅしょ", fullyMapped: true),
    .init(name: "row-z", hangul: "자지즈제조쟈쥬죠", kana: "ざじずぜぞじゃじゅじょ", fullyMapped: true),
    .init(name: "row-t", hangul: "타치츠테토챠츄쵸", kana: "たちつてとちゃちゅちょ", fullyMapped: true),
    .init(name: "row-d", hangul: "다데도띠뜨", kana: "だでどぢづ", fullyMapped: true),
    .init(name: "row-n", hangul: "나니누네노냐뉴뇨", kana: "なにぬねのにゃにゅにょ", fullyMapped: true),
    .init(name: "row-h", hangul: "하히후헤호햐휴효", kana: "はひふへほひゃひゅひょ", fullyMapped: true),
    .init(name: "row-b", hangul: "바비부베보뱌뷰뵤", kana: "ばびぶべぼびゃびゅびょ", fullyMapped: true),
    .init(name: "row-p", hangul: "파피푸페포퍄퓨표", kana: "ぱぴぷぺぽぴゃぴゅぴょ", fullyMapped: true),
    .init(name: "row-m", hangul: "마미무메모먀뮤묘", kana: "まみむめもみゃみゅみょ", fullyMapped: true),
    .init(name: "row-r", hangul: "라리루레로랴류료", kana: "らりるれろりゃりゅりょ", fullyMapped: true),
    // 별칭·확장
    .init(name: "tsu-variants", hangul: "츠쓰쯔", kana: "つつつ", fullyMapped: true),
    .init(name: "jj-row", hangul: "짜찌쮸쬬", kana: "ちゃちちゅちょ", fullyMapped: true),
    .init(name: "ch-aliases", hangul: "차추초", kana: "ちゃちゅちょ", fullyMapped: true),
    .init(name: "u-eu-equiv", hangul: "수주흐크", kana: "すずふく", fullyMapped: true),
    .init(name: "tense-aliases", hangul: "까따빠싸", kana: "かたぱさ", fullyMapped: true),
    .init(name: "extended", hangul: "티디투두화휘훼훠위웨", kana: "てぃでぃとぅどぅふぁふぃふぇふぉうぃうぇ", fullyMapped: true),
    .init(name: "za-vs-ja", hangul: "자쟈", kana: "ざじゃ", fullyMapped: true),
    .init(name: "prolonged", hangul: "라-멘", kana: "らーめん", fullyMapped: true),
    // 매핑 불가
    .init(name: "unmappable", hangul: "별", kana: "별", fullyMapped: false),
]

struct CompositionCase { let name: String, keys: String, syllables: [String] }
let compositionCases: [CompositionCase] = [
    .init(name: "reanalysis-kani", keys: "rksl", syllables: ["가", "니"]),
    .init(name: "explicit-ng-kan-i", keys: "rksdl", syllables: ["간", "이"]),
    .init(name: "compound-wo", keys: "dnj", syllables: ["워"]),
    .init(name: "compound-hwa", keys: "ghk", syllables: ["화"]),
    .init(name: "double-vowel-split", keys: "zkk", syllables: ["카", "ㅏ"]),
    .init(name: "final-then-consonant", keys: "tktvh", syllables: ["삿", "포"]),
    .init(name: "dd-cannot-be-final", keys: "zkEk", syllables: ["카", "따"]),
    .init(name: "lone-consonant", keys: "z", syllables: ["ㅋ"]),
]

// ── 자기검증 + JSON 기록 ──
func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

var kanaJSON = ["["]
for (i, c) in kanaCases.enumerated() {
    let keySeq = keys(for: c.hangul)
    var composer = HanguljiComposer()
    for ch in keySeq { _ = composer.insert(ch) }
    guard composer.markedText == c.kana else {
        fatalError("검증 실패 \(c.name): 기대 \(c.kana), 실제 \(composer.markedText) (keys \(keySeq))")
    }
    guard (composer.reading != nil) == c.fullyMapped else {
        fatalError("검증 실패 \(c.name): fullyMapped 불일치")
    }
    let comma = i == kanaCases.count - 1 ? "" : ","
    kanaJSON.append("  {\"name\": \"\(esc(c.name))\", \"keys\": \"\(esc(keySeq))\", \"kana\": \"\(esc(c.kana))\", \"fullyMapped\": \(c.fullyMapped)}\(comma)")
}
kanaJSON.append("]")

var compJSON = ["["]
for (i, c) in compositionCases.enumerated() {
    var jamoComposer = JamoComposer()
    for ch in c.keys {
        guard case .some(let jamo) = Keymap.jamo(for: ch) else { fatalError("자모 아님: \(ch)") }
        jamoComposer.append(jamo)
    }
    let actual = jamoComposer.syllables.map(\.hangul)
    guard actual == c.syllables else {
        fatalError("검증 실패 \(c.name): 기대 \(c.syllables), 실제 \(actual)")
    }
    let syllableList = c.syllables.map { "\"\(esc($0))\"" }.joined(separator: ", ")
    let comma = i == compositionCases.count - 1 ? "" : ","
    compJSON.append("  {\"name\": \"\(esc(c.name))\", \"keys\": \"\(esc(c.keys))\", \"syllables\": [\(syllableList)]}\(comma)")
}
compJSON.append("]")

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
let fixturesDir = root.appendingPathComponent("spec/fixtures")
try! FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
try! (kanaJSON.joined(separator: "\n") + "\n")
    .write(to: fixturesDir.appendingPathComponent("kana.json"), atomically: true, encoding: .utf8)
try! (compJSON.joined(separator: "\n") + "\n")
    .write(to: fixturesDir.appendingPathComponent("composition.json"), atomically: true, encoding: .utf8)
print("wrote fixtures: kana \(kanaCases.count), composition \(compositionCases.count)")
```

주의: `row-t`의 챠츄쵸는 ㅊ행이지만 케이스 이름은 기존 테스트(testTRow)를 따른다. `tsu-variants`의 "츠쓰쯔"→"つつつ"는 세 별칭이 모두 つ로 정규화됨을 하나의 케이스로 압축한 것.

- [ ] **Step 2: 실행 및 산출 확인**

```bash
cd core-swift && swift run fixture-export
python3 -c "import json;print(len(json.load(open('../spec/fixtures/kana.json'))), len(json.load(open('../spec/fixtures/composition.json'))))"
```

Expected: 자기검증 통과(전 케이스), kana 39(fullyMapped 38 + unmappable 1) / composition 8. **검증 실패 시 기대값(kana)이 진실** — hangul 표기나 keys 변환을 의심하고, 그래도 불일치하면 BLOCKED 보고 (KanaMapper 수정 금지).

- [ ] **Step 3: FixtureTests.swift 작성** (`core-swift/Tests/HanguljiCoreTests/FixtureTests.swift`)

```swift
import XCTest
@testable import HanguljiCore

/// spec/fixtures/*.json conformance 러너 — 모든 플랫폼 포트가 같은 픽스처를 통과해야 한다.
final class FixtureTests: XCTestCase {
    private var fixturesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("spec/fixtures")
    }

    func testKanaFixtures() throws {
        struct Case: Decodable { let name: String; let keys: String; let kana: String; let fullyMapped: Bool }
        let data = try Data(contentsOf: fixturesURL.appendingPathComponent("kana.json"))
        let cases = try JSONDecoder().decode([Case].self, from: data)
        XCTAssertGreaterThanOrEqual(cases.count, 38)
        for c in cases {
            var composer = HanguljiComposer()
            for ch in c.keys { _ = composer.insert(ch) }
            XCTAssertEqual(composer.markedText, c.kana, c.name)
            XCTAssertEqual(composer.reading != nil, c.fullyMapped, c.name)
        }
    }

    func testCompositionFixtures() throws {
        struct Case: Decodable { let name: String; let keys: String; let syllables: [String] }
        let data = try Data(contentsOf: fixturesURL.appendingPathComponent("composition.json"))
        let cases = try JSONDecoder().decode([Case].self, from: data)
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for c in cases {
            var composer = JamoComposer()
            for ch in c.keys {
                guard let jamo = Keymap.jamo(for: ch) else { return XCTFail("자모 아님 \(c.name): \(ch)") }
                composer.append(jamo)
            }
            XCTAssertEqual(composer.syllables.map(\.hangul), c.syllables, c.name)
        }
    }
}
```

- [ ] **Step 4: 검증** — `cd core-swift && swift test` → 기존 53 + 신규 2 = 55개 통과. `swift run fixture-export && git diff --exit-code -- ../spec/fixtures` → 멱등 확인.

- [ ] **Step 5: Commit** — `git add core-swift spec && git commit -m "feat: 언어 중립 골든 픽스처 + conformance 러너"`

---

### Task 4: SPEC.md — 포팅 명세

**Files:**
- Create: `spec/SPEC.md`

**Interfaces:**
- Produces: Kotlin(Android)·브리지(Windows) 포트가 읽는 유일한 알고리즘 명세. 코드 대신 이 문서 + mapping.tsv + fixtures가 포트의 요구사항이다.

- [ ] **Step 1: SPEC.md 작성** — 다음 내용을 담는다 (Swift 소스와 대조하며 작성하되, 문서에는 Swift 코드가 아닌 언어 중립 서술만):

  1. **키맵**: 2벌식 라틴→자모 표 전체 (Jamo.swift의 table과 동일한 34항목 + "배정 없는 대문자는 소문자와 동일" 규칙)
  2. **음절 automaton**: 상태 = 현재 음절(초성?, 중성?, 종성?); 전이 규칙 — 자음 도착(초성 없으면 초성 / 중성 있고 종성 가능(ㄸㅃㅉ 제외)하면 종성 / 아니면 flush 후 새 초성), 모음 도착(종성 있으면 **재해석**: 종성이 새 음절 초성으로 / 중성 없으면 중성 / 복합모음 결합표(ㅗ+ㅏ=ㅘ, ㅗ+ㅐ=ㅙ, ㅗ+ㅣ=ㅚ, ㅜ+ㅓ=ㅝ, ㅜ+ㅔ=ㅞ, ㅜ+ㅣ=ㅟ, ㅡ+ㅣ=ㅢ) / 아니면 flush 후 새 중성), 백스페이스 = 자모 스트림 1개 제거 후 전체 재계산
  3. **가나 매핑**: 음절 = 몸통(초성×중성, mapping.tsv body) + 종성(mapping.tsv final, ん/っ). 몸통 또는 종성이 표에 없으면 음절 전체 매핑 불가 → 한글 그대로 표시, fullyMapped=false
  4. **기호**: `-`=ー(조합 스트림에 포함), `.`→。 `,`→、(셸 레벨)
  5. **픽스처 포맷**: kana.json / composition.json 스키마와 러너 의무 (모든 포트는 두 픽스처 전부 통과하는 테스트를 CI에 가져야 함)
  6. **변경 절차**: mapping.tsv/fixtures 수정 → gen-swift + fixture-export 재실행 → Swift 테스트 → 각 포트 갱신

- [ ] **Step 2: 자기 대조** — SPEC.md의 복합모음 표·전이 규칙이 JamoComposer.swift와, 키맵 표가 Jamo.swift와 일치하는지 항목별 확인 (불일치 발견 시 SPEC.md를 코드에 맞춘다 — 코드가 레퍼런스).

- [ ] **Step 3: Commit** — `git add spec/SPEC.md && git commit -m "docs: 포팅용 automaton·키맵·매핑 명세"`

---

### Task 5: conformance CI (.github/workflows/core.yml)

**Files:**
- Create: `.github/workflows/core.yml`

- [ ] **Step 1: 워크플로 작성**

```yaml
name: core
on:
  push:
    branches: [main]
  pull_request:

jobs:
  swift:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: |
            core-swift/.build
            macos/.build
          key: spm-${{ runner.os }}-${{ hashFiles('core-swift/Package.resolved') }}
      - name: Core tests (fixtures 포함)
        run: swift test --package-path core-swift
      - name: macOS shell release build
        run: swift build -c release --package-path macos
      - name: 생성물 최신성 (테이블·픽스처)
        run: |
          swift spec/generators/gen-swift.swift
          swift run --package-path core-swift fixture-export
          git diff --exit-code
```

- [ ] **Step 2: YAML 문법 확인** — `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/core.yml'))"` (pyyaml 없으면 `ruby -ryaml -e "YAML.load_file('.github/workflows/core.yml')"`)

- [ ] **Step 3: Commit** — `git add .github && git commit -m "ci: conformance 워크플로 (테스트 + 생성물 최신성)"`

주: 실제 러너 검증은 push 후 컨트롤러가 확인한다. Swift 버전이 엔진 요구(6.1+)에 못 미치면 `maxim-lobanov/setup-xcode@v1`로 Xcode 버전을 명시하는 후속 수정이 필요할 수 있다 — 실패 시 그 방향으로 조치.

---

### Task 6: README 갱신 + 최종 검증

**Files:**
- Modify: `README.md` (개발 섹션의 구조 트리·명령 경로 갱신, 멀티플랫폼 로드맵 1문단 추가)

- [ ] **Step 1: README 개발 섹션 갱신** — 구조 트리를 새 레이아웃(spec/, core-swift/, macos/ + ios/·android/·windows/ 예정 표기)으로 교체하고, 명령을 `swift test --package-path core-swift` / `./macos/scripts/install-dev.sh`로 수정. "현재 제한" 위에 짧은 로드맵 문단: iOS·Android는 같은 엔진으로, Windows는 Google 일본어 입력 테이블/브리지로 지원 예정.

- [ ] **Step 2: 전체 최종 검증**

```bash
swift test --package-path core-swift 2>&1 | grep "Test Suite 'All tests'"
swift build -c release --package-path macos 2>&1 | tail -1
./macos/scripts/install-dev.sh
swift spec/generators/gen-swift.swift && swift run --package-path core-swift fixture-export && git diff --exit-code
```

Expected: 55개 테스트 통과, 빌드·설치 성공, 생성물 diff 없음.

- [ ] **Step 3: Commit** — `git add README.md && git commit -m "docs: 멀티플랫폼 구조 반영"`

---

## Self-Review 결과

1. **스펙 커버리지**: 설계 §3 구조→T1, §4 conformance(TSV·픽스처·러너·멱등)→T2–3, SPEC.md→T4, §6 CI→T5, §7 완료정의(테스트 통과·생성물 동일·macOS 정상·CI)→T1/T2/T5/T6. gen-kotlin·gen-mozc-table은 서브프로젝트 3·4 범위로 의도적 제외.
2. **플레이스홀더**: 없음. SPEC.md(T4)는 내용 요목을 명시하고 "코드가 레퍼런스" 대조 절차를 규정 — 문서 태스크의 성격상 산문 자체는 구현 시 작성.
3. **타입 일관성**: `KanaTable.body/finals` 시그니처(T2 생성기 출력 ↔ T2 KanaMapper 소비) 일치. `fixture-export` 타깃명(T1 주석·T3 Package 추가·T5 CI) 일치. `#filePath` 상향 횟수: DumpTSV(Tests/HanguljiCoreTests/파일 → core-swift → 루트 = 4회) ✓, fixture-export(Sources/fixture-export/main.swift → core-swift → 루트 = 4회) ✓, FixtureTests(4회) ✓.
4. **검산**: composition 픽스처 keys — rksl=ㄱㅏㄴㅣ ✓, rksdl=ㄱㅏㄴㅇㅣ ✓, dnj=ㅇㅜㅓ ✓, ghk=ㅎㅗㅏ ✓, zkk ✓, tktvh=ㅅㅏㅅㅍㅗ ✓, zkEk=ㅋㅏㄸㅏ ✓. kana 케이스의 한글 표기는 fixture-export 자기검증이 최종 안전망.
