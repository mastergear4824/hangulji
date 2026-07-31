import XCTest
// Keyboard/ 소스가 이 테스트 타깃에 직접 컴파일되므로 별도 import 불필요

final class FakeOutput: TextOutput {
    var inserted: [String] = []
    var deletions = 0
    func insertText(_ s: String) { inserted.append(s) }
    func deleteBackward() { deletions += 1 }
}

final class KeyboardModelTests: XCTestCase {
    private func makeModel() -> (KeyboardModel, FakeOutput) {
        let model = KeyboardModel()
        let out = FakeOutput()
        model.output = out
        return (model, out)
    }

    func testTypingShowsKanaPreview() {
        let (model, _) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }   // 토우쿄우
        XCTAssertEqual(model.preview, "とうきょう")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testShiftIsOneShot() {
        let (model, _) = makeModel()
        model.toggleShift()
        XCTAssertTrue(model.isShifted)
        model.tapKey("R")   // View가 시프트 상태의 라틴 대문자를 전달
        XCTAssertFalse(model.isShifted)
        XCTAssertEqual(model.preview, "ㄲ")
    }

    func testSpaceConverts() {
        let (model, _) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        XCTAssertFalse(model.candidates.isEmpty)
        XCTAssertTrue(model.candidates.contains("東京"), "\(model.candidates)")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.preview, model.candidates[0])
        model.tapSpace()   // 다음 후보
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.preview, model.candidates[1])
    }

    func testCandidateTapCommits() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        guard let tokyoIndex = model.candidates.firstIndex(of: "東京") else { return XCTFail() }
        model.tapCandidate(tokyoIndex)
        XCTAssertEqual(out.inserted, ["東京"])
        XCTAssertEqual(model.preview, "")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testEnterCommitsKanaWhileComposing() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapEnter()
        XCTAssertEqual(out.inserted, ["とうきょう"])
        XCTAssertEqual(model.preview, "")
    }

    func testEnterInsertsNewlineWhenIdle() {
        let (model, out) = makeModel()
        model.tapEnter()
        XCTAssertEqual(out.inserted, ["\n"])
    }

    func testTypingDuringSelectionCommitsCurrentCandidate() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        let first = model.candidates[0]
        model.tapKey("z")   // 새 타이핑
        XCTAssertEqual(out.inserted, [first])
        XCTAssertEqual(model.preview, "ㅋ")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testBackspaceJamoThenProxy() {
        let (model, out) = makeModel()
        model.tapKey("z"); model.tapKey("k")   // 카
        model.tapBackspace()                   // ㅏ 제거 → ㅋ
        XCTAssertEqual(model.preview, "ㅋ")
        model.tapBackspace()                   // 조합 비움
        XCTAssertEqual(model.preview, "")
        model.tapBackspace()                   // 프록시로 위임
        XCTAssertEqual(out.deletions, 1)
    }

    func testBackspaceCancelsSelection() {
        let (model, _) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        model.tapBackspace()
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(model.preview, "とうきょう")   // 가나로 복귀
    }

    func testSpaceWhenIdleInsertsSpace() {
        let (model, out) = makeModel()
        model.tapSpace()
        XCTAssertEqual(out.inserted, [" "])
    }

    func testUnmappableCommitsAsIs() {
        let (model, out) = makeModel()
        for ch in "quf" { model.tapKey(ch) }   // 별 (매핑 불가)
        model.tapSpace()                        // 변환 불가 → 그대로 확정
        XCTAssertEqual(out.inserted, ["별"])
    }

    func testSymbols() {
        let (model, out) = makeModel()
        model.tapSymbol("。")
        XCTAssertEqual(out.inserted, ["。"])
        for ch in "fk" { model.tapKey(ch) }    // 라
        model.tapSymbol("ー")                   // 조합 중 ー는 조합에 들어감
        XCTAssertEqual(model.preview, "らー")
        model.tapSymbol("。")                   // 조합 커밋 후 。
        XCTAssertEqual(out.inserted, ["。", "らー", "。"])
    }
}
