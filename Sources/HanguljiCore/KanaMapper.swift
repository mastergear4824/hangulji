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

    /// 스펙 §4.1(기본표) + §4.2(별칭) + §4.3(확장) 전체.
    /// 행(초성)별로 [모음: 가나] — 스펙 표와 1:1 대응하도록 유지할 것.
    private static let rows: [(Consonant, [Vowel: String])] = [
        (.ng, [.a: "あ", .i: "い", .u: "う", .e: "え", .o: "お",
               .ya: "や", .yu: "ゆ", .yo: "よ", .wa: "わ", .wo: "を",
               .wi: "うぃ", .we: "うぇ"]),
        (.k,  [.a: "か", .i: "き", .u: "く", .e: "け", .o: "こ",
               .ya: "きゃ", .yu: "きゅ", .yo: "きょ", .eu: "く"]),
        (.gg, [.a: "か", .i: "き", .u: "く", .e: "け", .o: "こ",
               .ya: "きゃ", .yu: "きゅ", .yo: "きょ", .eu: "く"]),
        (.g,  [.a: "が", .i: "ぎ", .u: "ぐ", .e: "げ", .o: "ご",
               .ya: "ぎゃ", .yu: "ぎゅ", .yo: "ぎょ", .eu: "ぐ"]),
        (.s,  [.a: "さ", .i: "し", .eu: "す", .u: "す", .e: "せ", .o: "そ",
               .ya: "しゃ", .yu: "しゅ", .yo: "しょ"]),
        (.ss, [.a: "さ", .i: "し", .eu: "つ", .e: "せ", .o: "そ"]),  // 쓰=つ 예외
        (.j,  [.a: "ざ", .i: "じ", .eu: "ず", .u: "ず", .e: "ぜ", .o: "ぞ",
               .ya: "じゃ", .yu: "じゅ", .yo: "じょ"]),
        (.jj, [.a: "ちゃ", .i: "ち", .eu: "つ", .yu: "ちゅ", .yo: "ちょ"]),
        (.ch, [.a: "ちゃ", .ya: "ちゃ", .u: "ちゅ", .yu: "ちゅ", .o: "ちょ", .yo: "ちょ",
               .i: "ち", .eu: "つ"]),
        (.t,  [.a: "た", .e: "て", .o: "と", .i: "てぃ", .u: "とぅ", .eu: "とぅ"]),
        (.dd, [.a: "た", .e: "て", .o: "と", .i: "ぢ", .eu: "づ"]),
        (.d,  [.a: "だ", .e: "で", .o: "ど", .i: "でぃ", .u: "どぅ", .eu: "どぅ"]),
        (.h,  [.a: "は", .i: "ひ", .u: "ふ", .eu: "ふ", .e: "へ", .o: "ほ",
               .ya: "ひゃ", .yu: "ひゅ", .yo: "ひょ",
               .wa: "ふぁ", .wi: "ふぃ", .we: "ふぇ", .wo: "ふぉ"]),
        (.b,  [.a: "ば", .i: "び", .u: "ぶ", .eu: "ぶ", .e: "べ", .o: "ぼ",
               .ya: "びゃ", .yu: "びゅ", .yo: "びょ"]),
        (.bb, [.a: "ぱ", .i: "ぴ", .u: "ぷ", .eu: "ぷ", .e: "ぺ", .o: "ぽ",
               .ya: "ぴゃ", .yu: "ぴゅ", .yo: "ぴょ"]),
        (.p,  [.a: "ぱ", .i: "ぴ", .u: "ぷ", .eu: "ぷ", .e: "ぺ", .o: "ぽ",
               .ya: "ぴゃ", .yu: "ぴゅ", .yo: "ぴょ"]),
        (.n,  [.a: "な", .i: "に", .u: "ぬ", .eu: "ぬ", .e: "ね", .o: "の",
               .ya: "にゃ", .yu: "にゅ", .yo: "にょ"]),
        (.m,  [.a: "ま", .i: "み", .u: "む", .eu: "む", .e: "め", .o: "も",
               .ya: "みゃ", .yu: "みゅ", .yo: "みょ"]),
        (.r,  [.a: "ら", .i: "り", .u: "る", .eu: "る", .e: "れ", .o: "ろ",
               .ya: "りゃ", .yu: "りゅ", .yo: "りょ"]),
    ]

    private static let bodyTable: [BodyKey: String] = {
        var table: [BodyKey: String] = [:]
        for (initial, vowels) in rows {
            for (vowel, kana) in vowels {
                table[BodyKey(initial: initial, vowel: vowel)] = kana
            }
        }
        return table
    }()

    /// 받침 → っ/ん (스펙 §4.1–4.2). 그 외 받침은 매핑 불가.
    private static let finalTable: [Consonant: String] = [
        .n: "ん", .ng: "ん", .m: "ん",
        .s: "っ", .g: "っ", .b: "っ", .d: "っ",
    ]

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
