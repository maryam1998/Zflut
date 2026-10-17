plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// شماره‌ی نسخه از VERSION_CODE (ورک‌فلو: شماره‌ی اجرا)؛ اگه نبود، از pubspec
val envVersionCode: Int? = System.getenv("VERSION_CODE")?.toIntOrNull()

android {
    namespace = "com.linglearn.app"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.linglearn.app"
        minSdk = 29
        targetSdk = 36
        versionCode = envVersionCode ?: flutter.versionCode
        versionName = if (envVersionCode != null) "1.0.$envVersionCode" else flutter.versionName

        // فقط معماری‌های رایج → حجم APK کمتر
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    // دو نسخه:
    //  • store = برای گوگل‌پلی / کافه‌بازار / مایکت (بدون Accessibility و دسترسی به اعلان‌ها)
    //  • full  = همه‌ی قابلیت‌ها (نسخه‌ی کامل)؛ ممکنه Play Protect هشدار بده
    flavorDimensions += "dist"
    productFlavors {
        create("store") { dimension = "dist" }
        create("full") { dimension = "dist" }
    }

    // امضا با کلید اختصاصی؛ اگه فایل کلید نبود (بیلد لوکال) با debug امضا می‌شه
    val keystoreFile = file("release-key.jks")
    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreFile.exists()) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES", "META-INF/LICENSE", "META-INF/LICENSE.txt",
                "META-INF/NOTICE", "META-INF/NOTICE.txt"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Sherpa-ONNX (فایل AAR توسط ورک‌فلو داخل android/app/libs دانلود می‌شه)
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar", "*.aar"))))

    implementation("androidx.core:core:1.13.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.mlkit:translate:17.0.3")
    implementation("com.google.mlkit:text-recognition:16.0.1")             // OCR لاتین
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")  // OCR هندی
}
