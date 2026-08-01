package com.mastergear.hangulji.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class KeymapTest {
    @Test
    fun lowercaseMappings() {
        assertEquals(Jamo.C(Consonant.G), Keymap.jamo('r'))
        assertEquals(Jamo.V(Vowel.A), Keymap.jamo('k'))
        assertEquals(Jamo.V(Vowel.EU), Keymap.jamo('m'))
    }

    @Test
    fun explicitUppercaseMappings() {
        assertEquals(Jamo.C(Consonant.GG), Keymap.jamo('R'))
        assertEquals(Jamo.C(Consonant.SS), Keymap.jamo('T'))
        assertEquals(Jamo.V(Vowel.YAE), Keymap.jamo('O'))
        assertEquals(Jamo.V(Vowel.YE), Keymap.jamo('P'))
    }

    @Test
    fun unassignedUppercaseFallsBackToLowercase() {   // SPEC §1.1
        assertEquals(Jamo.C(Consonant.M), Keymap.jamo('A'))
        assertEquals(Jamo.V(Vowel.YO), Keymap.jamo('Y'))
    }

    @Test
    fun nonJamoCharacters() {
        assertNull(Keymap.jamo('1'))
        assertNull(Keymap.jamo('-'))
        assertNull(Keymap.jamo(' '))
    }

    @Test
    fun ordinalsMatchUnicodeIndices() {   // SPEC §2.7 인덱스 표와 enum 선언 순서 일치 검증
        assertEquals(0, Consonant.G.ordinal)
        assertEquals(11, Consonant.NG.ordinal)
        assertEquals(18, Consonant.H.ordinal)
        assertEquals(0, Vowel.A.ordinal)
        assertEquals(9, Vowel.WA.ordinal)
        assertEquals(20, Vowel.I.ordinal)
    }
}
