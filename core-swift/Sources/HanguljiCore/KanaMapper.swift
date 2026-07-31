// Sources/HanguljiCore/KanaMapper.swift

public struct MappedSyllable: Equatable {
    public let display: String
    public let isMapped: Bool

    public init(display: String, isMapped: Bool) {
        self.display = display
        self.isMapped = isMapped
    }
}

public enum KanaMapper {
    private struct BodyKey: Hashable {
        let initial: Consonant
        let vowel: Vowel
    }

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

    public static func map(_ syllables: [Syllable]) -> [MappedSyllable] {
        syllables.map { syllable in
            guard let initial = syllable.initial, let vowel = syllable.vowel,
                  let body = bodyTable[BodyKey(initial: initial, vowel: vowel)]
            else {
                return MappedSyllable(display: syllable.hangul, isMapped: false)
            }
            if let final = syllable.final {
                guard let finalKana = finalTable[final] else {
                    return MappedSyllable(display: syllable.hangul, isMapped: false)
                }
                return MappedSyllable(display: body + finalKana, isMapped: true)
            }
            return MappedSyllable(display: body, isMapped: true)
        }
    }
}
