package com.mastergear.hangulji.engine

import com.mastergear.hangulji.core.toKatakana

internal object KanjiConverterNative {
    val isLoaded: Boolean = try {
        // libhangulji_jni.so 로드 → DT_NEEDED로 libHanguljiEngine.so + Swift 런타임이 연쇄 로드됨
        System.loadLibrary("hangulji_jni")
        true
    } catch (e: UnsatisfiedLinkError) {
        false   // 엔진 없이 빌드된 APK(CI 등) 또는 순수 JVM 유닛 테스트 — 변환 비활성 폴백
    }

    external fun nativeInit(dictionaryPath: String): Long
    external fun nativeConvert(handle: Long, readingUtf8: ByteArray, maxCandidates: Int): ByteArray?
    external fun nativeFree(handle: Long)
}

/**
 * 후보 목록 계약은 core-swift `KanjiConverter.candidateList(for:max:)`와 동일하다:
 * 한자 후보 최대 `max`개 뒤에 가나 원문(`reading`)·가타카나(`reading.toKatakana()`) 폴백을
 * 항상 보장 삽입한다(등장 순서 유지, 중복 제거).
 *
 * 엔진 미탑재(.so 없음)나 초기화 실패 시 `handle=0`이 되어 한자 목록은 비지만, 폴백 2개는
 * 그대로 반환한다("empty kanji list, fallbacks only") — JVM 유닛 테스트(KanjiConverterTest)가
 * 이 그레이스풀 디그레이드 경로를 검증한다. 네이티브 가용 경로에서는 Shim.swift(android/engine)가
 * 이미 동일한 폴백을 포함해 조인된 문자열을 반환하므로, 여기서 다시 검사해도 중복 삽입되지 않는다.
 */
class KanjiConverter(dictionaryPath: String) {
    private var handle: Long =
        if (KanjiConverterNative.isLoaded) KanjiConverterNative.nativeInit(dictionaryPath) else 0L

    val isAvailable: Boolean get() = handle != 0L

    @Synchronized
    fun candidateList(reading: String, max: Int = 9): List<String> {
        val kanji: List<String> = if (handle == 0L) {
            emptyList()
        } else {
            val bytes = KanjiConverterNative.nativeConvert(
                handle, reading.toByteArray(Charsets.UTF_8), max)
            bytes?.toString(Charsets.UTF_8)?.split('\n')?.filter { it.isNotEmpty() } ?: emptyList()
        }
        val result = kanji.toMutableList()
        for (fallback in listOf(reading, reading.toKatakana())) {
            if (!result.contains(fallback)) result.add(fallback)
        }
        return result
    }

    @Synchronized
    fun close() {
        if (handle != 0L) {
            KanjiConverterNative.nativeFree(handle)
            handle = 0L
        }
    }
}
