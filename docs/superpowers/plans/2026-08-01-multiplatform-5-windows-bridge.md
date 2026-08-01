# 멀티플랫폼 서브프로젝트 5: Windows 2단계 — 키 변환 브리지 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 설치형 Windows 브리지 — 상주 exe(Rust)가 2벌식 키입력을 MS-IME 로마자 키스트림으로 변환해 활성 일본어 IME에 주입한다. 가나 조합·한자 변환은 호스트 IME(MS-IME)가 담당하므로 브리지는 키 변환만 한다. 완료 정의(§7 SP5): **CI에서 브리지 exe 빌드 + 변환 로직 픽스처 테스트 통과** — Windows 실행 검증은 명시적 보류(기기 없음).

**Architecture:** 핵심은 **순수(플랫폼 무관) translator 모듈**과 **얇은 Windows 셸**의 분리다. translator는 1단계(`windows/hangulji-romaji-table.txt`)에서 검증된 mozc 테이블 상태머신(input/output/next_input — 받침 대기·최장일치·pending 재투입)을 그대로 재사용하되, **출력만 가나 대신 MS-IME 로마자 철자**로 바꾼 테이블을 쓴다. 자모 단위 무상태 방출은 기각 — ㄲ은 か행 별칭이라 "kk"가 아니라 "k"여야 하고(ㄲ카→"kka"=っか 오류), 쓰=つ(ssu 불가)·ㅝ=を(wo) 같은 대응은 **셀(음절) 단위**에서만 재현되기 때문이다. 테이블은 새 생성기 `spec/generators/gen-bridge-table.swift`가 `spec/mapping.tsv` + 가나→로마자 모라 표에서 생성한다. conformance는 Windows 없이 CI에서 루프를 닫는다: 픽스처 키열 → translator → 로마자 → **오라클**(같은 모라 표의 역표로 만든 로마자→가나 automaton = MS-IME 로마자 처리의 결정적 부분집합) → 가나가 픽스처 기대값과 일치해야 한다. Windows 셸은 WH_KEYBOARD_LL 훅(트리비얼 훅 프로시저 + 채널 + 워커 스레드), LLKHF_INJECTED 재귀 방지, Ctrl+Space 자체 토글(IME 상태 추적 안 함), SendInput은 **VK 키스트로크만**(KEYEVENTF_UNICODE 금지 — 일본어 IME의 로마자 automaton이 소비해야 함).

**Tech Stack:** Rust(edition 2021, rust-version 1.75, 로컬 cargo 1.95 확인됨) / windows crate 0.61(cfg(windows) 한정 의존성) / serde·serde_json(dev-dependencies만) / Swift 스크립트(생성기) / GitHub Actions windows-2022(Rust 프리인스톨 — `rustup default stable`로 확인)

**Spec:** `docs/superpowers/specs/2026-07-31-hangulji-multiplatform-design.md` §5.4 2단계, §6(windows.yml), §7(SP5 완료 정의), §8(리스크: Windows 실행 검증 불가 → 책임 범위 한정) + `spec/SPEC.md` §1(키맵)·§6(픽스처 러너 의무) + `spec/mapping.tsv` + `spec/fixtures/*.json`

## Global Constraints

- **검증 범위는 §7 SP5 완료 정의가 전부**: "CI에서 브리지 exe 빌드 + 변환 로직 픽스처 테스트 통과". Windows 실기기 실행 검증은 **명시적 보류**(기기 없음) — 실행 검증을 시도·약속하지 말고, 보류 사실을 README에 그대로 적는다. 그 이상(트레이 아이콘, 설정 파일, 설치 스크립트 등)은 범위 밖
- **spec 파일 불가침**: `spec/mapping.tsv`·`spec/SPEC.md`·`spec/fixtures/*.json` 수정 금지. 이 계획에서 spec/에 추가되는 파일은 `spec/generators/gen-bridge-table.swift` 하나뿐
- **생성물 전용**: `windows/bridge/src/table_generated.rs`는 gen-bridge-table.swift 산출물 — 수기 수정 금지 헤더 필수, core.yml 최신성 검사(생성 후 diff 0) 대상. 기대 규모: KEY_TO_ROMAJI 300항목(body 159 + final 단독 7 + final 연쇄 133 + 기호 1), ROMAJI_TO_KANA 116모라
- **변경 허용 범위**: `windows/bridge/**` + `spec/generators/gen-bridge-table.swift` + `.github/workflows/**` + 루트 `README.md`. 그 외 — `core-swift/`·`macos/`·`ios/`·`android/`·`windows/README.md`·`windows/hangulji-romaji-table.txt` — 절대 무수정
- **커밋 메시지에 Co-Authored-By 등 트레일러 절대 금지** — SP4에서 서브에이전트 2명이 위반했다. 매 태스크의 커밋 스텝마다 재확인한다(`git log -1 --format=%B`로 검증). 이것은 태스크별 선택 사항이 아니라 전 태스크 공통 하드 룰이다
- **주입 방식**: SendInput은 VK 키 이벤트만. KEYEVENTF_UNICODE 사용 금지 — 유니코드 주입은 IME 조합을 우회하므로 MS-IME 로마자 automaton이 소비할 수 없다(리서치 확정: 로마자 키 공급은 MS-IME에서 동작)
- **훅 프로시저는 트리비얼**: LowLevelHooksTimeout 초과 시 OS가 훅을 제거한다 — 훅 안에서는 분류 + 채널 송신 + 삼킴 판정만, 변환·SendInput은 워커 스레드에서
- **LLKHF_INJECTED 이벤트는 무조건 즉시 통과** — 자기 주입 재귀 방지, 훅 프로시저의 첫 검사
- **로마자 철자 원천은 생성기의 kanaToRomaji 하나**: 훈령식 우선(si/ti/tu/zi/di/du — 전단사 확보), ん=nn·っ=xtu(문맥 무관), 확장은 thi/dhi/twu/dwu/fa행/wi/we. 생성기가 전단사·접두사 자유를 fatalError로 강제한다. MS-IME 실물 수용 여부는 실기기 검증 보류 항목으로 문서화
- **Rust 의존성 최소**: 런타임 의존성은 `windows`(cfg(windows) 타깃 한정)만. serde/serde_json은 dev-dependencies. `Cargo.lock` 커밋(바이너리 크레이트)
- **테스트는 windows-gated 금지**: translator·conformance 테스트는 순수 모듈만 사용 — macOS에서 `cargo test --manifest-path windows/bridge/Cargo.toml`이 전건 통과해야 한다(매 태스크 종료 조건, Task 2부터)
- **픽스처 러너 의무(SPEC §6)**: kana.json 전 케이스 순회(개수 하드코딩 금지, fullyMapped 최소치 38만 검사), composition.json은 무패닉 스모크 + 받침 재해석 trace 테스트로 커버 — 음절(한글) 목록 검증 불가 사유(브리지는 자모 조합기가 없고 한글을 출력할 수 없음)는 README에 문서화(1단계 MozcTableTests 선례와 동일)

## 2벌식 키 ↔ 라틴 문자 (SPEC §1 — 생성기 키맵의 유일한 근거)

```
자음: ㅂq ㅈw ㄷe ㄱr ㅅt ㅁa ㄴs ㅇd ㄹf ㅎg ㅋz ㅌx ㅊc ㅍv + ㅃQ ㅉW ㄸE ㄲR ㅆT (19)
모음: ㅛy ㅕu ㅑi ㅐo ㅔp ㅗh ㅓj ㅏk ㅣl ㅠb ㅜn ㅡm + ㅒO ㅖP (복합: ㅘhk ㅙho ㅚhl ㅝnj ㅞnp ㅟnl ㅢml)
받침(TSV final): ㄴs·ㅇd·ㅁa → ん / ㅅt·ㄱr·ㅂq·ㄷe → っ. 기호: - → ー
```

