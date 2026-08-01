package com.mastergear.hangulji.core

import com.google.gson.Gson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** spec/fixtures 디렉터리의 kana.json·composition.json conformance 러너 (SPEC §6)
 *  — 모든 포트가 같은 픽스처를 통과해야 한다.
 *  개수 하드코딩 금지: 파일에 있는 만큼 전부 순회, 최소치(38/8)만 방어적으로 검사. */
class FixtureConformanceTest {
    private val fixturesDir = File(
        System.getProperty("fixturesDir")
            ?: error("-DfixturesDir 필요 (android/app/build.gradle.kts가 기본값을 주입한다)")
    )

    private data class KanaCase(
        val name: String, val keys: String, val kana: String, val fullyMapped: Boolean)
    private data class CompositionCase(
        val name: String, val keys: String, val syllables: List<String>)

    @Test
    fun kanaFixtures() {   // SPEC §6.1 — HanguljiComposer 레벨 골든
        val cases = Gson().fromJson(
            File(fixturesDir, "kana.json").readText(), Array<KanaCase>::class.java)
        assertTrue("케이스 수 ${cases.size} < 38", cases.size >= 38)
        for (c in cases) {
            val composer = HanguljiComposer()
            for (ch in c.keys) composer.insert(ch)
            assertEquals(c.name, c.kana, composer.markedText)
            assertEquals(c.name, c.fullyMapped, composer.reading != null)
        }
    }

    @Test
    fun compositionFixtures() {   // SPEC §6.2 — JamoComposer 레벨 골든
        val cases = Gson().fromJson(
            File(fixturesDir, "composition.json").readText(), Array<CompositionCase>::class.java)
        assertTrue("케이스 수 ${cases.size} < 8", cases.size >= 8)
        for (c in cases) {
            val composer = JamoComposer()
            for (ch in c.keys) {
                val jamo = Keymap.jamo(ch) ?: error("${c.name}: 자모 아님 '$ch'")
                composer.append(jamo)
            }
            assertEquals(c.name, c.syllables, composer.syllables.map { it.hangul })
        }
    }
}
