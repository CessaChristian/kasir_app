import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Kunci tanda tangan rilis di folder teras-inn-kunci/ (akar project,
// di-.gitignore, dicadangkan owner di iCloud). Update hanya bisa dipasang di
// atas aplikasi yang ditandatangani kunci yang SAMA — kunci hilang = semua HP
// harus hapus & pasang ulang. `storeFile` di key.properties relatif terhadap
// folder itu, jadi foldernya bisa langsung dipulihkan dari cadangan.
val folderKunci = rootProject.file("../teras-inn-kunci")
val kunciRilis = Properties().apply {
    val berkas = File(folderKunci, "key.properties")
    if (berkas.exists()) FileInputStream(berkas).use { load(it) }
}

// Build rilis tanpa kunci harus gagal, bukan diam-diam memakai kunci debug.
gradle.taskGraph.whenReady {
    if (kunciRilis.isEmpty && allTasks.any { it.name.contains("Release") }) {
        throw GradleException(
            "teras-inn-kunci/key.properties tidak ditemukan. Pulihkan folder " +
                "teras-inn-kunci dari cadangan iCloud ke akar project."
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
                // Cuma nama berkasnya yang dipakai: salinan lama berisi alamat
                // lengkap (~/teras-inn-kunci/...) tetap jalan.
                storeFile = File(folderKunci, File(kunciRilis.getProperty("storeFile")).name)
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