## File Structure

```
spec/generators/gen-bridge-table.swift   # mapping.tsv + 가나→로마자 표 → table_generated.rs (Task 1)
windows/bridge/
├── Cargo.toml                           # lib + bin, windows dep은 cfg(windows) 한정 (Task 1, 3에서 수정)
├── Cargo.lock                           # 커밋 대상
├── README.md                            # 사용법 + 한계 (Task 3)
├── src/
│   ├── lib.rs                           # pub mod table_generated; pub mod translator;
│   ├── main.rs                          # windows: 셸 구동 / 그 외 OS: 안내 후 종료
│   ├── table_generated.rs               # 생성 산출물 — 수기 수정 금지 (Task 1)
│   ├── translator.rs                    # 순수 Automaton — 브리지 본체 로직 (Task 2)
│   └── hook.rs                          # cfg(windows) bin 모듈: WH_KEYBOARD_LL + SendInput (Task 3)
└── tests/
    └── conformance.rs                   # spec/fixtures 러너 + 로마자→가나 오라클 (Task 2)
.github/workflows/core.yml               # 최신성 스텝에 gen-bridge-table 1줄 추가 (Task 1)
.github/workflows/windows-bridge.yml     # windows-2022: cargo test + build + exe 아티팩트 (Task 4)
README.md                                # Windows 2단계·구조·로드맵 갱신 (Task 4)
```

---

### Task 1: gen-bridge-table 생성기 + 크레이트 뼈대 + core.yml 최신성

**Files:**
- Create: `spec/generators/gen-bridge-table.swift`, `windows/bridge/Cargo.toml`, `windows/bridge/src/lib.rs`, `windows/bridge/src/main.rs`, `windows/bridge/src/table_generated.rs`(산출), `windows/bridge/Cargo.lock`(산출)
- Modify: `.github/workflows/core.yml`(최신성 스텝 1줄)

**Interfaces:**
- Produces: `hangulji_bridge::table_generated::KEY_TO_ROMAJI: &[(&str, &str, &str)]`(2벌식 키열, 로마자, next_input — 300항목), `ROMAJI_TO_KANA: &[(&str, &str, &str)]`(로마자, 가나, "" — 116항목). Task 2의 Automaton과 conformance 오라클이 이 두 상수를 소비한다.

- [ ] **Step 1: 생성기 작성** (`spec/generators/gen-bridge-table.swift`)

```swift
#!/usr/bin/env swift
// spec/mapping.tsv → windows/bridge/src/table_generated.rs (2단계 브리지 변환 테이블)
// 사용: swift spec/generators/gen-bridge-table.swift (저장소 루트에서)
//
// 1단계(gen-mozc-table)와 동일한 input/next_input 상태머신 구조에, 출력만 가나 대신
// MS-IME 로마자 철자로 바꾼 KEY_TO_ROMAJI와, 테스트 오라클용 역표 ROMAJI_TO_KANA를 생성한다.
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let tsvURL = root.appendingPathComponent("spec/mapping.tsv")
let outURL = root.appendingPathComponent("windows/bridge/src/table_generated.rs")

guard let tsv = try? String(contentsOf: tsvURL, encoding: .utf8) else {
    fatalError("spec/mapping.tsv 를 읽을 수 없음 — 저장소 루트에서 실행했는가?")
}

// ── 가나(1모라) → MS-IME 로마자 철자 ────────────────────────────────────────
// 철자 결정 원칙 (오라클 역변환 성립의 근거 — 아래 셋을 이 생성기가 fatalError로 강제):
//  1. 전단사: 서로 다른 가나에 같은 철자 금지 → 훈령식(si·ti·tu·zi·di·du)을 쓰면
//     し/じ/ち/ぢ/つ/づ/ず가 전부 다른 철자를 가진다 (헵번식은 ji·zu가 병합되어 불가)
//  2. 접두사 자유: 어떤 철자도 다른 철자의 접두사가 아님 → 오라클이 결정적
//  3. 문맥 자유: ん=nn(항상 — n 모호성 원천 차단), っ=xtu(항상 — 자음 중복 표기 불사용)
// 전부 MS-IME 기본 로마자 표의 표준 철자다. 실물 수용 여부는 실기기 검증 보류 항목
// (windows/bridge/README.md 한계 절 참고).
let kanaToRomaji: [String: String] = [
    "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
    "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
    "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
    "さ": "sa", "し": "si", "す": "su", "せ": "se", "そ": "so",
    "ざ": "za", "じ": "zi", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
    "た": "ta", "ち": "ti", "つ": "tu", "て": "te", "と": "to",
    "だ": "da", "ぢ": "di", "づ": "du", "で": "de", "ど": "do",
    "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
    "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
    "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu", "よ": "yo",
    "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
    "わ": "wa", "を": "wo",
    "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
    "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
    "しゃ": "sya", "しゅ": "syu", "しょ": "syo",
    "じゃ": "zya", "じゅ": "zyu", "じょ": "zyo",
    "ちゃ": "tya", "ちゅ": "tyu", "ちょ": "tyo",
    "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
    "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
    "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
    "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
    "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
    "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
    "てぃ": "thi", "でぃ": "dhi", "とぅ": "twu", "どぅ": "dwu",
    "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo",
    "うぃ": "wi", "うぇ": "we",
    "ん": "nn", "っ": "xtu", "ー": "-",
]

// 2벌식 라틴 키 (SPEC §1 — gen-mozc-table.swift와 동일해야 함. conformance가 검증망)
let consonantKey: [String: String] = [
    "ㄱ": "r", "ㄲ": "R", "ㄴ": "s", "ㄷ": "e", "ㄸ": "E", "ㄹ": "f", "ㅁ": "a",
    "ㅂ": "q", "ㅃ": "Q", "ㅅ": "t", "ㅆ": "T", "ㅇ": "d", "ㅈ": "w", "ㅉ": "W",
    "ㅊ": "c", "ㅋ": "z", "ㅌ": "x", "ㅍ": "v", "ㅎ": "g",
]
let vowelStrokes: [String: String] = [
    "ㅏ": "k", "ㅐ": "o", "ㅑ": "i", "ㅒ": "O", "ㅔ": "p", "ㅖ": "P",
    "ㅗ": "h", "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅛ": "y", "ㅜ": "n",
    "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅠ": "b", "ㅡ": "m", "ㅢ": "ml", "ㅣ": "l",
]
let allConsonantKeys = "qwertasdfgzxcvQWERT".map(String.init)

var usedMoras = Set<String>()

// 가나 셀 → 로마자. 셀 전체가 1모라(현 TSV 전부)면 직조회, 아니면 그리디 분해(2문자 우선).
func romaji(of kana: String, line: String) -> String {
    if let r = kanaToRomaji[kana] { usedMoras.insert(kana); return r }
    var rest = Substring(kana), out = ""
    while !rest.isEmpty {
        let two = String(rest.prefix(2))
        let one = String(rest.prefix(1))
        if rest.count >= 2, let r = kanaToRomaji[two] {
            usedMoras.insert(two); out += r; rest = rest.dropFirst(2)
        } else if let r = kanaToRomaji[one] {
            usedMoras.insert(one); out += r; rest = rest.dropFirst(1)
        } else {
            fatalError("로마자 철자 미정의 가나 '\(kana)' ← \(line) — kanaToRomaji에 추가 필요")
        }
    }
    return out
}

struct Entry { let input: String; let output: String; let next: String }
var entries: [Entry] = []
var seen = Set<String>()

func add(_ input: String, _ output: String, _ next: String, line: String) {
    guard seen.insert(input).inserted else { fatalError("중복 input '\(input)' ← \(line)") }
    entries.append(Entry(input: input, output: output, next: next))
}

var bodyCount = 0
var finalRows: [(key: String, romaji: String)] = []

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
        add(ck + vs, romaji(of: cols[3], line: line), "", line: line)
        bodyCount += 1
    case "final":
        guard let ck = consonantKey[cols[1]] else { fatalError("알 수 없는 자모: \(line)") }
        finalRows.append((ck, romaji(of: cols[3], line: line)))
    default:
        fatalError("알 수 없는 kind: \(line)")
    }
}

// 받침: 단독(경계에서 확정) + 자음이 뒤따르면 출력 후 그 자음을 pending으로 (1단계와 동일 구조)
var finalPairCount = 0
for (key, r) in finalRows.sorted(by: { $0.key < $1.key }) {
    add(key, r, "", line: "final-terminal \(key)")
    for c in allConsonantKeys {
        add(key + c, r, c, line: "final-pair \(key)+\(c)")
        finalPairCount += 1
    }
}

add("-", romaji(of: "ー", line: "prolonged"), "", line: "prolonged")

// ── 오라클 무결성 검증: 전단사 + 접두사 자유 ────────────────────────────────
var romajiToKana: [String: String] = [:]
for kana in usedMoras.sorted() {
    let r = kanaToRomaji[kana]!
    if let clash = romajiToKana[r] { fatalError("로마자 '\(r)' 충돌: \(clash) vs \(kana)") }
    romajiToKana[r] = kana
}
let spellings = romajiToKana.keys.sorted()
for a in spellings {
    for b in spellings where a != b && b.hasPrefix(a) {
        fatalError("접두사 위반: '\(a)' ⊂ '\(b)' — 오라클 결정성이 깨진다")
    }
}

// ── Rust 소스 방출 ──────────────────────────────────────────────────────────
var lines = [
    "// spec/mapping.tsv 에서 생성됨 — 수기 수정 금지. 재생성: swift spec/generators/gen-bridge-table.swift",
    "// (input, output, next_input) — 의미론은 translator.rs 의 Automaton 참조",
    "",
    "/// 2벌식 키열 → MS-IME 로마자 (브리지 본체 테이블 — 1단계 mozc 테이블과 같은 상태머신 구조)",
    "pub static KEY_TO_ROMAJI: &[(&str, &str, &str)] = &[",
]
for e in entries {
    lines.append("    (\"\(e.input)\", \"\(e.output)\", \"\(e.next)\"),")
}
lines.append("];")
lines.append("")
lines.append("/// 로마자 → 가나 — 테스트 오라클용 역표 (MS-IME 로마자 automaton의 결정적 부분집합)")
lines.append("pub static ROMAJI_TO_KANA: &[(&str, &str, &str)] = &[")
for r in spellings {
    lines.append("    (\"\(r)\", \"\(romajiToKana[r]!)\", \"\"),")
}
lines.append("];")

try! FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try! (lines.joined(separator: "\n") + "\n").write(to: outURL, atomically: true, encoding: .utf8)
print("wrote \(outURL.path)")
print("커버리지: KEY_TO_ROMAJI \(entries.count)항목 (body \(bodyCount), final 단독 \(finalRows.count), final 연쇄 \(finalPairCount), 기호 1) / ROMAJI_TO_KANA \(spellings.count)모라")
print("TSV 인코딩 불가 항목: 0 (실패 시 이 줄에 도달하기 전에 fatalError로 중단됨)")
```

