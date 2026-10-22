import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Kunci tanda tangan rilis. Berkasnya di luar repo (~/teras-inn-kunci/,
// dicadangkan owner); android/key.properties menunjuk ke sana dan tidak
// pernah masuk git. Update hanya bisa dipasang di atas aplikasi yang
// ditandatangani kunci yang SAMA — kunci hilang = semua HP harus hapus &
// pasang ulang.
val kunciRilis = Properties().apply {
    val berkas = rootProject.file("key.properties")
    if (berkas.exists()) FileInputStream(berkas).use { load(it) }
}

// Build rilis tanpa kunci harus gagal, bukan diam-diam memakai kunci debug.
gradle.taskGraph.whenReady {
    if (kunciRilis.isEmpty && allTasks.any { it.name.contains("Release") }) {
        throw GradleException(
            "android/key.properties tidak ditemukan. Salin dari cadangan " +
                "~/teras-inn-kunci/key.properties sebelum build rilis."
        )
    }
}

android {
    namespace = "com.example.kasir_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Identitas aplikasi di Android. JANGAN diganti lagi: ID lain =
        // aplikasi lain, semua HP harus hapus & pasang ulang. `namespace` di
        // atas cuma nama paket kode Kotlin, boleh beda.
        applicationId = "id.terasinn.kasir"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("rilis") {
            if (!kunciRilis.isEmpty) {
                storeFile = file(kunciRilis.getProperty("storeFile"))
                storePassword = kunciRilis.getProperty("storePassword")
                keyAlias = kunciRilis.getProperty("keyAlias")
                keyPassword = kunciRilis.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("rilis")
        }
    }
}

flutter {
    source = "../.."
}
