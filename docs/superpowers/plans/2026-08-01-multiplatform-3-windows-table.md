# 멀티플랫폼 서브프로젝트 3: Windows 1단계 — Google 일본어 입력 테이블 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 코드 제로로 Windows에서 한글지 방식 일본어 입력(한자 포함) — spec/mapping.tsv에서 Google 일본어 입력용 커스텀 로마자 테이블을 생성하고, 같은 kana 픽스처로 conformance를 증명하며, 설치 가이드를 제공한다.

**Architecture:** Google 일본어 입력(=mozc)의 로마자 테이블은 `input\toutput\tnext_input` 상태머신이다. 몸통 음절은 (초성 라틴 + 모음 스트로크)→가나 항목으로, **받침 재해석은 next_input 체인으로 자동 해결**된다: 받침 자음은 단독으로는 대기하다가(ㄴ+모음이면 다음 음절 항목이 매칭) 자음이 뒤따르면 ん/っ을 출력하고 그 자음을 pending으로 되민다. 생성기는 순수 Swift 스크립트, conformance는 mozc 테이블 automaton을 Swift 테스트에서 시뮬레이션해 kana 픽스처 전건을 검증한다.

**Tech Stack:** Swift 스크립트(생성기), XCTest(시뮬레이터 테스트), Google 일본어 입력(사용자 설치)

**Spec:** 설계 §5.4 1단계, §7 SP3 완료 정의 (테이블+가이드 커밋, 커버리지 문서화, 실행 검증은 보류 명시)

## Global Constraints

- 산출물 `windows/hangulji-romaji-table.txt`는 생성기 전용(수기 수정 금지 헤더), 멱등·결정적. 유일한 원천은 spec/mapping.tsv
- 생성기는 중복 input을 fatalError로 거부, 항목 수 요약을 출력(커버리지 리포트)
- conformance: kana 픽스처의 fullyMapped 케이스 **전건**이 테이블 시뮬레이션과 일치해야 한다. unmappable 케이스와 composition 픽스처는 명시적 스킵(사유 문서화 — 테이블은 한글을 출력할 수 없음)
- 라틴 키 매핑은 Keymap과 동일(2벌식). 자음 키 = q w e r t a s d f g z x c v Q W E R T (19), 모음 키 = 나머지
- 받침 매핑: ㄴ(s)·ㅇ(d)·ㅁ(a)→ん, ㅅ(t)·ㄱ(r)·ㅂ(q)·ㄷ(e)→っ — mapping.tsv의 final 행에서 파생 (하드코딩 금지: TSV의 final 행을 읽어 라틴 키로 변환)
- core-swift/ 기존 소스·spec/mapping.tsv·fixtures 수정 금지 (테스트 파일 추가만 허용)
- 커밋 메시지 트레일러 금지. 각 태스크에서 `swift test --package-path core-swift` 전체 통과

## File Structure

```
spec/generators/gen-mozc-table.swift    # TSV → windows/hangulji-romaji-table.txt
windows/
├── hangulji-romaji-table.txt           # 생성 산출물 (커밋됨)
└── README.md                           # 설치·사용 가이드 + 한계
core-swift/Tests/HanguljiCoreTests/MozcTableTests.swift   # conformance 시뮬레이터
.github/workflows/core.yml              # freshness 스텝에 gen-mozc-table + windows/ diff 추가
```

---

### Task 1: gen-mozc-table 생성기 + 테이블 산출

**Files:**
- Create: `spec/generators/gen-mozc-table.swift`, `windows/hangulji-romaji-table.txt`(산출)

**Interfaces:**
- Produces: 테이블 파일 형식 — 탭 구분 3열 `input\toutput\tnext_input`(next 없으면 빈칸), `#` 주석 헤더. Task 2 시뮬레이터와 Google 일본어 입력 import가 이 형식을 소비.

- [ ] **Step 1: 생성기 작성** (`spec/generators/gen-mozc-table.swift`)