- [ ] **Step 2: 생성기 실행 및 검증**

```bash
cd /Users/mastergear/hangulji
swift spec/generators/gen-bridge-table.swift
head -8 windows/bridge/src/table_generated.rs
swift spec/generators/gen-bridge-table.swift && git status --short windows/bridge   # 멱등
```

Expected: `커버리지: KEY_TO_ROMAJI 300항목 (body 159, final 단독 7, final 연쇄 133, 기호 1) / ROMAJI_TO_KANA 116모라`, 재실행 후 추가 diff 없음(신규 파일 1개만 untracked).

- [ ] **Step 3: 크레이트 뼈대 작성**

`windows/bridge/Cargo.toml`:

```toml
[package]
name = "hangulji-bridge"
version = "0.1.0"
edition = "2021"
rust-version = "1.75"

[lib]
name = "hangulji_bridge"
path = "src/lib.rs"

[[bin]]
name = "hangulji-bridge"
path = "src/main.rs"
```

`windows/bridge/src/lib.rs`:

```rust
//! 한글지 Windows 브리지 — 순수(플랫폼 무관) 변환 로직.
//! Windows 셸(훅·주입)은 bin 크레이트(main.rs + hook.rs)에만 있다.

pub mod table_generated;
```

`windows/bridge/src/main.rs`:

```rust
#[cfg(windows)]
fn main() {
    // Windows 셸은 Task 3에서 구현된다 (hook 모듈).
    println!("한글지 브리지 — 셸 미구현 (Task 3)");
}

#[cfg(not(windows))]
fn main() {
    eprintln!("hangulji-bridge는 Windows 전용 실행 파일입니다.");
    eprintln!("변환 로직 테스트는 어느 OS에서나: cargo test --manifest-path windows/bridge/Cargo.toml");
    std::process::exit(2);
}
```

- [ ] **Step 4: 빌드 확인**

```bash
cargo build --manifest-path windows/bridge/Cargo.toml
cargo test --manifest-path windows/bridge/Cargo.toml
```

Expected: 빌드 성공(경고 0), 테스트 0건 통과(`running 0 tests`). `windows/bridge/Cargo.lock` 생성됨.

- [ ] **Step 5: core.yml 최신성 스텝에 생성기 추가** — `.github/workflows/core.yml`의 "생성물 최신성" 스텝에서 `swift spec/generators/gen-mozc-table.swift` 줄 다음에 한 줄 추가:

```yaml
          swift spec/generators/gen-bridge-table.swift
```

diff 경로는 수정 불요 — 기존 `git diff --exit-code -- spec windows ...`의 `windows`가 `windows/bridge/src/table_generated.rs`를 이미 포함한다. (최신성 검사는 Swift가 있는 macOS 러너의 core.yml에서 수행 — windows 러너에는 Swift가 없다.)

- [ ] **Step 6: Commit** — 트레일러 금지(Co-Authored-By 절대 불가). 커밋 후 `git log -1 --format=%B`로 본문에 트레일러가 없는지 확인.

```bash
git add spec/generators/gen-bridge-table.swift windows/bridge .github/workflows/core.yml
git commit -m "feat(windows-bridge): 브리지 변환 테이블 생성기 + Rust 크레이트 뼈대"
```

---

### Task 2: translator 상태머신 + 픽스처 conformance (순수 Rust, macOS에서 실행)

**Files:**
- Create: `windows/bridge/src/translator.rs`, `windows/bridge/tests/conformance.rs`
- Modify: `windows/bridge/Cargo.toml`(dev-dependencies), `windows/bridge/src/lib.rs`(모듈 1줄)

