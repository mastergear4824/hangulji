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
