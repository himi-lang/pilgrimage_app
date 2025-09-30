// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream
import java.io.File

// local.properties から MAPS_API_KEY を読む（無ければ空文字）
val localProps = Properties().apply {
    val f = File(rootDir, "local.properties") // ← rootDir は android/ を指す
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val MAPS_API_KEY: String = localProps.getProperty("MAPS_API_KEY") ?: ""

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")    // Firebase を使うなら有効
    id("dev.flutter.flutter-gradle-plugin") // Flutter は最後＆ここだけ
}

android {
    // ★ google-services.json の package_name と合わせること
    namespace = "com.example.pilgrimage_app"

    // Flutter プラグインが与える値をそのまま利用
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        // ★ google-services.json の package_name と同一に
        applicationId = "com.example.pilgrimage_app"

        // 最近の Firebase は 23 推奨。flutter.minSdkVersion が 23 未満なら 23 に引き上げる
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Google Maps API Key を AndroidManifest に流し込む
        manifestPlaceholders["MAPS_API_KEY"] = MAPS_API_KEY
    }

    // Java/Kotlin 17
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildTypes {
        release {
            // まずは debug 鍵でOK（後で本番鍵に差し替え）
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // リソース競合が出る場合のみ有効化
    // packaging {
    //     resources {
    //         excludes += setOf("META-INF/*")
    //     }
    // }
}

// Flutter モジュールの場所
flutter {
    source = "../.."
}

/**
 * ---- Flutter が探す既定場所(<project>/build/app/outputs/flutter-apk)へ APK を“必ず”コピーする保険 ----
 * assembleDebug / packageDebug の存在や順序に依存せず、
 * ビルド終了時（成功時）に .apk を検出したらコピーします。
 */
gradle.buildFinished {
    // appモジュール標準のAPK出力候補
    val candidates = listOf(
        layout.buildDirectory.dir("outputs/apk/debug").get().asFile,
        layout.buildDirectory.dir("outputs/apk/release").get().asFile,
        layout.buildDirectory.dir("outputs/apk/app/debug").get().asFile,   // 環境によってはこちら
        layout.buildDirectory.dir("outputs/apk/app/release").get().asFile
    )

    // Flutter プロジェクト直下(build/...) へ出す（android の1つ上）
    // rootDir は android/、その1つ上が Flutter プロジェクトのルート
    val projectRoot = rootDir.parentFile ?: rootDir
    val dest = File(projectRoot, "build/app/outputs/flutter-apk")
    dest.mkdirs()

    var copied = false
    for (src in candidates) {
        if (src.exists()) {
            project.copy {
                from(src)
                include("*.apk")
                into(dest)
            }
            copied = true
        }
    }
    println(
        if (copied)
            "[post-copy] APK copied to: ${dest.absolutePath}"
        else
            "[post-copy] No APK found in: ${candidates.joinToString { it.absolutePath }}"
    )
}
