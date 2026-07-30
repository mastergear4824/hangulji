// Sources/HanguljiCore/Jamo.swift

/// 초성(choseong) 유니코드 정규 순서로 선언 — allCases 인덱스가 곧 초성 인덱스
public enum Consonant: Character, CaseIterable {
    case g = "ㄱ", gg = "ㄲ", n = "ㄴ", d = "ㄷ", dd = "ㄸ", r = "ㄹ", m = "ㅁ"
    case b = "ㅂ", bb = "ㅃ", s = "ㅅ", ss = "ㅆ", ng = "ㅇ", j = "ㅈ", jj = "ㅉ"
    case ch = "ㅊ", k = "ㅋ", t = "ㅌ", p = "ㅍ", h = "ㅎ"
}

/// 중성(jungseong) 유니코드 정규 순서로 선언
public enum Vowel: Character, CaseIterable {
    case a = "ㅏ", ae = "ㅐ", ya = "ㅑ", yae = "ㅒ", eo = "ㅓ", e = "ㅔ"
    case yeo = "ㅕ", ye = "ㅖ", o = "ㅗ", wa = "ㅘ", wae = "ㅙ", oe = "ㅚ"
    case yo = "ㅛ", u = "ㅜ", wo = "ㅝ", we = "ㅞ", wi = "ㅟ", yu = "ㅠ"
    case eu = "ㅡ", ui = "ㅢ", i = "ㅣ"
}

public enum Jamo: Equatable {
    case consonant(Consonant)
    case vowel(Vowel)
}

/// 2벌식 키맵: 라틴 문자(하드웨어 자판) → 자모
public enum Keymap {
    private static let table: [Character: Jamo] = [
        "q": .consonant(.b), "w": .consonant(.j), "e": .consonant(.d), "r": .consonant(.g),
        "t": .consonant(.s), "y": .vowel(.yo), "u": .vowel(.yeo), "i": .vowel(.ya),
        "o": .vowel(.ae), "p": .vowel(.e),
        "a": .consonant(.m), "s": .consonant(.n), "d": .consonant(.ng), "f": .consonant(.r),
        "g": .consonant(.h), "h": .vowel(.o), "j": .vowel(.eo), "k": .vowel(.a), "l": .vowel(.i),
        "z": .consonant(.k), "x": .consonant(.t), "c": .consonant(.ch), "v": .consonant(.p),
        "b": .vowel(.yu), "n": .vowel(.u), "m": .vowel(.eu),
        "Q": .consonant(.bb), "W": .consonant(.jj), "E": .consonant(.dd), "R": .consonant(.gg),
        "T": .consonant(.ss), "O": .vowel(.yae), "P": .vowel(.ye),
    ]

    public static func jamo(for ch: Character) -> Jamo? {
        if let j = table[ch] { return j }
        // 별도 배정 없는 대문자는 소문자와 동일 취급
        if ch.isUppercase, let lower = ch.lowercased().first { return table[lower] }
        return nil
    }
}