**Interfaces:**
- Consumes: `table_generated::{KEY_TO_ROMAJI, ROMAJI_TO_KANA}` (Task 1)
- Produces: `translator::Automaton` — `new(table: &'static [(&'static str, &'static str, &'static str)]) -> Automaton`, `push(&mut self, ch: char) -> String`(지금 확정되는 출력, 대기 중이면 빈 문자열), `flush(&mut self) -> String`(커밋 경계 해소), `pop_pending(&mut self) -> bool`(백스페이스), `pending_len(&self) -> usize`. Task 3의 hook.rs 워커 스레드가 이 시그니처를 그대로 사용한다.

- [ ] **Step 1: dev-dependencies 추가** — `windows/bridge/Cargo.toml` 끝에:

```toml
[dev-dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

- [ ] **Step 2: 실패하는 conformance 테스트 작성** (`windows/bridge/tests/conformance.rs`)

```rust
//! spec/fixtures conformance 러너 (SPEC.md §6 — 포트의 러너 의무).
//! 검증 고리: 2벌식 키 → [translator] → 로마자 → [오라클: ROMAJI_TO_KANA automaton
//! = MS-IME 로마자 처리의 결정적 부분집합] → 가나 == 픽스처 기대값.
//! Windows 없이 CI에서 변환 로직의 루프를 닫는다. MS-IME 실물이 같은 철자를
//! 수용하는지만 실기기 검증 보류 항목이다 (windows/bridge/README.md).

use hangulji_bridge::table_generated::{KEY_TO_ROMAJI, ROMAJI_TO_KANA};
use hangulji_bridge::translator::Automaton;
use serde::Deserialize;
use std::path::PathBuf;

#[derive(Deserialize)]
struct KanaCase {
    name: String,
    keys: String,
    kana: String,
    #[serde(rename = "fullyMapped")]
    fully_mapped: bool,
}

#[derive(Deserialize)]
struct CompositionCase {
    #[allow(dead_code)]
    name: String,
    keys: String,
    #[allow(dead_code)]
    syllables: Vec<String>,
}

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/fixtures").join(name)
}

/// 키 시퀀스 → (translator) 로마자 → (오라클) 가나
fn keys_to_kana(keys: &str) -> String {
    let mut translator = Automaton::new(KEY_TO_ROMAJI);
    let mut oracle = Automaton::new(ROMAJI_TO_KANA);
    let mut kana = String::new();
    for ch in keys.chars() {
        for r in translator.push(ch).chars() {
            kana.push_str(&oracle.push(r));
        }
    }
    for r in translator.flush().chars() {
        kana.push_str(&oracle.push(r));
    }
    kana.push_str(&oracle.flush());
    kana
}

#[test]
fn kana_fixtures_roundtrip_through_msime_romaji() {
    let data = std::fs::read_to_string(fixture("kana.json")).expect("kana.json 읽기");
    let cases: Vec<KanaCase> = serde_json::from_str(&data).expect("kana.json 파싱");
    let mut checked = 0;
    for case in &cases {
        if !case.fully_mapped {
            // 브리지는 호스트 IME에 로마자를 흘리므로 한글을 출력할 수 없다 —
            // 매핑 불가 케이스는 무패닉·비어있지 않은 결정적 열화만 확인
            // (1단계 MozcTableTests 선례와 동일. windows/bridge/README.md 한계 절 문서화)
            assert!(!keys_to_kana(&case.keys).is_empty(), "{}", case.name);
            continue;
        }
        assert_eq!(keys_to_kana(&case.keys), case.kana, "케이스 {}", case.name);
        checked += 1;
    }
    assert!(checked >= 38, "fullyMapped 케이스가 SPEC §6.1 최소치(38) 미만: {checked}");
}

#[test]
fn composition_fixtures_smoke() {
    // 브리지에는 자모 음절 조합기(JamoComposer)가 없어 §6.2의 한글 음절 목록 검증은
    // 구조적으로 불가 — 전 케이스 무패닉 처리 + §2.3 받침 재해석 의미론은 아래
    // batchim_reanalysis_traces가 가나 레벨에서 고정한다 (1단계 선례와 동일한 범위 한정)
    let data = std::fs::read_to_string(fixture("composition.json")).expect("composition.json 읽기");
    let cases: Vec<CompositionCase> = serde_json::from_str(&data).expect("composition.json 파싱");
    assert!(cases.len() >= 8);
    for case in &cases {
        let _ = keys_to_kana(&case.keys); // 무패닉·결정적 처리 확인
    }
}

#[test]
fn batchim_reanalysis_traces() {
    assert_eq!(keys_to_kana("rksl"), "がに");      // 가+니 — 받침 재해석 (composition: reanalysis-kani)
    assert_eq!(keys_to_kana("rksdl"), "がんい");   // 간+이 — 명시적 ㅇ (explicit-ng-kan-i)
    assert_eq!(keys_to_kana("rks"), "がん");       // 어말 받침 — flush 확정
    assert_eq!(keys_to_kana("tktvh"), "さっぽ");   // 삿+포 — 촉음 연쇄 (final-then-consonant)
    assert_eq!(keys_to_kana("zkEk"), "かた");      // ㄸ는 받침 불가 → 새 음절 (dd-cannot-be-final)
    assert_eq!(keys_to_kana("dh"), "お");          // 복합모음(ㅘ) 대기 중 flush → お 확정
}
```

- [ ] **Step 3: 실패 확인**

```bash
cargo test --manifest-path windows/bridge/Cargo.toml
```

Expected: 컴파일 FAIL — `unresolved import hangulji_bridge::translator` (모듈 미존재).

- [ ] **Step 4: translator 구현** (`windows/bridge/src/translator.rs`)

```rust
//! 순수(플랫폼 무관) 테이블 automaton — 1단계 Google IME 로마자 테이블과 같은 의미론.
//! (input, output, next_input) 규칙 집합에 대해 키를 pending에 누적하며:
//!   1. pending이 어떤 input의 진접두사이면 → 대기 (경계(flush)에서는 정확 일치 우선 확정)
//!   2. pending이 정확 일치하고 확장 불가면 → output 방출, pending = next_input
//!   3. 둘 다 아니면 → 최장 정확 접두사를 확정해 분리, 그것도 없으면 첫 키를 raw로 방출
//! 같은 코드가 두 규칙 집합에 쓰인다:
//!   - KEY_TO_ROMAJI: 2벌식 키 → 로마자 (브리지 본체 — 받침 대기·재해석이 여기서 해결됨)
//!   - ROMAJI_TO_KANA: 로마자 → 가나 (테스트 오라클 — 접두사 자유 표라 대기는 모라 중간뿐)
//! raw 방출(규칙 3 말단)은 매핑 불가 키(단독 모음 등)의 결정적 열화 경로다 — 1단계에서
//! Google IME에 라틴 문자가 그대로 남는 것과 동급이며 README 한계 절에 문서화한다.

use std::collections::{HashMap, HashSet};

pub struct Automaton {
    rules: HashMap<&'static str, (&'static str, &'static str)>,
    prefixes: HashSet<String>, // 모든 input의 진접두사 집합
    pending: String,
}

