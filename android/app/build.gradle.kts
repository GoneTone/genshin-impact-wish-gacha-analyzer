import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 上傳金鑰設定（git-ignored）。不存在時 release 退回 debug 金鑰，讓開發者照常 `flutter run --release`；
// CI 會在建置前從 secrets 寫入這個檔案，缺 secrets 時由 workflow 直接失敗。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) keystorePropertiesFile.inputStream().use { load(it) }
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

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                // storeFile 可為絕對路徑或相對於 android/ 的路徑。
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (injectedAdmobAppId.isNotEmpty()) {
                manifestPlaceholders["admobAppId"] = injectedAdmobAppId
            }
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

dependencies {
    // 下載進度監聽（PlayUpdateProgressChannel）；版本對齊 in_app_update 用的 app-update。
    implementation("com.google.android.play:app-update:2.1.0")
}
