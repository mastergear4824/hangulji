package com.mastergear.hangulji.engine

import android.content.Context
import java.io.File

/** assets/azooKey_dictionary → filesDir/azooKey_dictionary 1회 복사.
 *  엔진은 mmap 가능한 실파일 경로가 필요해 assets에서 직접 열 수 없다.
 *  APK가 갱신되면(lastUpdateTime 변동) 재복사한다. 최초 복사 ~35MB. */
object DictionaryInstaller {
    private const val ASSET_DIR = "azooKey_dictionary"

    fun ensureInstalled(context: Context): File {
        val target = File(context.filesDir, ASSET_DIR)
        val stamp = File(target, ".installed-version")
        val expected = context.packageManager
            .getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
        if (stamp.exists() && stamp.readText() == expected) return target
        target.deleteRecursively()
        copyAssetDir(context, ASSET_DIR, target)
        stamp.writeText(expected)
        return target
    }

    private fun copyAssetDir(context: Context, assetPath: String, target: File) {
        val names = context.assets.list(assetPath) ?: return
        if (names.isEmpty()) {   // leaf = 파일 (사전에 빈 디렉터리 없음)
            target.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            return
        }
        target.mkdirs()
        for (name in names) copyAssetDir(context, "$assetPath/$name", File(target, name))
    }
}
