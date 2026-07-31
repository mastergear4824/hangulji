import XCTest
// Keyboard/ 소스가 이 테스트 타깃에 직접 컴파일되므로 별도 import 불필요

final class FakeOutput: TextOutput {
    var marked: [String] = []
    var committed: [String] = []
    var inserted: [String] = []
    var clearedCount = 0
    var deletions = 0

    func setMarkedText(_ s: String) { marked.append(s) }
    func commitText(_ s: String) { committed.append(s) }
    func clearMarkedText() { clearedCount += 1 }
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
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }   // 토우쿄우
        XCTAssertEqual(model.preview, "とうきょう")
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(out.marked.last, "とうきょう")   // 인라인 마크드 텍스트로도 반영
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
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        XCTAssertFalse(model.candidates.isEmpty)
        XCTAssertTrue(model.candidates.contains("東京"), "\(model.candidates)")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.preview, model.candidates[0])
        XCTAssertEqual(out.marked.last, model.candidates[0])
        model.tapSpace()   // 다음 후보
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.preview, model.candidates[1])
        XCTAssertEqual(out.marked.last, model.candidates[1])
    }

    func testCandidateTapCommits() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        guard let tokyoIndex = model.candidates.firstIndex(of: "東京") else { return XCTFail() }
        model.tapCandidate(tokyoIndex)
        XCTAssertEqual(out.committed, ["東京"])
        XCTAssertTrue(out.inserted.isEmpty)
        XCTAssertEqual(model.preview, "")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testEnterCommitsKanaWhileComposing() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapEnter()
        XCTAssertEqual(out.committed, ["とうきょう"])
        XCTAssertTrue(out.inserted.isEmpty)
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
        XCTAssertEqual(out.committed, [first])
        XCTAssertEqual(model.preview, "ㅋ")
        XCTAssertEqual(out.marked.last, "ㅋ")
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testBackspaceJamoThenProxy() {
        let (model, out) = makeModel()
        model.tapKey("z"); model.tapKey("k")   // 카
        model.tapBackspace()                   // ㅏ 제거 → ㅋ
        XCTAssertEqual(model.preview, "ㅋ")
        model.tapBackspace()                   // 조합 비움 → 마크드 텍스트 제거(프록시 위임 아님)
        XCTAssertEqual(model.preview, "")
        XCTAssertGreaterThanOrEqual(out.clearedCount, 1)
        XCTAssertEqual(out.deletions, 0)
        model.tapBackspace()                   // 프록시로 위임
        XCTAssertEqual(out.deletions, 1)
    }

    func testBackspaceCancelsSelection() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }
        model.tapSpace()
        model.tapBackspace()
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(model.preview, "とうきょう")   // 가나로 복귀
        XCTAssertEqual(out.marked.last, "とうきょう")   // 마크드 텍스트도 다시 표시
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
        XCTAssertEqual(out.committed, ["별"])
        XCTAssertTrue(out.inserted.isEmpty)
    }

    func testDiscardCompositionClearsWithoutOutputCalls() {
        let (model, out) = makeModel()
        for ch in "xhdnzydn" { model.tapKey(ch) }   // 토우쿄우 — 조합 진행
        let (markedBefore, committedBefore, insertedBefore, clearedBefore, deletionsBefore) =
            (out.marked.count, out.committed.count, out.inserted.count, out.clearedCount, out.deletions)

        model.discardComposition()   // 텍스트 필드 전환 시뮬레이션 — 아무것도 확정하지 않음

        XCTAssertEqual(model.preview, "")
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(out.marked.count, markedBefore)
        XCTAssertEqual(out.committed.count, committedBefore)
        XCTAssertEqual(out.inserted.count, insertedBefore)
        XCTAssertEqual(out.clearedCount, clearedBefore)
        XCTAssertEqual(out.deletions, deletionsBefore)

        // 이후 새 조합은 정상적으로 시작되어야 함
        model.tapKey("z")
        XCTAssertEqual(model.preview, "ㅋ")
    }

    func testSymbols() {
        let (model, out) = makeModel()
        model.tapSymbol("。")
        XCTAssertEqual(out.inserted, ["。"])
        for ch in "fk" { model.tapKey(ch) }    // 라
        model.tapSymbol("ー")                   // 조합 중 ー는 조합에 들어감
        XCTAssertEqual(model.preview, "らー")
        XCTAssertEqual(out.marked.last, "らー")
        model.tapSymbol("。")                   // 조합 커밋 후 。
        XCTAssertEqual(out.committed, ["らー"])
        XCTAssertEqual(out.inserted, ["。", "。"])
    }
}
