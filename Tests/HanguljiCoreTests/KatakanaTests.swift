import XCTest
@testable import HanguljiCore

final class KatakanaTests: XCTestCase {
    func testBasicConversion() {
        XCTAssertEqual("とうきょう".toKatakana(), "トウキョウ")
        XCTAssertEqual("らーめん".toKatakana(), "ラーメン")   // ー 보존
        XCTAssertEqual("ふぁ".toKatakana(), "ファ")          // 소문자 가나 포함
    }
    func testNonHiraganaPreserved() {
        XCTAssertEqual("東京abc".toKatakana(), "東京abc")
    }
}
