package com.mastergear.hangulji.core

data class MappedSyllable(val display: String, val isMapped: Boolean)

object KanaMapper {
    private val bodyTable: Map<Pair<Consonant, Vowel>, String> =
        KanaTable.body.associate { (initial, vowel, kana) -> (initial to vowel) to kana }

    private val finalTable: Map<Consonant, String> = KanaTable.finals.toMap()

    /** SPEC §3 — 몸통·종성 중 하나라도 실패하면 음절 전체 매핑 불가(한글 그대로) */
    fun map(syllables: List<Syllable>): List<MappedSyllable> = syllables.map { s ->
        val initial = s.initial ?: return@map MappedSyllable(s.hangul, false)
        val vowel = s.vowel ?: return@map MappedSyllable(s.hangul, false)
        val body = bodyTable[initial to vowel] ?: return@map MappedSyllable(s.hangul, false)
        val final = s.final ?: return@map MappedSyllable(body, true)
        val finalKana = finalTable[final] ?: return@map MappedSyllable(s.hangul, false)
        MappedSyllable(body + finalKana, true)
    }
}
