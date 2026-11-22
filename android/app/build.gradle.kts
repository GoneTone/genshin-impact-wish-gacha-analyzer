import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter 把所有 --dart-define／--dart-define-from-file 展開成以逗號分隔、每段 base64 的 KEY=VALUE，放進 dart-defines 屬性。
// 只有 release 建置會用到注入的 AdMob 應用程式 ID；缺少時沿用 defaultConfig 的官方測試 ID。
val injectedAdmobAppId: String = (project.findProperty("dart-defines") as String? ?: "")
    .split(",")
    .filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    .firstOrNull { it.startsWith("ADMOB_APP_ID=") }
    ?.substringAfter("=")
    .orEmpty()

android {
    namespace = "tw.reh.genshin.gacha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "tw.reh.genshin.gacha"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 官方測試應用程式 ID：debug／profile 與未注入的 release 都用它，SDK 不會因缺 ID 閃退。
        manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
    }

    buildTypes {
        release {
            if (injectedAdmobAppId.isNotEmpty()) {
                manifestPlaceholders["admobAppId"] = injectedAdmobAppId
            }
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