impl Automaton {
    pub fn new(table: &'static [(&'static str, &'static str, &'static str)]) -> Self {
        let mut rules = HashMap::new();
        let mut prefixes = HashSet::new();
        for &(input, output, next) in table {
            let dup = rules.insert(input, (output, next));
            assert!(dup.is_none(), "중복 input: {input}");
            let chars: Vec<char> = input.chars().collect();
            for i in 1..chars.len() {
                prefixes.insert(chars[..i].iter().collect());
            }
        }
        Automaton { rules, prefixes, pending: String::new() }
    }

    /// 키 1개 소비 — 지금 확정되는 출력(대기 중이면 빈 문자열)을 돌려준다.
    pub fn push(&mut self, ch: char) -> String {
        self.pending.push(ch);
        self.resolve(false)
    }

    /// 커밋 경계(스페이스·엔터·토글 등): pending 전부를 정확 일치 우선으로 해소.
    pub fn flush(&mut self) -> String {
        self.resolve(true)
    }

    /// 백스페이스: 아직 방출되지 않은 pending의 마지막 키 1개 제거. 비었으면 false.
    pub fn pop_pending(&mut self) -> bool {
        self.pending.pop().is_some()
    }

    pub fn pending_len(&self) -> usize {
        self.pending.chars().count()
    }

    fn resolve(&mut self, at_boundary: bool) -> String {
        let mut out = String::new();
        loop {
            if self.pending.is_empty() {
                return out;
            }
            let has_ext = self.prefixes.contains(&self.pending);
            if let Some(&(output, next)) = self.rules.get(self.pending.as_str()) {
                if !has_ext || at_boundary {
                    out.push_str(output);
                    self.pending = next.to_string();
                    continue;
                }
            }
            if has_ext && !at_boundary {
                return out; // 더 긴 항목 가능성 — 대기
            }
            // 정확 일치 없음 → 최장 정확 접두사 분리, 그것도 없으면 첫 키 raw 방출
            let chars: Vec<char> = self.pending.chars().collect();
            let mut split = 0;
            for len in (1..=chars.len()).rev() {
                let p: String = chars[..len].iter().collect();
                if self.rules.contains_key(p.as_str()) {
                    split = len;
                    break;
                }
            }
            if split == 0 {
                out.push(chars[0]);
                self.pending = chars[1..].iter().collect();
            } else {
                let p: String = chars[..split].iter().collect();
                let &(output, next) = self.rules.get(p.as_str()).unwrap();
                out.push_str(output);
                let rest: String = chars[split..].iter().collect();
                self.pending = format!("{next}{rest}");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Automaton;
    use crate::table_generated::KEY_TO_ROMAJI;

    fn run(keys: &str) -> String {
        let mut a = Automaton::new(KEY_TO_ROMAJI);
        let mut out = String::new();
        for ch in keys.chars() {
            out.push_str(&a.push(ch));
        }
        out.push_str(&a.flush());
        out
    }

    #[test]
    fn emits_msime_romaji() {
        assert_eq!(run("xhdnzydnsldlzlaktm"), "toukyouniikimasu"); // 토우쿄우니이키마스
        assert_eq!(run("rksdl"), "ganni");             // ん은 항상 nn — n 모호성 원천 차단
        assert_eq!(run("tktvhfh"), "saxtuporo");       // っ은 항상 xtu — 자음 중복 표기 불사용
        assert_eq!(run("ghtRkdlehdn"), "hoxtukaidou"); // 홋(ㅅ받침 연쇄) + 까(Shift+R 별칭)
        assert_eq!(run("fk-aps"), "ra-menn");          // 장음 '-' 는 그대로 통과
    }

    #[test]
    fn waits_while_prefix_open() {
        let mut a = Automaton::new(KEY_TO_ROMAJI);
        assert_eq!(a.push('g'), "");   // ㅎ — 모음 대기
        assert_eq!(a.push('h'), "");   // ㅗ — ghk(화=ふぁ) 가능성 대기
        assert_eq!(a.push('k'), "fa"); // 화 확정
        assert_eq!(a.pending_len(), 0);
    }

    #[test]
    fn pop_pending_cancels_unemitted_key() {
        let mut a = Automaton::new(KEY_TO_ROMAJI);
        assert_eq!(a.push('z'), "");
        assert!(a.pop_pending());
        assert_eq!(a.push('g'), "");
        assert_eq!(a.push('k'), "ha"); // z 취소 후 gk = 하
        assert!(!a.pop_pending()); // pending 비어 있음
    }

    #[test]
    fn unmappable_degrades_deterministically() {
        // 별(quf): 몸통 ㅂ+ㅕ 미배정 → q는 받침 っ로, u·f는 raw로 샌다.
        // 1단계의 "っuf"와 동급의 결정적 열화 — README 한계 절에 문서화되는 동작의 고정.
        assert_eq!(run("quf"), "xtuuf");
    }
}
```

`windows/bridge/src/lib.rs`에 모듈 추가 (전체 교체):

```rust
//! 한글지 Windows 브리지 — 순수(플랫폼 무관) 변환 로직.
//! Windows 셸(훅·주입)은 bin 크레이트(main.rs + hook.rs)에만 있다.

pub mod table_generated;
pub mod translator;
```

- [ ] **Step 5: 전건 통과 확인**

```bash
cargo test --manifest-path windows/bridge/Cargo.toml
```

Expected: lib 유닛 4건 + conformance 통합 3건 = 7 passed. `kana_fixtures_roundtrip_through_msime_romaji`가 fullyMapped 44건 전건 검증(최소치 38 통과). 실패 시: 픽스처 kana가 진실 — 생성기의 kanaToRomaji 철자·automaton 의미론을 의심하고 수정. **mapping.tsv·fixtures·1단계 산출물 수정 금지.** 해결 불가면 BLOCKED 보고.

- [ ] **Step 6: Commit** — 트레일러 금지(Co-Authored-By 절대 불가 — SP4에서 2회 위반된 규칙). `git log -1 --format=%B`로 확인.

```bash
git add windows/bridge
git commit -m "feat(windows-bridge): translator automaton + 픽스처 conformance (로마자 오라클)"
```

---

### Task 3: Windows 훅 셸 (cfg(windows), 컴파일 검증만) + 브리지 README

**Files:**
- Create: `windows/bridge/src/hook.rs`, `windows/bridge/README.md`
- Modify: `windows/bridge/Cargo.toml`(windows 의존성), `windows/bridge/src/main.rs`(본문)

**Interfaces:**
- Consumes: `hangulji_bridge::translator::Automaton`(push/flush/pop_pending/pending_len — Task 2 시그니처 그대로), `table_generated::KEY_TO_ROMAJI`
- Produces: `hook::run() -> windows::core::Result<()>`(훅 설치 + 메시지 루프, main이 호출). 이 태스크의 검증은 **컴파일 체크까지** — 실행 검증은 Global Constraints대로 보류.

- [ ] **Step 1: Cargo.toml에 windows 의존성 추가** (cfg(windows) 한정 — macOS `cargo test`에는 컴파일조차 되지 않음):

```toml
[target.'cfg(windows)'.dependencies]
windows = { version = "0.61", features = [
    "Win32_Foundation",
    "Win32_UI_WindowsAndMessaging",
    "Win32_UI_Input_KeyboardAndMouse",
] }
```

- [ ] **Step 2: hook.rs 작성** (`windows/bridge/src/hook.rs`)

주의: 아래 코드는 windows crate 0.61 API 기준이다. Step 4의 `cargo check --target x86_64-pc-windows-msvc`에서 시그니처 불일치가 나오면(예: `Option<HHOOK>` 여부, BOOL 변환) **이 파일의 호출부만** 컴파일 에러에 맞춰 수정한다 — 설계(주석의 원칙 4개)는 불변.

```rust
//! Windows 셸: WH_KEYBOARD_LL 훅 + SendInput 로마자 주입.
//! 이 모듈의 책임 범위는 CI 컴파일 검증까지 — 실기기 실행 검증은 보류(설계 §5.4·§8).
//!
//! 원칙 (리서치 확정 사항):
//! 1. 훅 프로시저는 트리비얼해야 한다(LowLevelHooksTimeout 초과 시 OS가 훅 제거):
//!    분류 + 채널 송신 + 삼킴 판정만. 변환·SendInput은 워커 스레드.
//! 2. LLKHF_INJECTED 이벤트는 무조건 즉시 통과 — 자기 주입 재귀 방지 (첫 검사).
//! 3. KEYEVENTF_UNICODE 금지: VK 키만 주입해야 MS-IME 로마자 automaton이 소비한다.
//! 4. IME 상태 추적 대신 자체 토글(Ctrl+Space) — 보안 데스크톱·관리자 창 도달 불가는
//!    구조적 한계로 README에 문서화.

use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::OnceLock;

use hangulji_bridge::table_generated::KEY_TO_ROMAJI;
use hangulji_bridge::translator::Automaton;

use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP,
    VIRTUAL_KEY, VK_BACK, VK_CONTROL, VK_MENU, VK_OEM_MINUS, VK_SHIFT, VK_SPACE,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, TranslateMessage,
    KBDLLHOOKSTRUCT, LLKHF_INJECTED, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_SYSKEYDOWN,
};

enum Msg {
    /// 한글지 키 — translator로
    Key(char),
    /// 비매핑 키가 pending 중 도착 — flush 후 원 키를 재주입해 순서 보장
    /// (원 키를 통과시키면 flush 로마자보다 먼저 도착해 IME 변환 순서가 역전된다)
    Boundary(u16),
    /// 백스페이스 — 화면 미표시 pending 1키 취소
    BackspacePending,
}

static ENABLED: AtomicBool = AtomicBool::new(true);
// 훅 스레드의 동기 삼킴 판정용으로 워커가 갱신하는 pending 길이 사본.
// 채널에 미처리 키가 있는 짧은 순간 구식 값일 수 있다(빠른 타이핑 시) — README 한계 문서화.
static PENDING_LEN: AtomicUsize = AtomicUsize::new(0);
static TX: OnceLock<Sender<Msg>> = OnceLock::new();

pub fn run() -> windows::core::Result<()> {
    let (tx, rx) = channel::<Msg>();
    TX.set(tx).expect("run()은 1회만 호출");

    // 워커: translator 상태 소유. 훅 프로시저는 여기에 채널로만 접근한다.
    std::thread::spawn(move || {
        let mut translator = Automaton::new(KEY_TO_ROMAJI);
        for msg in rx {
            match msg {
                Msg::Key(ch) => {
                    let romaji = translator.push(ch);
                    PENDING_LEN.store(translator.pending_len(), Ordering::SeqCst);
                    send_romaji(&romaji);
                }
                Msg::Boundary(vk) => {
                    let romaji = translator.flush();
                    PENDING_LEN.store(0, Ordering::SeqCst);
                    send_romaji(&romaji);
                    send_vk(VIRTUAL_KEY(vk)); // 삼킨 원 키 재주입 (LLKHF_INJECTED로 통과됨)
                }
                Msg::BackspacePending => {
                    translator.pop_pending();
                    PENDING_LEN.store(translator.pending_len(), Ordering::SeqCst);
                }
            }
        }
    });

    unsafe {
        let _hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(hook_proc), None, 0)?;
        println!("한글지 브리지 동작 중 — Ctrl+Space 토글, 이 창에서 Ctrl+C 종료");
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            let _ = DispatchMessageW(&msg);
        }
    }
    Ok(())
}

