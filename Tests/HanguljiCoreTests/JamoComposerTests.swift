import XCTest
@testable import HanguljiCore

final class JamoComposerTests: XCTestCase {
    private func compose(_ jamos: [Jamo]) -> [Syllable] {
        var c = JamoComposer()
        jamos.forEach { c.append($0) }
        return c.syllables
    }

    func testSimpleSyllable() {
        // ㅋㅏ → 카
        let s = compose([.consonant(.k), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["카"])
    }
    func testBatchimReanalysisOnVowel() {
        // ㄱㅏㄴㅣ → 가니 (받침 ㄴ이 모음 앞에서 초성으로 이동)
        let s = compose([.consonant(.g), .vowel(.a), .consonant(.n), .vowel(.i)])
        XCTAssertEqual(s.map(\.hangul), ["가", "니"])
    }
    func testExplicitNgKeepsBatchim() {
        // ㄱㅏㄴㅇㅣ → 간이 (かんい/かに 구분의 핵심)
        let s = compose([.consonant(.g), .vowel(.a), .consonant(.n), .consonant(.ng), .vowel(.i)])
        XCTAssertEqual(s.map(\.hangul), ["간", "이"])
    }
    func testCompoundVowelWo() {
        // ㅇㅜㅓ → 워 (を 전용 음절)
        let s = compose([.consonant(.ng), .vowel(.u), .vowel(.eo)])
        XCTAssertEqual(s.map(\.hangul), ["워"])
    }
    func testCompoundVowelHwa() {
        // ㅎㅗㅏ → 화
        let s = compose([.consonant(.h), .vowel(.o), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["화"])
    }
    func testUncombinableVowelStartsNewSyllable() {
        // ㅋㅏㅏ → 카 + 독립모음 ㅏ (조합 불가 → 새 요소)
        let s = compose([.consonant(.k), .vowel(.a), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["카", "ㅏ"])
    }
    func testConsonantAfterFinalFlushes() {
        // ㅅㅏㅅㅍㅗ → 삿 + 포 (받침 뒤 자음은 새 음절)
        let s = compose([.consonant(.s), .vowel(.a), .consonant(.s), .consonant(.p), .vowel(.o)])
        XCTAssertEqual(s.map(\.hangul), ["삿", "포"])
    }
    func testDoubleConsonantCannotBeFinal() {
        // ㄸ는 받침 불가: ㅋㅏㄸㅏ → 카 + 따
        let s = compose([.consonant(.k), .vowel(.a), .consonant(.dd), .vowel(.a)])
        XCTAssertEqual(s.map(\.hangul), ["카", "따"])
    }
    func testLoneConsonant() {
        // ㅋ 하나 → 미완성 음절 ㅋ
        XCTAssertEqual(compose([.consonant(.k)]).map(\.hangul), ["ㅋ"])
    }
    func testBackspaceRemovesOneJamo() {
        var c = JamoComposer()
        [Jamo.consonant(.g), .vowel(.a), .consonant(.n)].forEach { c.append($0) }
        XCTAssertEqual(c.syllables.map(\.hangul), ["간"])
        XCTAssertTrue(c.backspace())
        XCTAssertEqual(c.syllables.map(\.hangul), ["가"])
        XCTAssertTrue(c.backspace())
        XCTAssertEqual(c.syllables.map(\.hangul), ["ㄱ"])
        XCTAssertTrue(c.backspace())
        XCTAssertTrue(c.isEmpty)
        XCTAssertFalse(c.backspace())
    }
}
