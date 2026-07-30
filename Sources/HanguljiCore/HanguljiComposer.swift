// Sources/HanguljiCore/HanguljiComposer.swift

/// 셸(IMKit 컨트롤러)이 사용하는 파사드.
/// 내부 스트림은 자모와 기호(ー)의 혼합 — 백스페이스가 자모 1개 단위로 동작한다.
public struct HanguljiComposer {
    private enum Token: Equatable {
        case jamo(Jamo)
        case prolonged // ー
    }

    private var tokens: [Token] = []

    public init() {}

    public var isEmpty: Bool { tokens.isEmpty }

    /// 문자를 소비했으면 true. 자모 키와 '-'만 소비한다.
    public mutating func insert(_ ch: Character) -> Bool {
        if let jamo = Keymap.jamo(for: ch) {
            tokens.append(.jamo(jamo))
            return true
        }
        if ch == "-" {
            tokens.append(.prolonged)
            return true
        }
        return false
    }

    @discardableResult
    public mutating func backspace() -> Bool {
        guard !tokens.isEmpty else { return false }
        tokens.removeLast()
        return true
    }

    public mutating func clear() { tokens.removeAll() }

    /// 자모 연속 구간별로 조합→매핑하고 ー를 사이에 끼운다.
    private var mappedElements: [MappedSyllable] {
        var elements: [MappedSyllable] = []
        var composer = JamoComposer()

        func flushJamoRun() {
            guard !composer.isEmpty else { return }
            elements.append(contentsOf: KanaMapper.map(composer.syllables))
            composer.clear()
        }

        for token in tokens {
            switch token {
            case .jamo(let j):
                composer.append(j)
            case .prolonged:
                flushJamoRun()
                elements.append(MappedSyllable(display: "ー", isMapped: true))
            }
        }
        flushJamoRun()
        return elements
    }

    /// 조합 중 표시 문자열 (가나 + 매핑불가 한글 혼합)
    public var markedText: String {
        mappedElements.map(\.display).joined()
    }

    /// 전부 매핑됐을 때만 가나 reading, 아니면 nil (한자 변환 가능 여부)
    public var reading: String? {
        let elements = mappedElements
        guard !elements.isEmpty, elements.allSatisfy(\.isMapped) else { return nil }
        return elements.map(\.display).joined()
    }
}
