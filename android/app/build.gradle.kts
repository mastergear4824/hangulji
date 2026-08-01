plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.mastergear.hangulji"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mastergear.hangulji"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }

    // 엔진 .so가 있는 ABI만 네이티브 빌드 — 없으면(예: CI) 글루도 빼고 순수 Kotlin 앱으로 빌드.
    // KanjiConverterNative.isLoaded=false 경로가 런타임 폴백을 담당한다 (Task 6 Kotlin 래퍼).
    val engineAbis = listOf("arm64-v8a", "x86_64")
        .filter { file("src/main/jniLibs/$it/libHanguljiEngine.so").exists() }
    if (engineAbis.isNotEmpty()) {
        ndkVersion = "27.2.12479018"
        externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }
        defaultConfig { ndk { abiFilters.addAll(engineAbis) } }

        // 기기 실측(에뮬레이터 dlopen 실패로 발견): AGP 기본 스트립(stripDebugDebugSymbols)이
        // Swift 크로스컴파일 런타임 .so 중 최소 libdispatch.so의 .dynamic 섹션을 손상시켜
        // "dlopen failed: empty/missing DT_HASH/DT_GNU_HASH (new hash type from the future?)"로
        // 로드가 실패한다. 손상된 파일도 host llvm-readelf -d로는 정상으로 보여(29개 엔트리,
        // NULL 종료 정상) AGP 번들 strip 도구 자체의 버그로 추정 — 원본(스트립 전)으로 되돌리면
        // (keepDebugSymbols) 즉시 해결됨을 실측 확인. 엔진·Swift 런타임 .so만 스트립 제외 대상으로
        // 좁혀 다른 의존성(androidx 등)의 스트립 이점은 그대로 유지한다.
        packaging {
            jniLibs {
                keepDebugSymbols += engineAbis.flatMap { abi ->
                    file("src/main/jniLibs/$abi").listFiles { f -> f.extension == "so" }
                        ?.map { "**/${it.name}" } ?: emptyList()
                }.toSet() + "**/libhangulji_jni.so"
            }
        }
    }

    sourceSets.getByName("main") { kotlin.srcDir("src/main/kotlin") }
    sourceSets.getByName("test") { kotlin.srcDir("src/test/kotlin") }
    sourceSets.getByName("androidTest") { kotlin.srcDir("src/androidTest/kotlin") }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.05.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.savedstate:savedstate-ktx:1.2.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.google.code.gson:gson:2.11.0")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

// conformance 러너가 spec/fixtures를 읽는다 — -DfixturesDir로 재지정 가능 (Task 4에서 소비)
tasks.withType<Test>().configureEach {
    systemProperty(
        "fixturesDir",
        System.getProperty("fixturesDir") ?: rootDir.resolve("../spec/fixtures").absolutePath
    )
}