```swift
#!/usr/bin/env swift
// spec/mapping.tsv → windows/hangulji-romaji-table.txt (Google 일본어 입력 로마자 테이블)
// 사용: swift spec/generators/gen-mozc-table.swift (저장소 루트에서)
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let tsvURL = root.appendingPathComponent("spec/mapping.tsv")
let outURL = root.appendingPathComponent("windows/hangulji-romaji-table.txt")

guard let tsv = try? String(contentsOf: tsvURL, encoding: .utf8) else {
    fatalError("spec/mapping.tsv 를 읽을 수 없음 — 저장소 루트에서 실행했는가?")
}

// 2벌식 라틴 키 (Keymap과 동일해야 함 — conformance 테스트가 검증망)
let consonantKey: [String: String] = [
    "ㄱ": "r", "ㄲ": "R", "ㄴ": "s", "ㄷ": "e", "ㄸ": "E", "ㄹ": "f", "ㅁ": "a",
    "ㅂ": "q", "ㅃ": "Q", "ㅅ": "t", "ㅆ": "T", "ㅇ": "d", "ㅈ": "w", "ㅉ": "W",
    "ㅊ": "c", "ㅋ": "z", "ㅌ": "x", "ㅍ": "v", "ㅎ": "g",
]
// 모음 → 키 스트로크 (복합모음은 2타)
let vowelStrokes: [String: String] = [
    "ㅏ": "k", "ㅐ": "o", "ㅑ": "i", "ㅒ": "O", "ㅔ": "p", "ㅖ": "P",
    "ㅗ": "h", "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅛ": "y", "ㅜ": "n",
    "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅠ": "b", "ㅡ": "m", "ㅢ": "ml", "ㅣ": "l",
]
let allConsonantKeys = "qwertasdfgzxcvQWERT".map(String.init)

struct Entry { let input: String; let output: String; let next: String }
var entries: [Entry] = []
var seen = Set<String>()

func add(_ input: String, _ output: String, _ next: String, line: String) {
    guard seen.insert(input).inserted else { fatalError("중복 input '\(input)' ← \(line)") }
    entries.append(Entry(input: input, output: output, next: next))
}

var bodyCount = 0
var finalRows: [(key: String, kana: String)] = []

for rawLine in tsv.split(separator: "\n") {
    let line = String(rawLine)
    if line.hasPrefix("#") || line.isEmpty { continue }
    let cols = line.components(separatedBy: "\t")
    guard cols.count == 4 else { fatalError("잘못된 TSV 행: \(line)") }
    switch cols[0] {
    case "body":
        guard let ck = consonantKey[cols[1]], let vs = vowelStrokes[cols[2]] else {
            fatalError("알 수 없는 자모: \(line)")
        }
        add(ck + vs, cols[3], "", line: line)
        bodyCount += 1
    case "final":
        guard let ck = consonantKey[cols[1]] else { fatalError("알 수 없는 자모: \(line)") }
        finalRows.append((ck, cols[3]))
    default:
        fatalError("알 수 없는 kind: \(line)")
    }
}

// 받침 규칙: 단독(입력 종료 시 확정) + 자음이 뒤따르면 출력 후 그 자음을 pending으로
var finalPairCount = 0
for (key, kana) in finalRows.sorted(by: { $0.key < $1.key }) {
    add(key, kana, "", line: "final-terminal \(key)")
    for c in allConsonantKeys {
        add(key + c, kana, c, line: "final-pair \(key)+\(c)")
        finalPairCount += 1
    }
}

add("-", "ー", "", line: "prolonged")

var lines = [
    "# 한글지 — Google 일본어 입력용 커스텀 로마자 테이블",
    "# spec/mapping.tsv 에서 생성됨 — 수기 수정 금지. 재생성: swift spec/generators/gen-mozc-table.swift",
    "# 형식: input<TAB>output<TAB>next_input",
]
for e in entries {
    lines.append("\(e.input)\t\(e.output)\t\(e.next)")
}
try! FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try! (lines.joined(separator: "\n") + "\n").write(to: outURL, atomically: true, encoding: .utf8)
print("wrote \(outURL.path)")
print("커버리지: body \(bodyCount), final 단독 \(finalRows.count), final 연쇄 \(finalPairCount), 기호 1 — 총 \(entries.count)항목")
print("TSV 인코딩 불가 항목: 0 (전 셀 인코딩됨)")
```

- [ ] **Step 2: 실행 및 검증**

```bash
swift spec/generators/gen-mozc-table.swift
head -8 windows/hangulji-romaji-table.txt
grep -c $'\t' windows/hangulji-romaji-table.txt   # 데이터 행 수
swift spec/generators/gen-mozc-table.swift && git diff --stat -- windows   # 멱등
```

Expected: 커버리지 라인 출력 (body 159, final 단독 7, 연쇄 133, 총 300), 재실행 diff 없음.

- [ ] **Step 3: Commit** — `git add spec/generators/gen-mozc-table.swift windows/ && git commit -m "feat(windows): Google 일본어 입력용 로마자 테이블 생성기"`

