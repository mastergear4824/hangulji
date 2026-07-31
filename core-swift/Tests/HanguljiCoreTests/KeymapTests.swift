import XCTest
@testable import HanguljiCore

final class KeymapTests: XCTestCase {
    func testLowercaseConsonants() {
        XCTAssertEqual(Keymap.jamo(for: "q"), .consonant(.b))   // ㅂ
        XCTAssertEqual(Keymap.jamo(for: "r"), .consonant(.g))   // ㄱ
        XCTAssertEqual(Keymap.jamo(for: "t"), .consonant(.s))   // ㅅ
        XCTAssertEqual(Keymap.jamo(for: "d"), .consonant(.ng))  // ㅇ
        XCTAssertEqual(Keymap.jamo(for: "z"), .consonant(.k))   // ㅋ
        XCTAssertEqual(Keymap.jamo(for: "g"), .consonant(.h))   // ㅎ
    }
    func testVowels() {
        XCTAssertEqual(Keymap.jamo(for: "k"), .vowel(.a))    // ㅏ
        XCTAssertEqual(Keymap.jamo(for: "h"), .vowel(.o))    // ㅗ
        XCTAssertEqual(Keymap.jamo(for: "n"), .vowel(.u))    // ㅜ
        XCTAssertEqual(Keymap.jamo(for: "m"), .vowel(.eu))   // ㅡ
        XCTAssertEqual(Keymap.jamo(for: "l"), .vowel(.i))    // ㅣ
        XCTAssertEqual(Keymap.jamo(for: "y"), .vowel(.yo))   // ㅛ
    }
    func testShiftedKeys() {
        XCTAssertEqual(Keymap.jamo(for: "Q"), .consonant(.bb)) // ㅃ
        XCTAssertEqual(Keymap.jamo(for: "R"), .consonant(.gg)) // ㄲ
        XCTAssertEqual(Keymap.jamo(for: "T"), .consonant(.ss)) // ㅆ
        XCTAssertEqual(Keymap.jamo(for: "W"), .consonant(.jj)) // ㅉ
        XCTAssertEqual(Keymap.jamo(for: "E"), .consonant(.dd)) // ㄸ
        XCTAssertEqual(Keymap.jamo(for: "P"), .vowel(.ye))     // ㅖ
        // 별도 배정 없는 대문자는 소문자와 동일
        XCTAssertEqual(Keymap.jamo(for: "A"), .consonant(.m))  // ㅁ
    }
    func testNonHangulKeysReturnNil() {
        XCTAssertNil(Keymap.jamo(for: "1"))
        XCTAssertNil(Keymap.jamo(for: " "))
        XCTAssertNil(Keymap.jamo(for: "-"))
    }
}
