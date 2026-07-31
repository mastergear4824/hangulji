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
