package com.mastergear.hangulji

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.mastergear.hangulji.engine.DictionaryInstaller
import com.mastergear.hangulji.engine.KanjiConverter
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** 완료 정의의 자동화 절반: 실기(에뮬레이터)에서 엔진이 とうきょう→東京을 낸다.
 *  전제: build-engine.sh 실행 완료(jniLibs + assets). */
@RunWith(AndroidJUnit4::class)
class EngineSmokeTest {
    @Test
    fun tokyoIsAmongCandidates() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dictionary = DictionaryInstaller.ensureInstalled(context)
        val converter = KanjiConverter(dictionary.absolutePath)
        assertTrue("엔진 .so 미탑재 — scripts/build-engine.sh 후 재시도", converter.isAvailable)
        val candidates = converter.candidateList("とうきょう", max = 9)
        assertTrue("후보: $candidates", candidates.contains("東京"))
        assertTrue("후보: $candidates", candidates.contains("とうきょう"))   // 가나 폴백 보장
        assertTrue("후보: $candidates", candidates.contains("トウキョウ"))   // 가타카나 폴백 보장
        converter.close()
    }
}
