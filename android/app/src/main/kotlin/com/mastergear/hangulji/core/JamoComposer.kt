package com.mastergear.hangulji.core

data class Syllable(
    val initial: Consonant? = null,
    val vowel: Vowel? = null,
    val final: Consonant? = null,
) {
    /** 화면 표시용 한글 — SPEC §2.7 유니코드 완성형 조합 공식 (미완성이면 낱자) */
    val hangul: String
        get() {
            if (initial != null && vowel != null) {
                val fi = final?.let { jongseongIndex[it] } ?: 0
                val code = 0xAC00 + (initial.ordinal * 21 + vowel.ordinal) * 28 + fi
                return String(Character.toChars(code))
            }
            if (initial != null) return initial.char.toString()
            if (vowel != null) return vowel.char.toString()
            return ""
        }

    companion object {
        /** 종성 인덱스 (SPEC §2.7). ㄸㅃㅉ 없음 = 종성 불가 (§2.5) */
        private val jongseongIndex: Map<Consonant, Int> = mapOf(
            Consonant.G to 1, Consonant.GG to 2, Consonant.N to 4, Consonant.D to 7,
            Consonant.R to 8, Consonant.M to 16, Consonant.B to 17, Consonant.S to 19,
            Consonant.SS to 20, Consonant.NG to 21, Consonant.J to 22, Consonant.CH to 23,
            Consonant.K to 24, Consonant.T to 25, Consonant.P to 26, Consonant.H to 27,
        )

        fun canBeFinal(c: Consonant): Boolean = jongseongIndex.containsKey(c)
    }
}

class JamoComposer {
    private val jamos = mutableListOf<Jamo>()

    val isEmpty: Boolean get() = jamos.isEmpty()

    fun append(jamo: Jamo) { jamos.add(jamo) }

    fun backspace(): Boolean {
        if (jamos.isEmpty()) return false
        jamos.removeAt(jamos.size - 1)
        return true
    }

    fun clear() { jamos.clear() }

    /** 모음 조합 결합표 (SPEC §2.4) */
    private val vowelCombinations: Map<Vowel, Map<Vowel, Vowel>> = mapOf(
        Vowel.O to mapOf(Vowel.A to Vowel.WA, Vowel.AE to Vowel.WAE, Vowel.I to Vowel.OE),
        Vowel.U to mapOf(Vowel.EO to Vowel.WO, Vowel.E to Vowel.WE, Vowel.I to Vowel.WI),
        Vowel.EU to mapOf(Vowel.I to Vowel.UI),
    )

    /** 자모 스트림 전체를 매번 처음부터 재조합 (SPEC §2.1 — 스트림이 짧아 단순함 우선) */
    val syllables: List<Syllable>
        get() {
            val result = mutableListOf<Syllable>()
            var cur = Syllable()

            fun flush() {
                if (cur != Syllable()) result.add(cur)
                cur = Syllable()
            }

            for (jamo in jamos) when (jamo) {
                is Jamo.C -> {   // SPEC §2.2
                    val c = jamo.consonant
                    if (cur.vowel == null) {
                        if (cur.initial == null) {
                            cur = cur.copy(initial = c)
                        } else {
                            flush()
                            cur = Syllable(initial = c)
                        }
                    } else if (cur.initial != null && cur.final == null && Syllable.canBeFinal(c)) {
                        cur = cur.copy(final = c)
                    } else {
                        flush()
                        cur = Syllable(initial = c)
                    }
                }
                is Jamo.V -> {   // SPEC §2.3
                    val v = jamo.vowel
                    val f = cur.final
                    if (f != null) {
                        cur = cur.copy(final = null)   // 받침 재해석: 종성을 다음 음절 초성으로
                        flush()
                        cur = Syllable(initial = f, vowel = v)
                    } else if (cur.vowel == null) {
                        cur = cur.copy(vowel = v)
                    } else {
                        val combined = vowelCombinations[cur.vowel]?.get(v)
                        if (combined != null) {
                            cur = cur.copy(vowel = combined)
                        } else {
                            flush()
                            cur = Syllable(vowel = v)
                        }
                    }
                }
            }
            flush()
            return result
        }
}
