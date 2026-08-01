package com.mastergear.hangulji.core

import org.junit.Assert.assertEquals
import org.junit.Test

class KanaMapperTest {
    private fun syllables(keys: String): List<Syllable> {
        val composer = JamoComposer()
        for (ch in keys) composer.append(Keymap.jamo(ch) ?: error("자모 아님: $ch"))
        return composer.syllables
    }

    @Test
    fun bodyAndFinal() {   // SPEC §3: 몸통+종성 독립 조회 — 간=がん
        assertEquals(
            listOf(MappedSyllable("がん", true)),
            KanaMapper.map(syllables("rks"))
        )
    }

    @Test
    fun unmappableSyllableStaysHangul() {   // 별: ㅂ+ㅕ 몸통 없음 → 한글 그대로
        assertEquals(
            listOf(MappedSyllable("별", false)),
            KanaMapper.map(syllables("quf"))
        )
    }

    @Test
    fun incompleteSyllableUnmapped() {   // SPEC §3-1: 낱자 → 매핑 불가
        assertEquals(
            listOf(MappedSyllable("ㅋ", false)),
            KanaMapper.map(syllables("z"))
        )
    }

    @Test
    fun unmappableFinalFailsWholeSyllable() {   // SPEC §3-4: 종성 ㄹ은 final 표에 없음 → 칼 전체 한글
        assertEquals(
            listOf(MappedSyllable("칼", false)),
            KanaMapper.map(syllables("zkf"))
        )
    }

    @Test
    fun katakanaConversion() {
        assertEquals("トウキョウ", "とうきょう".toKatakana())
        assertEquals("ラーメン", "らーめん".toKatakana())   // ー(U+30FC)는 범위 밖 — 보존
        assertEquals("abc東京", "abc東京".toKatakana())
    }
}