---

### Task 2: conformance 시뮬레이터 테스트

**Files:**
- Create: `core-swift/Tests/HanguljiCoreTests/MozcTableTests.swift`

**Interfaces:**
- Consumes: `windows/hangulji-romaji-table.txt`, `spec/fixtures/kana.json`
- Produces: 테이블이 Swift 레퍼런스와 동일하게 동작함을 CI에서 상시 증명. mozc automaton 의미론(대기/최장일치/next_input)을 그대로 구현.

- [ ] **Step 1: 테스트 작성**

```swift
import XCTest

/// Google 일본어 입력(mozc) 로마자 테이블 automaton 시뮬레이터.
/// 의미론: 키를 pending에 누적 → pending이 어떤 항목의 진접두사면 대기,
/// 정확 일치가 있고 확장 불가면 적용(출력+next를 pending으로), 그 외엔 최장 정확 접두사를 떼어 적용.
final class MozcTableTests: XCTestCase {
    struct Rule { let output: String; let next: String }

    private static var rules: [String: Rule] = [:]
    private static var prefixes: Set<String> = []   // 모든 input의 진접두사 집합

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    override class func setUp() {
        super.setUp()
        let url = repoRoot.appendingPathComponent("windows/hangulji-romaji-table.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("테이블 없음: \(url.path) — gen-mozc-table 먼저 실행")
        }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2 else { continue }
            let input = cols[0]
            rules[input] = Rule(output: cols[1], next: cols.count > 2 ? cols[2] : "")
            var prefix = ""
            for ch in input.dropLast() {
                prefix.append(ch)
                prefixes.insert(prefix)
            }
        }
    }

    private func hasExtension(_ s: String) -> Bool { Self.prefixes.contains(s) }

    private func simulate(_ keys: String) -> String {
        var output = ""
        var pending = ""

        func step() {
            while true {
                if let rule = Self.rules[pending], !hasExtension(pending) {
                    output += rule.output
                    pending = rule.next
                    continue
                }
                if hasExtension(pending) || pending.isEmpty { return }
                // 정확 일치 없음·확장 불가 → 최장 정확 접두사 분리
                var prefix = pending
                while !prefix.isEmpty, Self.rules[prefix] == nil { prefix.removeLast() }
                if prefix.isEmpty {
                    output.append(pending.removeFirst())   // 매핑 불가 키는 그대로
                } else {
                    let rule = Self.rules[prefix]!
                    output += rule.output
                    pending = rule.next + pending.dropFirst(prefix.count)
                }
            }
        }

        for key in keys {
            pending.append(key)
            step()
        }
        // 입력 종료(변환 시점): 남은 pending을 정확 일치로 해소
        while !pending.isEmpty {
            if let rule = Self.rules[pending] {
                output += rule.output
                pending = rule.next
            } else {
                var prefix = pending
                while !prefix.isEmpty, Self.rules[prefix] == nil { prefix.removeLast() }
                if prefix.isEmpty { output.append(pending.removeFirst()) }
                else {
                    let rule = Self.rules[prefix]!
                    output += rule.output
                    pending = rule.next + pending.dropFirst(prefix.count)
                }
            }
        }
        return output
    }

    func testKanaFixturesThroughTable() throws {
        struct Case: Decodable { let name: String; let keys: String; let kana: String; let fullyMapped: Bool }
        let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent("spec/fixtures/kana.json"))
        let cases = try JSONDecoder().decode([Case].self, from: data)
        var checked = 0
        for c in cases {
            // 테이블은 한글을 출력할 수 없으므로 매핑 불가 케이스는 대상 외 (windows/README에 문서화)
            guard c.fullyMapped else { continue }
            XCTAssertEqual(simulate(c.keys), c.kana, c.name)
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 44)
    }

    func testBatchimReanalysisThroughTable() {
        XCTAssertEqual(simulate("rksl"), "がに")     // 받침 재해석
        XCTAssertEqual(simulate("rksdl"), "がんい")  // 명시적 ㅇ
        XCTAssertEqual(simulate("rks"), "がん")      // 어말 받침
        XCTAssertEqual(simulate("tktvhfh"), "さっぽろ")
        XCTAssertEqual(simulate("dhs"), "おん")      // 온
        XCTAssertEqual(simulate("dh"), "お")         // 대기 중 종료
    }
}
```