fn key_down(vk: VIRTUAL_KEY) -> bool {
    unsafe { (GetAsyncKeyState(vk.0 as i32) as u16) & 0x8000 != 0 }
}

/// vkCode(+Shift) → 한글지 키 문자. SPEC §1.1 구현: 명시 배정된 대문자(Q W E R T O P)만
/// 대문자 유지, 그 외 Shift+알파벳은 소문자로 폴백. Shift+'-'(_)는 비매핑.
/// O·P 대문자(ㅒ·ㅖ)는 배정은 있으나 TSV에 몸통이 없어 raw로 새는 열화 경로다(README 문서화).
fn map_char(vk: u32, shift: bool) -> Option<char> {
    if (0x41..=0x5A).contains(&vk) {
        let upper = (vk as u8) as char; // VK_A..VK_Z == 'A'..'Z'
        if shift && matches!(upper, 'Q' | 'W' | 'E' | 'R' | 'T' | 'O' | 'P') {
            Some(upper)
        } else {
            Some(upper.to_ascii_lowercase())
        }
    } else if vk == VK_OEM_MINUS.0 as u32 && !shift {
        Some('-')
    } else {
        None
    }
}

unsafe extern "system" fn hook_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code < 0 {
        return CallNextHookEx(None, code, wparam, lparam);
    }
    let kb = &*(lparam.0 as *const KBDLLHOOKSTRUCT);

    // 1. 자기 주입 재귀 방지 — 최우선
    if kb.flags.contains(LLKHF_INJECTED) {
        return CallNextHookEx(None, code, wparam, lparam);
    }

    let is_down =
        wparam.0 as u32 == WM_KEYDOWN || wparam.0 as u32 == WM_SYSKEYDOWN;
    let ctrl = key_down(VK_CONTROL);

    // 2. 토글: Ctrl+Space (설계 §5.4 — IME 상태 추적 대신 자체 토글)
    if is_down && ctrl && kb.vkCode == VK_SPACE.0 as u32 {
        let was_enabled = ENABLED.fetch_xor(true, Ordering::SeqCst);
        println!("한글지 브리지: {}", if was_enabled { "꺼짐" } else { "켜짐" });
        return LRESULT(1);
    }

    // 3. 꺼짐 상태·단축키(Ctrl/Alt 동반)는 건드리지 않는다 (Ctrl+C 등 보존)
    if !ENABLED.load(Ordering::SeqCst) || ctrl || key_down(VK_MENU) {
        return CallNextHookEx(None, code, wparam, lparam);
    }

    // 4. 한글지 키 → 삼키고 워커로 (down/up 모두 삼켜 짝 없는 keyup 방지)
    if let Some(ch) = map_char(kb.vkCode, key_down(VK_SHIFT)) {
        if is_down {
            let _ = TX.get().unwrap().send(Msg::Key(ch));
        }
        return LRESULT(1);
    }

    // 5. 비매핑 키가 pending 중 도착 (keydown만 개입 — keyup은 통과)
    if is_down && PENDING_LEN.load(Ordering::SeqCst) > 0 {
        if kb.vkCode == VK_BACK.0 as u32 {
            // pending 키는 화면에 없으므로 백스페이스를 앱까지 보내지 않는다
            let _ = TX.get().unwrap().send(Msg::BackspacePending);
            return LRESULT(1);
        }
        // 스페이스·엔터·숫자 등: flush 후 원 키 재주입 (순서 보장)
        let _ = TX.get().unwrap().send(Msg::Boundary(kb.vkCode as u16));
        return LRESULT(1);
    }

    CallNextHookEx(None, code, wparam, lparam)
}

fn char_to_vk(c: char) -> VIRTUAL_KEY {
    match c {
        'a'..='z' => VIRTUAL_KEY(c.to_ascii_uppercase() as u16), // VK_A..VK_Z == 'A'..'Z'
        '-' => VK_OEM_MINUS,
        _ => unreachable!("생성 테이블 출력은 [a-z-] 뿐 (gen-bridge-table이 보장)"),
    }
}

