import java.nio.charset.StandardCharsets
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Properties

// Maps SDK ?? local.properties 瑜??쎌? ??secret.properties 媛 ?덉쑝硫?MAPS_API_KEY 瑜???뼱?(?곗꽑)
val mapsApiKey: String = run {
    val p = Properties()
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { p.load(it) }
    rootProject.file("secret.properties").takeIf { it.exists() }?.inputStream()?.use { p.load(it) }
    p.getProperty("MAPS_API_KEY")?.trim().orEmpty()
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// PC쨌CI 怨듯넻 release ?쒕챸 (android/key.properties + keys/dbros-release.jks)
// ?좑툘 key.properties 媛 ?놁쑝硫?由대━利?鍮뚮뱶媛 利됱떆 ?ㅽ뙣?⑸땲??(?붾쾭洹??ㅻ줈 ?泥댄븯吏 ?딆쓬)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun monotonicVersionCode(): Int {
    val name = flutter.versionName
    val build = flutter.versionCode
    val parts = name.split(".")
    val major = parts.getOrNull(0)?.toIntOrNull() ?: 1
    val minor = parts.getOrNull(1)?.toIntOrNull() ?: 0
    val patch = parts.getOrNull(2)?.toIntOrNull() ?: 0
    return major * 100_000 + minor * 1_000 + patch * 100 + build
}

android {
    namespace = "com.dbros.drive"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications ?깆씠 ?붽뎄 (java.time ??理쒖떊 API 諛깊룷??
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dbros.drive"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = monotonicVersionCode()
        versionName = flutter.versionName
        resValue("string", "google_maps_api_key", mapsApiKey)
    }

    signingConfigs {
        create("release") {
            val store = keystoreProperties.getProperty("storeFile")
                ?: error(
                    "\n\n" +
                    "===================================================\n" +
                    "由대━利??쒕챸 ?ㅺ? ?놁뒿?덈떎!\n" +
                    "android/key.properties ? android/keys/dbros-release.jks\n" +
                    "?뚯씪???뚯궗 PC?먯꽌 蹂듭궗????PC???숈씪???꾩튂??遺숈뿬?ｊ퀬\n" +
                    "?ㅼ떆 鍮뚮뱶?섏꽭??\n" +
                    "===================================================\n"
                )
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = rootProject.file(store)
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("release") {
            // ??긽 release ?쒕챸 ?ㅼ젙 ?ъ슜 (???놁쑝硫???signingConfigs ?먯꽌 鍮뚮뱶 以묐떒)
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = true   // minifyEnabled -> isMinifyEnabled
            isShrinkResources = true // shrinkResources -> isShrinkResources

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // google_mlkit_text_recognition: Korean script (TextRecognitionScript.korean)
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}

// release APK 蹂듭궗: ?좎쭨 + pubspec 踰꾩쟾 (bump ??tools/build_release_apk.ps1 濡??좏뻾)
tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        val date = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE) // yyyyMMdd
        val flutterRoot = project.projectDir.resolve("../..").normalize()
        val pubspecFile = flutterRoot.resolve("pubspec.yaml")
        var suffix = ""
        if (pubspecFile.exists()) {
            val text = pubspecFile.readText(StandardCharsets.UTF_8)
            val vm = Regex("^version:\\s*(.+)\\+(\\d+)\\s*$", RegexOption.MULTILINE).find(text)
            if (vm != null) {
                val vName = vm.groupValues[1].replace(".", "_")
                val bNum = vm.groupValues[2].padStart(2, '0')
                suffix = "_v${vName}_$bNum"
            }
        }
        val outDir = project.projectDir.resolve("../../build/app/outputs/flutter-apk").normalize()
        val defaultApk = File(outDir, "app-release.apk")
        val namedApk = File(outDir, "DbrosInstall_${date}${suffix}.apk")
        if (defaultApk.exists()) {
            if (namedApk.exists()) namedApk.delete()
            defaultApk.copyTo(namedApk, overwrite = true)
        }
    }
}
