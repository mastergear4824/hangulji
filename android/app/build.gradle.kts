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
