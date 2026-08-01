#!/usr/bin/env swift
// spec/mapping.tsv → android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt
// 사용: swift spec/generators/gen-kotlin.swift (저장소 루트에서)
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let tsvURL = root.appendingPathComponent("spec/mapping.tsv")
let outURL = root.appendingPathComponent(
    "android/app/src/main/kotlin/com/mastergear/hangulji/core/KanaTable.kt")

guard let tsv = try? String(contentsOf: tsvURL, encoding: .utf8) else {
    fatalError("spec/mapping.tsv 를 읽을 수 없음 — 저장소 루트에서 실행했는가?")
}

// 자모 문자 → Kotlin enum 케이스 이름 (Jamo.kt의 Consonant/Vowel 선언과 반드시 일치)
let consonantNames: [String: String] = [
    "ㄱ": "G", "ㄲ": "GG", "ㄴ": "N", "ㄷ": "D", "ㄸ": "DD", "ㄹ": "R", "ㅁ": "M",
    "ㅂ": "B", "ㅃ": "BB", "ㅅ": "S", "ㅆ": "SS", "ㅇ": "NG", "ㅈ": "J", "ㅉ": "JJ",
    "ㅊ": "CH", "ㅋ": "K", "ㅌ": "T", "ㅍ": "P", "ㅎ": "H",
]
let vowelNames: [String: String] = [
    "ㅏ": "A", "ㅐ": "AE", "ㅑ": "YA", "ㅒ": "YAE", "ㅓ": "EO", "ㅔ": "E",
    "ㅕ": "YEO", "ㅖ": "YE", "ㅗ": "O", "ㅘ": "WA", "ㅙ": "WAE", "ㅚ": "OE",
    "ㅛ": "YO", "ㅜ": "U", "ㅝ": "WO", "ㅞ": "WE", "ㅟ": "WI", "ㅠ": "YU",
    "ㅡ": "EU", "ㅢ": "UI", "ㅣ": "I",
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
        bodyLines.append("        Triple(Consonant.\(ci), Vowel.\(vi), \"\(cols[3])\"),")
    case "final":
        guard let ci = consonantNames[cols[1]] else { fatalError("알 수 없는 자모: \(line)") }
        finalLines.append("        Consonant.\(ci) to \"\(cols[3])\",")
    default:
        fatalError("알 수 없는 kind: \(line)")
    }
}

let output = """
// KanaTable.kt
// spec/mapping.tsv 에서 생성됨 — 수기 수정 금지.
// 재생성: swift spec/generators/gen-kotlin.swift (저장소 루트에서)
package com.mastergear.hangulji.core

object KanaTable {
    val body: List<Triple<Consonant, Vowel, String>> = listOf(
\(bodyLines.joined(separator: "\n"))
    )

    val finals: List<Pair<Consonant, String>> = listOf(
\(finalLines.joined(separator: "\n"))
    )
}

"""
try! output.write(to: outURL, atomically: true, encoding: .utf8)
print("wrote \(outURL.path): body \(bodyLines.count), finals \(finalLines.count)")
