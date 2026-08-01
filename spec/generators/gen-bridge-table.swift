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