fn key_event(vk: VIRTUAL_KEY, up: bool) -> INPUT {
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: 0,
                dwFlags: if up { KEYEVENTF_KEYUP } else { Default::default() },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

/// 로마자 문자열을 VK 키스트로크로 주입. KEYEVENTF_UNICODE 금지(Global Constraints).
/// 물리 Shift가 눌린 채(예: ㄲ=Shift+R 직후 tR 연쇄) 소문자 로마자를 주입하면 대문자가
/// 되어 IME 조합이 깨지므로, 주입 전 Shift-up / 주입 후 Shift-down으로 물리 상태를
/// 감쌌다가 복원한다 — 실기기 검증 보류 항목(README).
fn send_romaji(romaji: &str) {
    if romaji.is_empty() {
        return;
    }
    let mut inputs: Vec<INPUT> = Vec::with_capacity(romaji.len() * 2 + 2);
    let shift_held = key_down(VK_SHIFT);
    if shift_held {
        inputs.push(key_event(VK_SHIFT, true)); // 일시 해제
    }
    for c in romaji.chars() {
        let vk = char_to_vk(c);
        inputs.push(key_event(vk, false));
        inputs.push(key_event(vk, true));
    }
    if shift_held {
        inputs.push(key_event(VK_SHIFT, false)); // 물리 상태 복원
    }
    unsafe {
        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
}

fn send_vk(vk: VIRTUAL_KEY) {
    let inputs = [key_event(vk, false), key_event(vk, true)];
    unsafe {
        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
}
```

- [ ] **Step 3: main.rs 본문 교체** (`windows/bridge/src/main.rs` 전체):

```rust
#[cfg(windows)]
mod hook;

#[cfg(windows)]
fn main() {
    println!("한글지 브리지 — 2벌식 키를 MS-IME 로마자로 변환해 주입합니다.");
    println!("사전 조건: 일본어 IME(MS-IME) 활성 + ひらがな 모드 + 로마자 입력 설정");
    println!("토글: Ctrl+Space / 종료: 이 창에서 Ctrl+C");
    println!("한계: 관리자 권한 창·보안 데스크톱에는 주입되지 않습니다 (README.md 참고)");
    if let Err(e) = hook::run() {
        eprintln!("키보드 훅 설치 실패: {e}");
        std::process::exit(1);
    }
}

#[cfg(not(windows))]
fn main() {
    eprintln!("hangulji-bridge는 Windows 전용 실행 파일입니다.");
    eprintln!("변환 로직 테스트는 어느 OS에서나: cargo test --manifest-path windows/bridge/Cargo.toml");
    std::process::exit(2);
}
```

- [ ] **Step 4: 크로스 컴파일 체크 (macOS에서 — 링크 없는 타입 검사)**

```bash
rustup target add x86_64-pc-windows-msvc
cargo check --manifest-path windows/bridge/Cargo.toml --target x86_64-pc-windows-msvc
```

Expected: 성공(경고 0). windows crate 0.61의 실제 시그니처와 다른 부분이 있으면 여기서 컴파일 에러로 드러난다 — hook.rs 호출부만 에러에 맞춰 수정(재귀 방지·트리비얼 훅·VK 주입·토글이라는 설계는 불변). 최종 증명은 Task 4의 windows-2022 CI 빌드.

- [ ] **Step 5: macOS 회귀 — 순수 모듈 무영향 확인**

```bash
cargo test --manifest-path windows/bridge/Cargo.toml
cargo build --manifest-path windows/bridge/Cargo.toml
```

Expected: 7 passed 유지, macOS 빌드에 windows 의존성 미포함(cfg 타깃 한정이므로 다운로드조차 안 함).

- [ ] **Step 6: 브리지 README 작성** (`windows/bridge/README.md`) — 다음 내용 전부 포함(한국어):

```markdown
# 한글지 브리지 (Windows 2단계)

## 개요

1단계([windows/README.md](../README.md))가 Google 일본어 입력의 커스텀 로마자 테이블이라면,
2단계 브리지는 **시스템 기본 MS-IME를 테이블 교체 없이 그대로** 쓰는 상주 프로그램이다.
`hangulji-bridge.exe`가 2벌식 키입력을 가로채 MS-IME 로마자 키스트림으로 재주입하고,
가나 조합·한자 변환·후보 선택은 전부 MS-IME가 담당한다.

변환 표는 `spec/mapping.tsv`에서 생성되며(§ 재생성), 로마자 철자는 훈령식 우선 +
MS-IME 확장(si·ti·tu·zi·di·du / thi·dhi·twu·dwu / fa·fi·fe·fo / wi·we / ん=nn / っ=xtu)이다.

## 빌드

    cargo build --release
    # 산출물: target/release/hangulji-bridge.exe

GitHub Actions(windows-bridge 워크플로)가 같은 명령으로 빌드한 서명 없는 exe를
아티팩트로 올린다. 서명이 없으므로 실행 시 SmartScreen 경고가 뜰 수 있다.

## 사용

1. Windows 일본어 IME(MS-IME)를 켜고 ひらがな 모드 + 로마자 입력으로 둔다
2. `hangulji-bridge.exe` 실행 (콘솔 창 유지)
3. 아무 앱에서 2벌식 위치로 타이핑: xhdnzydn(토우쿄우) → とうきょう → Space → 東京
4. **Ctrl+Space**로 브리지 켬/끔 토글 (영문 입력이 필요할 때 끈다)
5. 종료는 콘솔 창에서 Ctrl+C

## 한계 (정직하게)

- **실기기 미검증**: Windows 기기가 없어 실행 검증을 못 했다. CI의 exe 빌드 +
  변환 로직 conformance(픽스처 44케이스, 로마자→가나 오라클 왕복)까지가 현재
  책임 범위다(설계 §5.4·§7 SP5). MS-IME가 이 로마자 철자 전부를 기본 설정에서
  수용하는지, Shift 상태 복원 주입이 실제로 동작하는지가 실기기 1순위 확인 항목
- **관리자 권한 창·보안 데스크톱(UAC·로그인 화면) 주입 불가** — 저수준 훅의 구조적 한계
- **훅 타임아웃**: 시스템이 느릴 때 OS가 훅을 제거할 수 있다(LowLevelHooksTimeout).
  입력이 원래 키로 돌아가면 브리지를 재실행한다
- **매핑 불가 음절은 로마자·라틴 키가 그대로 샌다**: 별(quf) → っうf 상당 (1단계의
  "っuf"와 동급). 오타를 바로 알아챌 수 있는 동작으로 활용
- **백스페이스**: 아직 화면에 나가지 않은 대기 키(pending)만 브리지가 취소하고,
  화면에 이미 조합된 가나의 삭제는 MS-IME 기본 동작이다. 빠른 타이핑 중에는
  대기 판정이 한 키 늦을 수 있다
- Ctrl/Alt 동반 키(단축키)는 변환하지 않고 통과시킨다

## 테스트 (어느 OS에서나)

    cargo test
    # translator 유닛 4건 + spec/fixtures conformance 3건
    # conformance는 spec/fixtures/kana.json 전 케이스를 순회한다.
    # composition.json은 무패닉 스모크만 — 브리지에는 자모 음절 조합기가 없어
    # 한글 음절 목록 검증이 구조적으로 불가하고(호스트 IME에 로마자를 흘리는 구조),
    # 받침 재해석 의미론은 가나 레벨 trace 테스트로 고정한다 (1단계 선례와 동일)

## 재생성

매핑 규칙 변경 후 (저장소 루트에서):

    swift spec/generators/gen-bridge-table.swift

산출물 `src/table_generated.rs`는 수기 수정 금지 — core CI가 최신성(재생성 후 diff 0)을 검사한다.
```

- [ ] **Step 7: Commit** — 트레일러 금지(Co-Authored-By 절대 불가). `git log -1 --format=%B` 확인.

```bash
git add windows/bridge
git commit -m "feat(windows-bridge): WH_KEYBOARD_LL 훅 셸 + 사용 가이드"
```

---

### Task 4: windows-bridge CI + 루트 README + 최종 회귀

**Files:**
- Create: `.github/workflows/windows-bridge.yml`
- Modify: 루트 `README.md`(Windows 섹션·개발 명령·구조 트리·로드맵)

**Interfaces:**
- Consumes: `windows/bridge/` 크레이트 전체(Task 1–3), `windows/bridge/Cargo.lock`(캐시 키)
- Produces: SP5 완료 정의의 증거 — windows-2022에서 `cargo test`(픽스처 테스트) + `cargo build --release`(exe) 그린, exe 아티팩트

- [ ] **Step 1: 워크플로 작성** (`.github/workflows/windows-bridge.yml`)

```yaml
name: windows-bridge
on:
  push:
    branches: [main]
  pull_request:

jobs:
  bridge:
    runs-on: windows-2022
    defaults:
      run:
        working-directory: windows/bridge
    steps:
      - uses: actions/checkout@v4
      - name: Rust 툴체인 확인 (러너 프리인스톨 stable-x86_64-pc-windows-msvc)
        run: |
          rustup default stable
          rustc --version
          cargo --version
      - uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            windows/bridge/target
          key: cargo-${{ runner.os }}-${{ hashFiles('windows/bridge/Cargo.lock') }}
      - name: 변환 로직 픽스처 테스트 (SP5 완료 정의 후반 — translator + conformance)
        run: cargo test --release
      - name: 브리지 exe 빌드 (SP5 완료 정의 전반)
        run: cargo build --release
      - name: exe 아티팩트 업로드 (서명 없음)
        uses: actions/upload-artifact@v4
        with:
          name: hangulji-bridge-exe
          path: windows/bridge/target/release/hangulji-bridge.exe
```

주: table_generated.rs 최신성 검사는 이 워크플로가 아니라 core.yml(macOS — Swift 필요)에 있다(Task 1 Step 5). 설계 §6의 "windows.yml"은 이 파일명이 담당한다.

- [ ] **Step 2: YAML 문법 검증**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/windows-bridge.yml'); puts 'OK'"
ruby -ryaml -e "YAML.load_file('.github/workflows/core.yml'); puts 'OK'"
```

Expected: OK 2회.

- [ ] **Step 3: 루트 README 갱신** — 다음 3곳 + 개발 명령 1곳:

1. **설치 → Windows 섹션**: 기존 두 문단("**코드 제로** — ..." / "상세한 설치 방법은 ...") 뒤에 추가:

```markdown
**설치형 브리지(2단계)** — 상주 프로그램(`hangulji-bridge.exe`)이 2벌식 키를 로마자로
변환해 MS-IME에 주입합니다. 테이블 교체 없이 시스템 기본 일본어 IME를 그대로 씁니다.
빌드·사용법·한계는 [windows/bridge/README.md](windows/bridge/README.md)를 참고하세요
(CI 빌드 + 변환 로직 conformance까지 검증됨, 실기기 실행 검증은 보류).
```

2. **개발 구조 트리**: `windows/` 줄을 다음으로 교체:

```
windows/                        1단계: Google IME 커스텀 테이블 / 2단계: 키 변환 브리지 (bridge/, Rust)
```

3. **개발 명령 블록**: `swift test --package-path core-swift` 줄 아래에 추가:

```bash
cargo test --manifest-path windows/bridge/Cargo.toml   # Windows 브리지 변환 로직 (OS 무관)
```

4. **로드맵**: Windows 줄을 다음으로 교체:

```markdown
- **Windows:** 1단계 완료(Google 일본어 입력 커스텀 테이블) + 2단계 완료(키 변환 브리지 — CI에서 exe 빌드·픽스처 conformance 검증). 실기기 실행 검증은 Windows 기기 확보 시.
```

- [ ] **Step 4: 최종 회귀 + 범위 감사**

```bash
cargo test --manifest-path windows/bridge/Cargo.toml                 # 7 passed
swift spec/generators/gen-bridge-table.swift && git diff --stat -- windows  # 멱등 (diff 없음)
swift test --package-path core-swift                                  # 기존 57개 무영향
git status --short   # 변경이 windows/bridge, spec/generators/gen-bridge-table.swift, .github, README.md 에만 있는지
```

- [ ] **Step 5: Commit** — 트레일러 금지(Co-Authored-By 절대 불가 — 최종 커밋에서도 예외 없음). `git log -1 --format=%B` 확인.

```bash
git add .github/workflows/windows-bridge.yml README.md
git commit -m "ci(windows-bridge): windows-2022 빌드·테스트 워크플로 + README 갱신"
```

---

## Self-Review 결과

1. **스펙 커버리지**: §5.4 2단계 전 항목 — Rust WH_KEYBOARD_LL 훅(Task 3), LLKHF_INJECTED 재귀 방지(hook_proc 검사 1), 훅 타임아웃 대응(트리비얼 훅 + 워커 스레드), 관리자 창·보안 데스크톱 한계 문서화(README 한계 절), 자체 토글 키(Ctrl+Space), CI windows-2022 빌드·서명 없는 exe 산출(Task 4 아티팩트). §6 windows 워크플로(windows-bridge.yml). §7 SP5 완료 정의 = Task 4의 두 CI 스텝과 1:1 대응, 실행 검증 보류는 README·로드맵 양쪽에 명시(§8 리스크 대응). SPEC §6 러너 의무는 kana.json 전 케이스 순회 + composition.json 스모크·trace로 이행하며 음절 검증 불가 사유를 문서화(1단계 MozcTableTests 선례와 동일한 범위 한정).
2. **플레이스홀더**: 없음 — 생성기·translator·conformance·hook·CI·README 전부 실코드/실문안. "나중에"·"적절히" 류 표현 없음.
3. **검산 (본 계획 작성 시 시뮬레이션으로 실검증함)**: KEY_TO_ROMAJI 300항목(body 159 + final 단독 7 + 연쇄 7×19=133 + 기호 1), ROMAJI_TO_KANA 116모라(TSV 셀 고유값 115 + ー), kanaToRomaji가 TSV 전 셀 커버(미커버 0), 철자 전단사·접두사 자유 성립, **kana.json fullyMapped 44건 전건이 translator→오라클 왕복으로 픽스처와 일치(불일치 0)**. 유닛 테스트 기대값도 동일 시뮬레이션 산출: toukyouniikimasu·ganni·saxtuporo·hoxtukaidou·ra-menn·xtuuf, trace 가나 がに·がんい·がん·さっぽ·かた·お.
4. **타입/경로 일관성**: Automaton 시그니처(push/flush/pop_pending/pending_len)가 Task 2 정의 ↔ Task 3 hook.rs 사용처 일치. `table_generated`(언더스코어) 모듈명 = 생성기 출력 경로 = lib.rs 선언 일치. 픽스처 경로 `CARGO_MANIFEST_DIR/../../spec/fixtures`(windows/bridge → 루트 2단계 상향) 일치. 크레이트명 hangulji-bridge/lib hangulji_bridge, CI 아티팩트 경로 `windows/bridge/target/release/hangulji-bridge.exe` 일치. conformance 최소치 38 = SPEC §6.1 명시값(개수 하드코딩 금지 준수).
