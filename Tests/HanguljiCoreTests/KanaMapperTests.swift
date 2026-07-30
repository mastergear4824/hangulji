import XCTest
@testable import HanguljiCore

final class KanaMapperTests: XCTestCase {
    /// 편의: 한글 문자열 → 음절 배열 (완성형 분해)
    private func syllables(_ text: String) -> [Syllable] {
        text.unicodeScalars.map { scalar in
            let code = Int(scalar.value) - 0xAC00
            precondition(code >= 0 && code < 11172, "완성형 한글만: \(scalar)")
            let ci = code / (21 * 28), vi = (code % (21 * 28)) / 28, fi = code % 28
            let finals: [Int: Consonant] = [1: .g, 2: .gg, 4: .n, 7: .d, 8: .r, 16: .m,
                                            17: .b, 19: .s, 20: .ss, 21: .ng, 22: .j, 23: .ch,
                                            24: .k, 25: .t, 26: .p, 27: .h]
            return Syllable(initial: Consonant.allCases[ci],
                            vowel: Vowel.allCases[vi],
                            final: fi == 0 ? nil : finals[fi])
        }
    }
    private func kana(_ text: String) -> String {
        KanaMapper.map(syllables(text)).map(\.display).joined()
    }

    // 기본표 (스펙 §4.1) — 행별 골든
    func testVowelRow()      { XCTAssertEqual(kana("아이우에오야유요와워"), "あいうえおやゆよわを") }
    func testKRow()          { XCTAssertEqual(kana("카키쿠케코캬큐쿄"), "かきくけこきゃきゅきょ") }
    func testGRow()          { XCTAssertEqual(kana("가기구게고갸규교"), "がぎぐげごぎゃぎゅぎょ") }
    func testSRow()          { XCTAssertEqual(kana("사시스세소샤슈쇼"), "さしすせそしゃしゅしょ") }
    func testZRow()          { XCTAssertEqual(kana("자지즈제조쟈쥬죠"), "ざじずぜぞじゃじゅじょ") }
    func testTRow()          { XCTAssertEqual(kana("타치츠테토챠츄쵸"), "たちつてとちゃちゅちょ") }
    func testDRow()          { XCTAssertEqual(kana("다데도띠뜨"), "だでどぢづ") }
    func testNRow()          { XCTAssertEqual(kana("나니누네노냐뉴뇨"), "なにぬねのにゃにゅにょ") }
    func testHRow()          { XCTAssertEqual(kana("하히후헤호햐휴효"), "はひふへほひゃひゅひょ") }
    func testBRow()          { XCTAssertEqual(kana("바비부베보뱌뷰뵤"), "ばびぶべぼびゃびゅびょ") }
    func testPRow()          { XCTAssertEqual(kana("파피푸페포퍄퓨표"), "ぱぴぷぺぽぴゃぴゅぴょ") }
    func testMRow()          { XCTAssertEqual(kana("마미무메모먀뮤묘"), "まみむめもみゃみゅみょ") }
    func testRRow()          { XCTAssertEqual(kana("라리루레로랴류료"), "らりるれろりゃりゅりょ") }

    // 받침 (스펙 §4.1)
    func testFinalN()        { XCTAssertEqual(kana("간"), "がん") }
    func testFinalSSokuon()  { XCTAssertEqual(kana("삿포로"), "さっぽろ") }
    func testFinalAliases()  {
        XCTAssertEqual(kana("혹카이도"), "ほっかいど")   // 받침 ㄱ → っ
        XCTAssertEqual(kana("잇파이"), "いっぱい")       // 받침 ㅅ → っ
        XCTAssertEqual(kana("망가"), "まんが")           // 받침 ㅇ → ん
        XCTAssertEqual(kana("돔부리"), "どんぶり")       // 받침 ㅁ → ん
    }

    // 관용 별칭 (스펙 §4.2)
    func testTenseAliases()  {
        XCTAssertEqual(kana("까"), "か")
        XCTAssertEqual(kana("홋까이도우"), "ほっかいどう")
        XCTAssertEqual(kana("빠"), "ぱ")
        XCTAssertEqual(kana("따"), "た")
        XCTAssertEqual(kana("싸"), "さ")
    }
    func testTsuVariants()   {
        XCTAssertEqual(kana("츠"), "つ")
        XCTAssertEqual(kana("쓰"), "つ")
        XCTAssertEqual(kana("쯔"), "つ")
    }
    func testJjRow()         {
        XCTAssertEqual(kana("찌"), "ち")
        XCTAssertEqual(kana("짜"), "ちゃ")   // ~짱 습관
    }
    func testChAliases()     {
        XCTAssertEqual(kana("차"), "ちゃ")
        XCTAssertEqual(kana("추"), "ちゅ")
        XCTAssertEqual(kana("초"), "ちょ")
    }
    func testUEuEquivalence() {
        XCTAssertEqual(kana("수"), "す")
        XCTAssertEqual(kana("주"), "ず")
        XCTAssertEqual(kana("흐"), "ふ")
        XCTAssertEqual(kana("크"), "く")
    }

    // 확장 가타카나 음절 (스펙 §4.3) — 히라가나 소문자 조합으로 출력
    func testExtendedSyllables() {
        XCTAssertEqual(kana("티"), "てぃ")
        XCTAssertEqual(kana("디"), "でぃ")
        XCTAssertEqual(kana("투"), "とぅ")
        XCTAssertEqual(kana("두"), "どぅ")
        XCTAssertEqual(kana("화"), "ふぁ")
        XCTAssertEqual(kana("휘"), "ふぃ")
        XCTAssertEqual(kana("훼"), "ふぇ")
        XCTAssertEqual(kana("훠"), "ふぉ")
        XCTAssertEqual(kana("위"), "うぃ")
        XCTAssertEqual(kana("웨"), "うぇ")
    }

    // 자↔쟈 구분 유지 (스펙 §4.4)
    func testZaVsJa() {
        XCTAssertEqual(kana("자"), "ざ")
        XCTAssertEqual(kana("쟈"), "じゃ")
    }

    // 매핑 불가 음절은 한글 그대로 + isMapped=false (스펙 §3)
    func testUnmappableSyllable() {
        let mapped = KanaMapper.map(syllables("별"))
        XCTAssertEqual(mapped, [MappedSyllable(display: "별", isMapped: false)])
        // 받침 ㄹ은 매핑 불가 → 몸통이 매핑 가능해도 음절 전체 불가
        let mapped2 = KanaMapper.map(syllables("갈"))
        XCTAssertEqual(mapped2, [MappedSyllable(display: "갈", isMapped: false)])
    }

    // 미완성 음절 (조합 중): 자모 낱자 표시, isMapped=false
    func testIncompleteSyllable() {
        let mapped = KanaMapper.map([Syllable(initial: .k)])
        XCTAssertEqual(mapped, [MappedSyllable(display: "ㅋ", isMapped: false)])
    }
}
