import java.nio.charset.StandardCharsets
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Properties

// Maps SDK 키: local.properties 를 읽은 뒤 secret.properties 가 있으면 MAPS_API_KEY 를 덮어씀(우선)
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
}

android {
    namespace = "com.example.dbros_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 등이 요구 (java.time 등 최신 API 백포트)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.dbros_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "google_maps_api_key", mapsApiKey)
    }

    buildTypes {
        getByName("release") {
            // [수정됨] Kotlin DSL 문법에 맞게 등호(=)와 정확한 참조 사용
            signingConfig = signingConfigs.getByName("debug") // 별도의 release 키가 없다면 일단 debug로 설정
            
            isMinifyEnabled = true   // minifyEnabled -> isMinifyEnabled
            isShrinkResources = true // shrinkResources -> isShrinkResources
            
            // [수정됨] 홑따옴표(' ') 대신 쌍따옴표(" ")를 사용하고 괄호로 감싸야 함
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
}

// release APK 복사: 날짜 + pubspec 버전 (bump 는 tools/build_release_apk.ps1 로 선행)
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
                val bNum = vm.groupValues[2]
                suffix = "_v${vName}_$bNum"
            }
        }
        val outDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
        val defaultApk = File(outDir, "app-release.apk")
        val namedApk = File(outDir, "DbrosInstall_${date}${suffix}.apk")
        if (defaultApk.exists()) {
            if (namedApk.exists()) namedApk.delete()
            defaultApk.copyTo(namedApk, overwrite = true)
        }
    }
}