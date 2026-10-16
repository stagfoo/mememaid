plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mememaid.mememaid"
    // flutter.compileSdkVersion resolves to 36 on Flutter 3.47.0, but
    // permission_handler_android requires 37 or the release build fails with
    // "Dependency ':permission_handler_android' requires ... compileSdk of at
    // least 37". AGP 9.1.0 warns that 36 is its maximum *recommended* value;
    // that is a warning, not a limit, and 37 builds cleanly.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mememaid.mememaid"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Debug builds need a stable signing identity across machines and CI
        // runs — without this, AGP falls back to an implicit
        // ~/.android/debug.keystore that's freshly (and differently)
        // auto-generated on every fresh environment (like a GitHub Actions
        // runner), so each CI-built APK ends up signed with a different key
        // and can't be installed as an update over the last one. This keystore
        // is debug-only — never used for real release signing.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
