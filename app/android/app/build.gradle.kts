plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.wendelin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.wendelin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 8.0: adaptive icons, CalendarContract and AlarmClock extras.
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Emulator test of the system speech recognizer (WP20, tool/e2e_recognizer.sh).
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // Only in the test APK: the STT fixtures as audio for the recognizer test.
    sourceSets["androidTest"].assets.srcDir("../../test/fixtures/stt")

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Rust-Prüfmodul native/attest (WP47): cargo-ndk legt die .so je ABI unter build/rust/jniLibs ab.
// Welche ABIs, bestimmt Flutter über -Ptarget-platform (android-arm, android-arm64, android-x64).
val rustAbis = (project.findProperty("target-platform") as String?)
    ?.split(",")
    ?.mapNotNull {
        when (it.trim()) {
            "android-arm" -> "armeabi-v7a"
            "android-arm64" -> "arm64-v8a"
            "android-x64" -> "x86_64"
            else -> null
        }
    }
    ?.takeIf { it.isNotEmpty() }
    ?: listOf("arm64-v8a", "x86_64")
val rustJniLibs = layout.buildDirectory.dir("rust/jniLibs")
val buildRustAttest = tasks.register<Exec>("buildRustAttest") {
    val repo = rootProject.projectDir.resolve("../..")
    inputs.dir(repo.resolve("native/attest/src"))
    inputs.files(repo.resolve("native/attest/Cargo.toml"), repo.resolve("native/attest/Cargo.lock"))
    inputs.property("abis", rustAbis.joinToString(","))
    outputs.dir(rustJniLibs)
    environment("ANDROID_NDK_HOME", android.ndkDirectory.absolutePath)
    commandLine(
        repo.resolve("tool/build_attest_android.sh").absolutePath,
        rustJniLibs.get().asFile.absolutePath,
        rustAbis.joinToString(","),
    )
}
android.sourceSets["main"].jniLibs.srcDir(rustJniLibs.get().asFile)
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("JniLibFolders")) dependsOn(buildRustAttest)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // OAuth login of MCP servers in a Custom Tab (WP27). Plain AndroidX, no Google Play Services
    // or Firebase (K7, checked by tool/check_apk.sh); without a Custom Tabs browser any browser.
    implementation("androidx.browser:browser:1.8.0")
    // Same versions as the debug classpath: the integration_test plugin (dev dependency, debug
    // builds only) brings androidx.test:runner/rules and junit 4.12, and Gradle resolves the
    // test APK consistently with it. Device tests through instrumentation: FlutterE2eTest (WP19).
    androidTestImplementation("androidx.test:runner:1.3.0")
    // JVM tests of pure Kotlin logic (./gradlew :app:testDebugUnitTest), e.g. RecognitionServiceStatus.
    testImplementation("junit:junit:4.12")
    androidTestImplementation("junit:junit:4.12")
    // JVM tests of the Android-free logic (AssistantLauncher, B10): ./gradlew app:testDebugUnitTest
    testImplementation("junit:junit:4.12")
}
