// Sources/HanguljiCore/Katakana.swift

public extension String {
    /// 히라가나(U+3041–U+3096)를 가타카나(+0x60)로. 그 외 문자는 보존.
    func toKatakana() -> String {
        String(String.UnicodeScalarView(unicodeScalars.map { scalar in
            if (0x3041...0x3096).contains(scalar.value) {
                return UnicodeScalar(scalar.value + 0x60)!
            }
            return scalar
        }))
    }
}
