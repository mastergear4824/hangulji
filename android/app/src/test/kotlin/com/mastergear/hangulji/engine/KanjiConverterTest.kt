package com.mastergear.hangulji.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** 순수 JVM 유닛 테스트 — libhangulji_jni.so는 JVM 클래스패스에 없으므로
 *  System.loadLibrary가 항상 UnsatisfiedLinkError로 실패한다. CI(엔진 미탑재 빌드)와
 *  동일한 그레이스풀 디그레이드 경로("empty kanji list, fallbacks only")를 실행 없이 검증한다. */
class KanjiConverterTest {
    @Test
    fun engineUnavailable_isAvailableFalse() {
        assertFalse(KanjiConverterNative.isLoaded)
        val converter = KanjiConverter("/nonexistent/dictionary")
        assertFalse(converter.isAvailable)
    }

    @Test
    fun engineUnavailable_candidateListIsFallbacksOnly() {
        val converter = KanjiConverter("/nonexistent/dictionary")
        val candidates = converter.candidateList("とうきょう", max = 9)
        // 한자 후보(東京 등)는 없다 — 엔진이 없으니 생성 불가.
        assertFalse("후보: $candidates", candidates.contains("東京"))
        // 가나 원문·가타카나 폴백은 항상 보장된다.
        assertEquals(listOf("とうきょう", "トウキョウ"), candidates)
    }

    @Test
    fun engineUnavailable_fallbacksDedupedWhenReadingHasNoKana() {
        // 히라가나가 없는 입력(예: 이미 가타카나)이면 toKatakana()가 그대로라 폴백 2개가 1개로 합쳐진다.
        val converter = KanjiConverter("/nonexistent/dictionary")
        val candidates = converter.candidateList("トウキョウ", max = 9)
        assertEquals(listOf("トウキョウ"), candidates)
    }
}
