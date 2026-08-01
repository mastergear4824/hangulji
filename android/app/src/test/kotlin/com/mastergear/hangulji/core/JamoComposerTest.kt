package com.mastergear.hangulji.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JamoComposerTest {
    private fun compose(keys: String): List<String> {
        val composer = JamoComposer()
        for (ch in keys) composer.append(Keymap.jamo(ch) ?: error("자모 아님: $ch"))
        return composer.syllables.map { it.hangul }
    }

    @Test fun basicSyllable() = assertEquals(listOf("카"), compose("zk"))
    @Test fun finalConsonant() = assertEquals(listOf("간"), compose("rks"))

    @Test
    fun batchimReanalysis() {   // SPEC §2.3-1: 간+ㅣ → 가/니
        assertEquals(listOf("가", "니"), compose("rksl"))
    }

    @Test
    fun compoundVowel() {   // SPEC §2.4: ㅜ+ㅓ=ㅝ, ㅗ+ㅏ=ㅘ
        assertEquals(listOf("워"), compose("dnj"))
        assertEquals(listOf("화"), compose("ghk"))
    }

    @Test
    fun doubleVowelSplits() {   // SPEC §2.3-4: 결합표 밖 모음 → flush
        assertEquals(listOf("카", "ㅏ"), compose("zkk"))
    }

    @Test
    fun ddCannotBeFinal() {   // SPEC §2.5: ㄸ 종성 불가 → 새 음절 초성
        assertEquals(listOf("카", "따"), compose("zkEk"))
    }

    @Test fun loneConsonant() = assertEquals(listOf("ㅋ"), compose("z"))
    @Test fun loneVowel() = assertEquals(listOf("ㅏ"), compose("k"))

    @Test
    fun consonantRunFlushes() {   // SPEC §2.2-1: 초성 연속 → 낱자 flush
        assertEquals(listOf("ㄱ", "ㄴ"), compose("rs"))
    }

    @Test
    fun backspaceRemovesOneJamo() {   // SPEC §2.6
        val composer = JamoComposer()
        for (ch in "rks") composer.append(Keymap.jamo(ch)!!)
        assertTrue(composer.backspace())
        assertEquals(listOf("가"), composer.syllables.map { it.hangul })
        assertTrue(composer.backspace()); assertTrue(composer.backspace())
        assertTrue(composer.isEmpty)
        assertFalse(composer.backspace())
    }

    @Test
    fun hangulRenderingFormula() {   // SPEC §2.7: 0xAC00 공식 — 힣 = ㅎ+ㅣ+ㅎ
        assertEquals("힣", Syllable(Consonant.H, Vowel.I, Consonant.H).hangul)
        assertEquals("", Syllable().hangul)
    }
}
