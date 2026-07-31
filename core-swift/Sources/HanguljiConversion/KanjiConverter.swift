// Sources/HanguljiConversion/KanjiConverter.swift
import Foundation
import HanguljiCore
import KanaKanjiConverterModuleWithDefaultDictionary

/// AzooKeyKanaKanjiConverter 어댑터.
/// pre-1.0 API 변동을 이 파일 한 곳에 가둔다 — 셸은 candidateList(for:max:)만 안다.
public final class KanjiConverter {
    private let converter = KanaKanjiConverter.withDefaultDictionary()

    public init() {}

    /// 한자 변환 후보 목록.
    ///
    /// 계약: 한자 후보를 최대 `max`개까지 담고, 그 뒤에 가나 원문(`reading`)과
    /// 가타카나(`reading.toKatakana()`) 폴백을 항상 보장 삽입한다. 전체 목록은
    /// 등장 순서를 유지하며 중복은 제거된다. 셸(Task 9)은 이 계약만 신뢰하면 된다.
    public func candidateList(for reading: String, max: Int = 9) -> [String] {
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)

        let scratchDirectory = FileManager.default.temporaryDirectory

        let options = ConvertRequestOptions(
            N_best: max,
            requireJapanesePrediction: false,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: scratchDirectory,
            sharedContainerURL: scratchDirectory,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: nil
        )
        let results = converter.requestCandidates(composing, options: options)

        // 한자 후보를 max개로 자른 뒤 가나/가타카나 폴백을 보장 삽입.
        // (mainResults는 N_best로 안 묶임 — 통짜 prefix는 폴백을 잘라낼 수 있다)
        var seen = Set<String>()
        var kanji: [String] = []
        for text in results.mainResults.map(\.text) {
            if seen.insert(text).inserted { kanji.append(text) }
        }
        var list = Array(kanji.prefix(max))
        for fallback in [reading, reading.toKatakana()] where !list.contains(fallback) {
            list.append(fallback)
        }
        return list
    }
}
