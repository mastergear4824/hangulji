// Sources/HanguljiCore/JamoComposer.swift

public struct Syllable: Equatable {
    public var initial: Consonant?
    public var vowel: Vowel?
    public var final: Consonant?

    public init(initial: Consonant? = nil, vowel: Vowel? = nil, final: Consonant? = nil) {
        self.initial = initial
        self.vowel = vowel
        self.final = final
    }

    /// 종성 인덱스 (유니코드 한글 조합 공식용). ㄸㅃㅉ은 종성 불가 → nil
    private static let jongseongIndex: [Consonant: Int] = [
        .g: 1, .gg: 2, .n: 4, .d: 7, .r: 8, .m: 16, .b: 17, .s: 19, .ss: 20,
        .ng: 21, .j: 22, .ch: 23, .k: 24, .t: 25, .p: 26, .h: 27,
    ]

    static func canBeFinal(_ c: Consonant) -> Bool { jongseongIndex[c] != nil }

    /// 화면 표시용 한글 (완성형 블록, 미완성이면 자모 낱자)
    public var hangul: String {
        if let i = initial, let v = vowel {
            let ci = Consonant.allCases.firstIndex(of: i)!
            let vi = Vowel.allCases.firstIndex(of: v)!
            let fi = final.flatMap { Self.jongseongIndex[$0] } ?? 0
            let code = 0xAC00 + (ci * 21 + vi) * 28 + fi
            return String(UnicodeScalar(code)!)
        }
        if let i = initial { return String(i.rawValue) }
        if let v = vowel { return String(v.rawValue) }
        return ""
    }
}

public struct JamoComposer {
    public private(set) var jamos: [Jamo] = []

    public init() {}

    public var isEmpty: Bool { jamos.isEmpty }

    public mutating func append(_ jamo: Jamo) { jamos.append(jamo) }

    @discardableResult
    public mutating func backspace() -> Bool {
        guard !jamos.isEmpty else { return false }
        jamos.removeLast()
        return true
    }

    public mutating func clear() { jamos.removeAll() }

    /// 모음 조합 (일본어 표기에 필요한 것 + 표준 몇 개)
    private static let vowelCombinations: [Vowel: [Vowel: Vowel]] = [
        .o: [.a: .wa, .ae: .wae, .i: .oe],
        .u: [.eo: .wo, .e: .we, .i: .wi],
        .eu: [.i: .ui],
    ]

    /// 자모 스트림 전체를 다시 조합 (스트림이 짧으므로 매번 재계산)
    public var syllables: [Syllable] {
        var result: [Syllable] = []
        var cur = Syllable()

        func flush() {
            if cur != Syllable() { result.append(cur) }
            cur = Syllable()
        }

        for jamo in jamos {
            switch jamo {
            case .consonant(let c):
                if cur.vowel == nil {
                    if cur.initial == nil {
                        cur.initial = c
                    } else {
                        flush()
                        cur.initial = c
                    }
                } else if cur.initial != nil, cur.final == nil, Syllable.canBeFinal(c) {
                    cur.final = c
                } else {
                    flush()
                    cur.initial = c
                }
            case .vowel(let v):
                if let f = cur.final {
                    // 받침 재해석: 받침을 다음 음절 초성으로
                    cur.final = nil
                    flush()
                    cur.initial = f
                    cur.vowel = v
                } else if cur.vowel == nil {
                    cur.vowel = v
                } else if let combined = Self.vowelCombinations[cur.vowel!]?[v] {
                    cur.vowel = combined
                } else {
                    flush()
                    cur.vowel = v
                }
            }
        }
        flush()
        return result
    }
}
