import XCTest
@testable import HanguljiConversion

final class KanjiConverterTests: XCTestCase {
    func testTokyoConversion() {
        let converter = KanjiConverter()
        let candidates = converter.candidateList(for: "とうきょう", max: 9)
        XCTAssertTrue(candidates.contains("東京"), "candidates: \(candidates)")
        XCTAssertTrue(candidates.contains("とうきょう"), "가나 원문 후보 포함")
        XCTAssertTrue(candidates.contains("トウキョウ"), "가타카나 후보 포함")
    }
    func testSentenceConversion() {
        let converter = KanjiConverter()
        let candidates = converter.candidateList(for: "とうきょうにいきます", max: 9)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.contains("東京") }, "candidates: \(candidates)")
    }
    func testNoDuplicates() {
        let converter = KanjiConverter()
        let candidates = converter.candidateList(for: "とうきょう", max: 9)
        XCTAssertEqual(candidates.count, Set(candidates).count)
    }
    func testFallbacksSurviveManyCandidates() {
        let converter = KanjiConverter()
        let candidates = converter.candidateList(for: "か", max: 9)
        XCTAssertTrue(candidates.contains("か"), "candidates: \(candidates)")
        XCTAssertTrue(candidates.contains("カ"), "candidates: \(candidates)")
        XCTAssertLessThanOrEqual(candidates.count, 11)
    }
}
