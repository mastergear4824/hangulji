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
