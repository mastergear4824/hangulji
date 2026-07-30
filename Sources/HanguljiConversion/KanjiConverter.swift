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

        var seen = Set<String>()
        var list: [String] = []
        for text in results.mainResults.map(\.text) + [reading, reading.toKatakana()] {
            if seen.insert(text).inserted { list.append(text) }
        }
        return Array(list.prefix(max + 2))  // 한자 max개 + 가나/가타카나 폴백
    }
}
