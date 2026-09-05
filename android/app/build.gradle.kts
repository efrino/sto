import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Kunci penandatangan dibaca dari android/key.properties - berkas itu berisi
// kata sandi keystore, jadi TIDAK ikut masuk git (lihat android/.gitignore).
// Contoh isinya ada di android/key.properties.example.
val berkasKunci = rootProject.file("key.properties")
val kunci = Properties().apply {
    if (berkasKunci.exists()) {
        FileInputStream(berkasKunci).use { load(it) }
    }
}
val adaKunci = berkasKunci.exists()

/** Nilai wajib dari key.properties; kosong = build dihentikan dengan pesan jelas. */
fun kunciWajib(nama: String): String {
    val nilai = kunci.getProperty(nama)?.trim().orEmpty()
    if (nilai.isEmpty()) {
        throw GradleException(
            "android/key.properties ada tetapi \"$nama\" kosong. " +
                "Lengkapi keyAlias, keyPassword, storeFile, dan storePassword."
        )
    }
    return nilai
}

android {
    // Berkas AIDL printer pabrikan ada di src/main/aidl.
    buildFeatures {
        aidl = true
    }

    namespace = "com.maj.sto_prep"
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
        applicationId = "com.maj.sto_prep"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (adaKunci) {
            create("release") {
                keyAlias = kunciWajib("keyAlias")
                keyPassword = kunciWajib("keyPassword")
                storePassword = kunciWajib("storePassword")

                // storeFile boleh jalur mutlak (keystore disimpan di luar repo -
                // ini yang dianjurkan) maupun relatif terhadap folder android/.
                val jalur = kunciWajib("storeFile")
                val berkas = File(jalur).let {
                    if (it.isAbsolute) it else rootProject.file(jalur)
                }
                if (!berkas.exists()) {
                    throw GradleException(
                        "Keystore tidak ditemukan di ${berkas.absolutePath}. " +
                            "Periksa storeFile pada android/key.properties."
                    )
                }
                storeFile = berkas
            }
        }
    }

    buildTypes {
        debug {
            // Ditandatangani kunci RELEASE bila keystore-nya ada.
            //
            // ANDROID_ID di Android 8+ diturunkan dari kunci penandatangan
            // APK, jadi build debug yang memakai kunci debug bawaan melapor
            // sebagai PERANGKAT LAIN - pemasangan NIK yang sudah didaftarkan
            // admin langsung tidak dikenali, dan tiap komputer menghasilkan
            // ANDROID_ID-nya sendiri karena kunci debug dibuat per-mesin.
            //
            // Dengan satu kunci untuk debug dan release, ANDROID_ID sebuah
            // handheld tetap sama - dan `flutter run` tidak lagi ditolak
            // INSTALL_FAILED_UPDATE_INCOMPATIBLE lalu meng-uninstall aplikasi
            // berikut antrean kiriman yang belum sampai server.
            //
            // Tanpa key.properties, build debug tetap jalan dengan kunci debug
            // bawaan - hanya saja ANDROID_ID-nya berbeda.
            if (adaKunci) {
                signingConfig = signingConfigs.getByName("release")
            }
        }

        release {
            // Tanpa keystore, build release TIDAK dilanjutkan.
            //
            // Sebelumnya di sini dipakai kunci debug supaya `flutter run
            // --release` jalan. Untuk aplikasi yang dipasang di handheld
            // lapangan itu berbahaya: kunci debug dibuat per-komputer, jadi
            // versi berikutnya yang dibangun dari mesin lain tidak bisa dipasang
            // sebagai pembaruan - handheld harus di-uninstall dulu, dan antrean
            // kiriman yang belum sampai server ikut hilang. Kunci debug juga
            // kedaluwarsa setahun sekali.
            //
            // Lebih baik gagal di sini, di meja, daripada ketahuan saat 30
            // handheld menolak pembaruan.
            signingConfig = if (adaKunci) signingConfigs.getByName("release") else null
        }
    }
}

// Pesan yang menuntun, bukan sekadar "signing config not found".
if (!adaKunci) {
    gradle.taskGraph.whenReady {
        val adaTugasRelease = allTasks.any {
            it.name.contains("Release") && (
                it.name.startsWith("assemble") ||
                    it.name.startsWith("bundle") ||
                    it.name.startsWith("package")
                )
        }
        if (adaTugasRelease) {
            throw GradleException(
                """
                Build release dihentikan: android/key.properties belum ada.

                1. Buat keystore (SIMPAN DI LUAR repo, dan cadangkan - kehilangan
                   berkas ini berarti aplikasi tidak bisa diperbarui lagi):

                   keytool -genkey -v -keystore D:/kunci/sto-prep.jks \
                     -keyalg RSA -keysize 2048 -validity 10000 -alias sto-prep

                2. Salin android/key.properties.example menjadi
                   android/key.properties, lalu isi sesuai keystore tadi.

                3. Ulangi: flutter build apk --release

                Untuk sekadar mencoba di perangkat tanpa keystore, pakai
                `flutter run` (debug) atau `flutter build apk --debug`.
                """.trimIndent()
            )
        }
    }
}

flutter {
    source = "../.."
}
