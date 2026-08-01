package com.mastergear.hangulji.keyboard

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mastergear.hangulji.core.HanguljiComposer

/** IMS가 구현하는 텍스트 출력 추상화 — iOS TextOutput과 동일 계약 */
interface TextOutput {
    fun setMarkedText(s: String)   // 조합/선택 후보를 조합 영역(밑줄)으로 표시
    fun commitText(s: String)      // 조합 영역을 s로 치환·확정 (원자적)
    fun clearMarkedText()          // 조합 취소 — 아무것도 확정하지 않고 조합 영역 제거
    fun insertText(s: String)      // 조합과 무관한 직접 삽입 (공백·개행·구두점)
    fun deleteBackward()
}

/** 한자 후보 공급자 — 실기는 KanjiConverter 어댑터, JVM 테스트는 페이크 */
fun interface CandidateSource {
    fun candidateList(reading: String, max: Int): List<String>
}

/** 키보드 상태머신. Android 프레임워크 비의존(Compose 스냅숏 상태만) — JVM 유닛테스트 대상.
 *  의미론은 ios/Keyboard/KeyboardModel.swift(현행)와 동일. 유일한 의도적 차이:
 *  candidateList가 빈 목록(엔진 미탑재)이면 가나를 그대로 확정한다. */
class KeyboardModel(private val candidateSource: CandidateSource) {
    var preview by mutableStateOf(""); private set
    var candidates by mutableStateOf<List<String>>(emptyList()); private set
    var selectedIndex by mutableIntStateOf(0); private set
    var isShifted by mutableStateOf(false)

    var output: TextOutput? = null

    private val composer = HanguljiComposer()

    private val isSelecting: Boolean get() = candidates.isNotEmpty()

    fun tapKey(latin: Char) {
        if (isSelecting) commitCandidate(selectedIndex)
        if (composer.insert(latin)) {
            isShifted = false
            refreshPreview()
        }
    }

    fun toggleShift() { isShifted = !isShifted }

    fun tapSpace() {
        if (isSelecting) {
            selectedIndex = (selectedIndex + 1) % candidates.size
            preview = candidates[selectedIndex]
            output?.setMarkedText(candidates[selectedIndex])
            return
        }
        if (composer.isEmpty) {
            output?.insertText(" ")
            return
        }
        val reading = composer.reading
        if (reading == null) {
            commitComposition()   // 매핑 불가 포함 → 그대로 확정
            return
        }
        val list = candidateSource.candidateList(reading, 9)
        if (list.isEmpty()) {
            commitComposition()   // 엔진 미탑재 폴백 — 가나 그대로 확정
            return
        }
        candidates = list
        selectedIndex = 0
        preview = list[0]
        output?.setMarkedText(list[0])
    }

    fun tapCandidate(index: Int) {
        if (index !in candidates.indices) return
        commitCandidate(index)
    }

    fun tapEnter() {
        if (isSelecting) { commitCandidate(selectedIndex); return }
        if (!composer.isEmpty) { commitComposition(); return }
        output?.insertText("\n")
    }

    fun tapBackspace() {
        if (isSelecting) {   // 변환 취소 → 가나 조합으로 복귀
            candidates = emptyList()
            selectedIndex = 0
            refreshPreview()   // composer는 그대로라 가나가 다시 조합 영역에 표시됨
            return
        }
        if (composer.backspace()) {
            refreshPreview()   // 조합이 비면 refreshPreview가 clearMarkedText 호출
        } else {
            output?.deleteBackward()
        }
    }

    /** 조합/선택 확정과 함께 삽입되는 구두점·기호는 하나의 원자적 commitText로 합친다
     *  (iOS 프록시 배칭 레이스의 교훈 — InputConnection에서도 같은 구조가 안전하다). */
    fun tapSymbol(s: String) {
        if (s == "ー") {
            if (isSelecting) commitCandidate(selectedIndex)
            if (composer.insert('-')) refreshPreview()
            return
        }
        if (isSelecting) {
            output?.commitText(candidates[selectedIndex] + s)
            composer.clear()
            candidates = emptyList()
            selectedIndex = 0
            preview = ""
            return
        }
        if (!composer.isEmpty) {
            output?.commitText(composer.markedText + s)
            composer.clear()
            preview = ""
            return
        }
        output?.insertText(s)
    }

    /** 포커스 이탈 등 — 조합/선택 중이면 조합 영역 내용을 그대로 확정 */
    fun commitAll() {
        if (isSelecting) { commitCandidate(selectedIndex); return }
        if (!composer.isEmpty) commitComposition()
    }

    /** 필드 전환 등 외부 요인 — 아무것도 확정하지 않고 상태만 파기 (output 호출 없음) */
    fun discardComposition() {
        composer.clear()
        candidates = emptyList()
        selectedIndex = 0
        preview = ""
    }

    private fun commitComposition() {
        output?.commitText(composer.markedText)
        composer.clear()
        preview = ""
    }

    private fun commitCandidate(index: Int) {
        output?.commitText(candidates[index])
        composer.clear()
        candidates = emptyList()
        selectedIndex = 0
        preview = ""
    }

    private fun refreshPreview() {
        preview = composer.markedText
        if (preview.isEmpty()) {
            output?.clearMarkedText()
        } else {
            output?.setMarkedText(preview)
        }
    }
}
