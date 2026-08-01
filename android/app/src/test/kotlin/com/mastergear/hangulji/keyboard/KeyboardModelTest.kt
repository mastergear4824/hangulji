package com.mastergear.hangulji.keyboard

import com.mastergear.hangulji.core.toKatakana
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeOutput : TextOutput {
    val marked = mutableListOf<String>()
    val committed = mutableListOf<String>()
    val inserted = mutableListOf<String>()
    var clearedCount = 0
    var deletions = 0

    override fun setMarkedText(s: String) { marked.add(s) }
    override fun commitText(s: String) { committed.add(s) }
    override fun clearMarkedText() { clearedCount++ }
    override fun insertText(s: String) { inserted.add(s) }
    override fun deleteBackward() { deletions++ }
}

/** JVM 테스트용 후보 공급 페이크 — 계약(한자들 + 가나 + 가타카나 폴백)만 흉내낸다 */
private class FakeCandidateSource : CandidateSource {
    override fun candidateList(reading: String, max: Int): List<String> = when (reading) {
        "とうきょう" -> listOf("東京", "東教", "とうきょう", "トウキョウ")
        else -> listOf(reading, reading.toKatakana()).distinct()
    }
}

class KeyboardModelTest {
    private fun makeModel(
        source: CandidateSource = FakeCandidateSource(),
    ): Pair<KeyboardModel, FakeOutput> {
        val model = KeyboardModel(source)
        val out = FakeOutput()
        model.output = out
        return model to out
    }

    @Test
    fun typingShowsKanaPreview() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)   // 토우쿄우
        assertEquals("とうきょう", model.preview)
        assertTrue(model.candidates.isEmpty())
        assertEquals("とうきょう", out.marked.last())   // 조합 영역에도 반영
    }

    @Test
    fun shiftIsOneShot() {
        val (model, _) = makeModel()
        model.toggleShift()
        assertTrue(model.isShifted)
        model.tapKey('R')   // View가 시프트 상태의 라틴 대문자를 전달
        assertFalse(model.isShifted)
        assertEquals("ㄲ", model.preview)
    }

    @Test
    fun spaceConverts() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        assertTrue(model.candidates.isNotEmpty())
        assertTrue("${model.candidates}", model.candidates.contains("東京"))
        assertEquals(0, model.selectedIndex)
        assertEquals(model.candidates[0], model.preview)
        assertEquals(model.candidates[0], out.marked.last())
        model.tapSpace()   // 다음 후보
        assertEquals(1, model.selectedIndex)
        assertEquals(model.candidates[1], model.preview)
        assertEquals(model.candidates[1], out.marked.last())
    }

    @Test
    fun candidateTapCommits() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        val tokyoIndex = model.candidates.indexOf("東京")
        assertTrue(tokyoIndex >= 0)
        model.tapCandidate(tokyoIndex)
        assertEquals(listOf("東京"), out.committed)
        assertTrue(out.inserted.isEmpty())
        assertEquals("", model.preview)
        assertTrue(model.candidates.isEmpty())
    }

    @Test
    fun enterCommitsKanaWhileComposing() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapEnter()
        assertEquals(listOf("とうきょう"), out.committed)
        assertTrue(out.inserted.isEmpty())
        assertEquals("", model.preview)
    }

    @Test
    fun enterInsertsNewlineWhenIdle() {
        val (model, out) = makeModel()
        model.tapEnter()
        assertEquals(listOf("\n"), out.inserted)
    }

    @Test
    fun typingDuringSelectionCommitsCurrentCandidate() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        val first = model.candidates[0]
        model.tapKey('z')   // 새 타이핑
        assertEquals(listOf(first), out.committed)
        assertEquals("ㅋ", model.preview)
        assertEquals("ㅋ", out.marked.last())
        assertTrue(model.candidates.isEmpty())
    }

    @Test
    fun backspaceJamoThenProxy() {
        val (model, out) = makeModel()
        model.tapKey('z'); model.tapKey('k')   // 카
        model.tapBackspace()                   // ㅏ 제거 → ㅋ
        assertEquals("ㅋ", model.preview)
        model.tapBackspace()                   // 조합 비움 → 조합 영역 제거(프록시 위임 아님)
        assertEquals("", model.preview)
        assertTrue(out.clearedCount >= 1)
        assertEquals(0, out.deletions)
        model.tapBackspace()                   // 프록시로 위임
        assertEquals(1, out.deletions)
    }

    @Test
    fun backspaceCancelsSelection() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        model.tapBackspace()
        assertTrue(model.candidates.isEmpty())
        assertEquals("とうきょう", model.preview)          // 가나로 복귀
        assertEquals("とうきょう", out.marked.last())      // 조합 영역도 다시 표시
    }

    @Test
    fun spaceWhenIdleInsertsSpace() {
        val (model, out) = makeModel()
        model.tapSpace()
        assertEquals(listOf(" "), out.inserted)
    }

    @Test
    fun unmappableCommitsAsIs() {
        val (model, out) = makeModel()
        for (ch in "quf") model.tapKey(ch)   // 별 (매핑 불가 → reading null)
        model.tapSpace()                      // 변환 불가 → 그대로 확정
        assertEquals(listOf("별"), out.committed)
        assertTrue(out.inserted.isEmpty())
    }

    @Test
    fun discardCompositionClearsWithoutOutputCalls() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        val counts = listOf(
            out.marked.size, out.committed.size, out.inserted.size, out.clearedCount, out.deletions)

        model.discardComposition()   // 필드 전환 시뮬레이션 — 아무것도 확정하지 않음

        assertEquals("", model.preview)
        assertTrue(model.candidates.isEmpty())
        assertEquals(counts, listOf(
            out.marked.size, out.committed.size, out.inserted.size, out.clearedCount, out.deletions))

        model.tapKey('z')   // 이후 새 조합은 정상 시작
        assertEquals("ㅋ", model.preview)
    }

    @Test
    fun symbols() {
        val (model, out) = makeModel()
        model.tapSymbol("。")
        assertEquals(listOf("。"), out.inserted)
        for (ch in "fk") model.tapKey(ch)     // 라
        model.tapSymbol("ー")                  // 조합 중 ー는 조합에 들어감
        assertEquals("らー", model.preview)
        assertEquals("らー", out.marked.last())
        model.tapSymbol("。")                  // 조합 확정+。를 하나의 원자적 commitText로
        assertEquals(listOf("らー。"), out.committed)
        assertEquals(listOf("。"), out.inserted)   // 두 번째 。는 별도 insertText로 나가지 않음
        assertEquals("", model.preview)
    }

    @Test
    fun symbolWhileSelectingCommitsCandidateAndSymbolAtomically() {
        val (model, out) = makeModel()
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        val first = model.candidates[0]
        model.tapSymbol("。")
        assertEquals(listOf(first + "。"), out.committed)
        assertTrue(out.inserted.isEmpty())
        assertTrue(model.candidates.isEmpty())
        assertEquals("", model.preview)
    }

    @Test
    fun engineUnavailableCommitsKanaAsIs() {   // Android 고유: .so 미탑재 그레이스풀 디그레이드
        val (model, out) = makeModel(source = { _, _ -> emptyList() })
        for (ch in "xhdnzydn") model.tapKey(ch)
        model.tapSpace()
        assertEquals(listOf("とうきょう"), out.committed)
        assertTrue(model.candidates.isEmpty())
        assertEquals("", model.preview)
    }
}
