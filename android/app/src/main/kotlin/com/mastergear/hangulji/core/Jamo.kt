package com.mastergear.hangulji.core

/** 초성(choseong) 유니코드 정규 순서로 선언 — ordinal이 곧 초성 인덱스 (SPEC §2.7) */
enum class Consonant(val char: Char) {
    G('ㄱ'), GG('ㄲ'), N('ㄴ'), D('ㄷ'), DD('ㄸ'), R('ㄹ'), M('ㅁ'),
    B('ㅂ'), BB('ㅃ'), S('ㅅ'), SS('ㅆ'), NG('ㅇ'), J('ㅈ'), JJ('ㅉ'),
    CH('ㅊ'), K('ㅋ'), T('ㅌ'), P('ㅍ'), H('ㅎ'),
}

/** 중성(jungseong) 유니코드 정규 순서로 선언 — ordinal이 곧 중성 인덱스 (SPEC §2.7) */
enum class Vowel(val char: Char) {
    A('ㅏ'), AE('ㅐ'), YA('ㅑ'), YAE('ㅒ'), EO('ㅓ'), E('ㅔ'),
    YEO('ㅕ'), YE('ㅖ'), O('ㅗ'), WA('ㅘ'), WAE('ㅙ'), OE('ㅚ'),
    YO('ㅛ'), U('ㅜ'), WO('ㅝ'), WE('ㅞ'), WI('ㅟ'), YU('ㅠ'),
    EU('ㅡ'), UI('ㅢ'), I('ㅣ'),
}

sealed interface Jamo {
    data class C(val consonant: Consonant) : Jamo
    data class V(val vowel: Vowel) : Jamo
}

/** 2벌식 키맵: 라틴 문자(하드웨어 자판) → 자모 (SPEC §1 — 33항목) */
object Keymap {
    private val table: Map<Char, Jamo> = mapOf(
        'q' to Jamo.C(Consonant.B), 'w' to Jamo.C(Consonant.J), 'e' to Jamo.C(Consonant.D),
        'r' to Jamo.C(Consonant.G), 't' to Jamo.C(Consonant.S),
        'y' to Jamo.V(Vowel.YO), 'u' to Jamo.V(Vowel.YEO), 'i' to Jamo.V(Vowel.YA),
        'o' to Jamo.V(Vowel.AE), 'p' to Jamo.V(Vowel.E),
        'a' to Jamo.C(Consonant.M), 's' to Jamo.C(Consonant.N), 'd' to Jamo.C(Consonant.NG),
        'f' to Jamo.C(Consonant.R), 'g' to Jamo.C(Consonant.H),
        'h' to Jamo.V(Vowel.O), 'j' to Jamo.V(Vowel.EO), 'k' to Jamo.V(Vowel.A),
        'l' to Jamo.V(Vowel.I),
        'z' to Jamo.C(Consonant.K), 'x' to Jamo.C(Consonant.T), 'c' to Jamo.C(Consonant.CH),
        'v' to Jamo.C(Consonant.P),
        'b' to Jamo.V(Vowel.YU), 'n' to Jamo.V(Vowel.U), 'm' to Jamo.V(Vowel.EU),
        'Q' to Jamo.C(Consonant.BB), 'W' to Jamo.C(Consonant.JJ), 'E' to Jamo.C(Consonant.DD),
        'R' to Jamo.C(Consonant.GG), 'T' to Jamo.C(Consonant.SS),
        'O' to Jamo.V(Vowel.YAE), 'P' to Jamo.V(Vowel.YE),
    )

    /** SPEC §1.1: 정확 일치 → 미배정 대문자는 소문자 폴백 → 그래도 없으면 null */
    fun jamo(ch: Char): Jamo? =
        table[ch] ?: if (ch.isUpperCase()) table[ch.lowercaseChar()] else null
}
