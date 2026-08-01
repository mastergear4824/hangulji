package com.mastergear.hangulji.core

/** 셸(IMS)이 사용하는 파사드 — 자모와 ー(장음) 토큰의 혼합 스트림 (SPEC §5).
 *  백스페이스는 토큰 1개 단위. */
class HanguljiComposer {
    private sealed interface Token {
        data class J(val jamo: Jamo) : Token
        data object Prolonged : Token   // ー
    }

    private val tokens = mutableListOf<Token>()

    val isEmpty: Boolean get() = tokens.isEmpty()

    /** 문자를 소비했으면 true. 자모 키와 '-'만 소비한다. */
    fun insert(ch: Char): Boolean {
        val jamo = Keymap.jamo(ch)
        if (jamo != null) { tokens.add(Token.J(jamo)); return true }
        if (ch == '-') { tokens.add(Token.Prolonged); return true }
        return false
    }

    fun backspace(): Boolean {
        if (tokens.isEmpty()) return false
        tokens.removeAt(tokens.size - 1)
        return true
    }

    fun clear() { tokens.clear() }

    /** 자모 연속 구간별로 조합→매핑하고 ー를 사이에 끼운다 (SPEC §5 표시/독법 계산) */
    private val mappedElements: List<MappedSyllable>
        get() {
            val elements = mutableListOf<MappedSyllable>()
            val composer = JamoComposer()

            fun flushJamoRun() {
                if (!composer.isEmpty) {
                    elements.addAll(KanaMapper.map(composer.syllables))
                    composer.clear()
                }
            }

            for (token in tokens) when (token) {
                is Token.J -> composer.append(token.jamo)
                Token.Prolonged -> {
                    flushJamoRun()
                    elements.add(MappedSyllable("ー", isMapped = true))
                }
            }
            flushJamoRun()
            return elements
        }

    /** 조합 중 표시 문자열 (가나 + 매핑불가 한글 혼합) */
    val markedText: String get() = mappedElements.joinToString("") { it.display }

    /** 전부 매핑됐을 때만 가나 reading, 아니면 null (한자 변환 가능 여부 신호) */
    val reading: String?
        get() {
            val elements = mappedElements
            if (elements.isEmpty() || !elements.all { it.isMapped }) return null
            return elements.joinToString("") { it.display }
        }
}