- [ ] **Step 2: 실행** — `swift test --package-path core-swift --filter MozcTableTests` → 2개 통과. 실패 시: 기대값(kana)이 진실 — 생성기의 규칙(받침 연쇄·모음 스트로크)을 의심하고 수정. **mapping.tsv·fixtures·기존 소스 수정 금지.** 해결 불가면 BLOCKED 보고.

- [ ] **Step 3: 전체 회귀** — `swift test --package-path core-swift` (55 + 2 = 57 통과)

- [ ] **Step 4: Commit** — `git add core-swift/Tests/HanguljiCoreTests/MozcTableTests.swift && git commit -m "test(windows): mozc 테이블 automaton conformance (kana 픽스처 전건)"`

---

### Task 3: 설치 가이드 + CI freshness 확장 + 문서

**Files:**
- Create: `windows/README.md`
- Modify: `.github/workflows/core.yml`(freshness 스텝), `README.md`(로드맵·구조 트리)

- [ ] **Step 1: windows/README.md 작성** — 다음 내용 (한국어):
  1. **개요**: Windows에서는 별도 프로그램 설치 없이 Google 일본어 입력의 커스텀 로마자 테이블로 한글지 방식을 쓴다. 한자 변환·후보·학습은 Google 엔진 그대로
  2. **설치**: ① Google 일본어 입력 설치(공식 링크) ② 속성 → 일반 → ローマ字テーブル(로마자 테이블) 편집 → 기존 항목 전체 선택·삭제 → `hangulji-romaji-table.txt` 내용으로 가져오기/붙여넣기 ③ 입력 모드 ひらがな, 하드웨어 자판은 **영문 모드**로 두고 2벌식 위치로 타이핑
  3. **사용법**: 토우쿄우(xhdnzydn 위치) → 화면에 とうきょう → 스페이스 변환 → 東京. 받침·별칭·장음 규칙은 루트 README와 동일
  4. **한계(정직하게)**: 일본어에 없는 한글 음절은 라틴 문자가 그대로 남음(맥·iOS는 한글로 표시됨), 표기 규칙 변경 시 테이블 재가져오기 필요, **실기기 검증 미완**(Windows 기기 확보 시 검증 예정 — conformance는 CI 시뮬레이션으로 증명됨)
  5. **재생성**: `swift spec/generators/gen-mozc-table.swift`

- [ ] **Step 2: CI freshness 확장** — core.yml의 "생성물 최신성" 스텝에 `swift spec/generators/gen-mozc-table.swift` 추가하고 diff 범위에 `windows`를 포함:

```yaml
          swift spec/generators/gen-swift.swift
          swift spec/generators/gen-mozc-table.swift
          swift run --package-path core-swift fixture-export
          git diff --exit-code -- spec windows core-swift/Sources/HanguljiCore/KanaTable.generated.swift
```

- [ ] **Step 3: 루트 README 갱신** — 설치 섹션에 Windows 항목 추가(windows/README.md 링크, "코드 제로 — Google 일본어 입력 테이블" 한 줄), 로드맵에서 Windows 1단계 → 완료(실기기 검증 보류), 구조 트리에 windows/ 실구조

- [ ] **Step 4: 최종 검증** — `swift test --package-path core-swift`(57), 생성기 2종+픽스처 멱등 diff 없음, ruby YAML 검증

- [ ] **Step 5: Commit** — `git add windows README.md .github && git commit -m "docs(windows): 설치 가이드 + CI freshness에 테이블 포함"`

---

## Self-Review 결과

1. **스펙 커버리지**: §5.4 1단계(테이블 생성기+가이드+커버리지 리포트+한계 문서화) 전부, §7 SP3 완료 정의 충족. 브리지(2단계)는 SP5로 유보.
2. **플레이스홀더**: 없음.
3. **검산**: 커버리지 산식 — body 159, final 단독 7, 연쇄 7×19=133, 기호 1 → 총 300 ✓. 받침 재해석 트레이스(rksl→がに, rksdl→がんい, 종료 시 rks→がん) 본문 automaton으로 수기 검증 ✓. 자음/모음 키 분리로 body(자음+모음)와 연쇄(자음+자음) input 충돌 없음 ✓. 복합모음 대기(dh→dhk)는 mozc 최장일치 대기 의미론으로 처리 ✓.
4. **타입/경로 일관성**: #filePath 4단계 상향(core-swift/Tests/HanguljiCoreTests/ → 루트) ✓, 테이블 경로·픽스처 경로 Task 1↔2 일치 ✓, checked ≥ 44 (fullyMapped 44건: 45 - unmappable 1) ✓.
