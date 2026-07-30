import XCTest
@testable import HanguljiCore

final class HanguljiComposerTests: XCTestCase {
    /// 라틴 키 시퀀스를 입력 (2벌식 자판 기준)
    private func type(_ keys: String) -> HanguljiComposer {
        var c = HanguljiComposer()
        for ch in keys { _ = c.insert(ch) }
        return c
    }

    func testMarkedTextIsKana() {
        // 토우쿄우 = xh dn zy dn
        XCTAssertEqual(type("xhdnzydn").markedText, "とうきょう")
    }
    func testReadingWhenFullyMapped() {
        XCTAssertEqual(type("xhdnzydn").reading, "とうきょう")
    }
    func testReadingNilWhenUnmappable() {
        // quf = ㅂㅕㄹ → 별: ㅕ는 일본어에 없음 → 매핑 불가 → reading nil, 한글 그대로 노출
        let c = type("quf")
        XCTAssertNil(c.reading)
        XCTAssertEqual(c.markedText, "별")
    }
    func testProlongedSoundMark() {
        // 라-멘: fk - aps
        var c = HanguljiComposer()
        for ch in "fk" { XCTAssertTrue(c.insert(ch)) }
        XCTAssertTrue(c.insert("-"))
        for ch in "aps" { _ = c.insert(ch) }
        XCTAssertEqual(c.markedText, "らーめん")
        XCTAssertEqual(c.reading, "らーめん")
    }
    func testNonJamoKeysNotConsumed() {
        var c = HanguljiComposer()
        XCTAssertFalse(c.insert("1"))
        XCTAssertFalse(c.insert("."))
        XCTAssertFalse(c.insert(" "))
        XCTAssertTrue(c.isEmpty)
    }
    func testBackspaceJamoLevel() {
        var c = type("xhdn")           // ㅌㅗㅇㅜ → 토우 → とう
        XCTAssertEqual(c.markedText, "とう")
        XCTAssertTrue(c.backspace())   // ㅜ 삭제 → ㅌㅗㅇ은 '통'으로 재조합 → とん
        // (2벌식 표준 동작: 토우 타이핑 중에도 '통(とん)' 상태를 지나간다)
        XCTAssertEqual(c.markedText, "とん")
        XCTAssertTrue(c.backspace())   // ㅇ 제거 → 토 → と
        XCTAssertEqual(c.markedText, "と")
    }
    func testClear() {
        var c = type("xhdn")
        c.clear()
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(c.markedText, "")
    }

    // ── 문장 골든 (스펙 §7) ──
    private func kana(_ keys: String) -> String { type(keys).markedText }

    func testSentenceGoldens() {
        XCTAssertEqual(kana("xhdnzydnsldlzlaktm"), "とうきょうにいきます")   // 토우쿄우니이키마스
        XCTAssertEqual(kana("dkfl rkxhdnrhwkdlaktm".replacingOccurrences(of: " ", with: "")),
                       "ありがとうございます")                                // 아리가토우고자이마스
        XCTAssertEqual(kana("zhsslclgk"), "こんにちは")                       // 콘니치하 (こ=콘, は는 철자대로 '하')
        XCTAssertEqual(kana("rktRhdn"), "がっこう")                           // 갓코우
        XCTAssertEqual(kana("tkttlqnfl"), "さっしぶり")                       // 삿시부리 (받침 ㅅ→っ; 부=qn)
        XCTAssertEqual(kana("dhspdptkd"), "おねえさん")                       // 오네에상 (네=sp; 장음+받침ㅇ→ん)
        XCTAssertEqual(kana("dhdhtkzk"), "おおさか")                          // 오오사카
        XCTAssertEqual(kana("dpdlrk"), "えいが")                              // 에이가
        XCTAssertEqual(kana("rkdnjdlaktm"), "がをいます")                     // 가워이마스 → を 확인 (가=が)
    }
}
