allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Menambal plugin pub yang belum menyebut `namespace`.
//
// blue_thermal_printer 1.2.3 masih gaya AGP 3: nama paketnya ditulis sebagai
// atribut `package` di AndroidManifest.xml - cara yang dibuang AGP 8, sehingga
// build berhenti dengan "Namespace not specified". Pluginnya sendiri tidak bisa
// disunting: isinya ada di pub cache dan ikut tertimpa tiap `flutter pub get`,
// jadi namespace-nya diisikan di sini, dibaca dari manifest plugin itu sendiri.
//
// Dikerjakan lewat refleksi supaya berkas ini tidak perlu menarik kelas AGP ke
// classpath-nya sendiri.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate

        fun metode(nama: String, jumlahArgumen: Int) =
            android.javaClass.methods.firstOrNull {
                it.name == nama && it.parameterCount == jumlahArgumen
            }?.apply { isAccessible = true }

        val sudahAda = runCatching {
            metode("getNamespace", 0)?.invoke(android) as String?
        }.getOrNull()
        if (!sudahAda.isNullOrEmpty()) return@afterEvaluate

        val manifest = file("src/main/AndroidManifest.xml")
        if (!manifest.exists()) return@afterEvaluate

        // Dicari tanpa regex supaya berkas ini bebas dari escape yang mudah
        // salah ketik. Spasi di sekitar "=" dirapikan lebih dulu.
        val kutip = 34.toChar().toString()
        val penanda = "package=" + kutip
        val teks = manifest.readText()
            .replace(" =", "=")
            .replace("= ", "=")
        val mulai = teks.indexOf(penanda)
        if (mulai < 0) return@afterEvaluate
        val paket = teks.substring(mulai + penanda.length).substringBefore(kutip)
        if (paket.isEmpty()) return@afterEvaluate

        val setter = metode("setNamespace", 1) ?: return@afterEvaluate
        setter.invoke(android, paket)
        logger.lifecycle("namespace :${project.name} diisi dari manifest: $paket")
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
