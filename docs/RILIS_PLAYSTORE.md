# Rilis ke Google Play

Panduan kerja untuk mengunggah aplikasi STO ke Play Console. Ditulis 7
September 2026, keadaan proyek pada tanggal itu.

---

## 0. Yang harus diputuskan lebih dulu

### 0.1 Server tujuan aplikasi belum siap untuk peninjau Google

Aplikasi memakai HTTPS `mspin.newarmada.biz` sebagai server bawaan &mdash;
itu satu-satunya alamat yang bisa dijangkau dari luar pabrik, jadi memang
itulah yang akan dipakai peninjau Google. Masalahnya, **deployment itu
menjalankan kode yang lebih lama** daripada server 67:

| Endpoint | mspin (bawaan aplikasi) | server 67 |
|---|---|---|
| `login`, `print-tag`, `scan-tag` | ada | ada |
| `tag-ok-prepare` | ada | ada |
| `chat-threads` (kotak pesan) | **404 &mdash; tidak ada** | ada |
| `device-claim` (klaim perangkat) | **404 &mdash; tidak ada** | ada |

Akibatnya bagi peninjau Google, yang memasang aplikasi dari nol di HP-nya:

1. ia mengisi nama perangkat, lalu login;
2. login ditolak 403 karena NIK-nya belum terpasang di HP itu;
3. aplikasi mencoba `device-claim` &mdash; **404 di mspin**;
4. ia berhenti di layar login dan tidak pernah masuk.

Aplikasi yang tidak bisa dimasuki peninjau **pasti ditolak**. Karena itu:

> **Minta dev backend men-deploy `Sto.php` + model `sto/` versi server 67 ke
> mspin sebelum mengajukan review produksi.** Selama itu belum terjadi,
> gunakan jalur **Internal testing** (bagian 6) yang tidak melalui review
> fungsional.

### 0.2 NIK uji `guest` &mdash; belum bisa dipakai apa adanya

Permintaannya memakai `guest`. Dua hal yang perlu diketahui sebelum itu
dijalankan:

| Kenyataan | Akibatnya |
|---|---|
| `guest` berperan **operator** dengan kolom `permissions` **NULL** | Setelah berhasil masuk, peninjau melihat beranda bertuliskan *"Belum ada hak akses menu untuk NIK ini"*. Aplikasi tampak kosong &rarr; ditolak karena "fungsi minimal". |
| `guest` adalah **akun produksi** &mdash; sudah membuat **2.310 tag** asli | Kredensial yang diserahkan ke Google adalah akun yang memiliki ribuan catatan produksi. |
| `guest` belum punya perangkat (`device_id` NULL) | Login peninjau akan menempelkan `guest` ke HP peninjau lewat `device-claim`. Bisa dilepas kembali, tapi harus diingat. |

**Saran:** buat akun khusus review, mis. `DEMO.PLAY`, dengan izin
`prepare` + `scan` saja, lalu hapus setelah aplikasi disetujui. Perintahnya:

```bash
curl -s -X POST "http://192.168.10.67/majsf_rest_api/api/sto/register" -H "Content-Type: application/json" -d '{"nik":"DEMO.PLAY","role":"counter","created_by":"F.9964","permissions":["prepare","scan"],"tim":"A"}'
```

Apa pun pilihannya, perlu diketahui: **peninjau menulis ke database
produksi.** Tidak ada server contoh. Sediakan waktu membersihkan beberapa
baris uji setelah review, dan pastikan ada event STO yang berjalan &mdash;
tanpa itu tombol Siapkan menolak bekerja dan aplikasi kembali tampak rusak.

---

## 1. Berkas yang sudah siap

| Hal | Keadaan |
|---|---|
| `applicationId` `com.maj.sto_prep` | siap &mdash; **permanen, tidak bisa diubah selamanya** |
| targetSdk (Flutter 3.38) | memenuhi syarat Play |
| Penandatanganan release | `android/key.properties` + keystore di luar repo |
| `allowBackup=false` | sudah |
| Cleartext dibatasi ke `192.168.10.67` | sudah, bukan pelanggaran |
| Kebijakan privasi | draf di `docs/kebijakan-privasi.html` &mdash; **harus di-host di URL publik** |

---

## 2. Naikkan versi tiap unggahan

`pubspec.yaml` baris `version:` &mdash; angka setelah `+` adalah
`versionCode` yang dipakai Play. Play menolak `versionCode` yang sudah
pernah diunggah, walau berkasnya berbeda.

```yaml
version: 1.0.0+1     # unggahan pertama
version: 1.0.1+2     # perbaikan berikutnya, dan seterusnya
```

---

## 3. Membangun berkas unggahan

Play menerima **Android App Bundle** (`.aab`), bukan APK:

```bash
flutter build appbundle --release
```

Hasilnya di `build/app/outputs/bundle/release/app-release.aab`.

> **Penting soal ANDROID_ID.** Play menandatangani ulang aplikasi dengan
> kunci Google (Play App Signing). Sejak Android 8, ANDROID_ID diturunkan
> dari kunci penandatangan &mdash; dan itulah kunci pemasangan NIK di
> aplikasi ini. Maka aplikasi dari Play punya ANDROID_ID **berbeda** dengan
> APK sideload yang sekarang terpasang, dan **tidak bisa dipasang sebagai
> pembaruan** di atasnya: handheld harus di-uninstall dulu, dan antrean
> kiriman yang belum sampai server ikut hilang.
>
> Seluruh pemasangan NIK yang sudah didaftarkan admin akan tidak dikenali
> sekaligus. Fitur klaim perangkat membereskannya sendiri (operator mengisi
> nama perangkat lalu login), tapi **lakukan perpindahan ini di luar jam
> pelaksanaan STO**, bukan di tengah shift.

---

## 4. Isian Play Console

### 4.1 Data safety

| Pertanyaan | Jawaban |
|---|---|
| Mengumpulkan data pengguna? | Ya |
| Data dienkripsi saat dikirim? | Ya (HTTPS di luar jaringan pabrik) |
| Pengguna bisa minta data dihapus? | Ya &mdash; lewat administrator perusahaan |
| Ada berbagi ke pihak ketiga? | Tidak |

Jenis data yang didaftarkan:

- **Personal info &rarr; User IDs** &mdash; NIK. Dikumpulkan, tidak
  dibagikan. Tujuan: *App functionality*. Wajib.
- **App activity &rarr; Other actions** &mdash; catatan hasil stock take.
  Tujuan: *App functionality*. Wajib.
- **Messages &rarr; Other in-app messages** &mdash; isi kotak pesan. Tujuan:
  *App functionality*. Opsional (hanya bila dipakai).
- **Device or other IDs** &mdash; ANDROID_ID untuk pemasangan perangkat.
  Tujuan: *App functionality*. Wajib.

**Jangan** mendaftarkan Location. Aplikasi tidak pernah membaca posisi.

### 4.2 Deklarasi izin lokasi

Play akan bertanya karena manifest memuat `ACCESS_FINE_LOCATION` dan
`ACCESS_COARSE_LOCATION`. Jawaban yang benar &mdash; dan jujur:

> Aplikasi tidak menggunakan lokasi pengguna dalam bentuk apa pun dan tidak
> pernah membaca koordinat. Izin lokasi dideklarasikan semata-mata karena
> Android mensyaratkannya untuk pemindaian perangkat Bluetooth pada
> Android 11 ke bawah, yang dipakai aplikasi untuk menyambung ke printer
> label termal saat mencetak tag inventaris. Tidak ada data lokasi yang
> dikumpulkan, disimpan, atau dikirimkan.

> **Cara menghindari pertanyaan ini sama sekali:** tambahkan
> `android:usesPermissionFlags="neverForLocation"` pada `BLUETOOTH_SCAN`
> lalu hapus kedua izin lokasi dari manifest. **Harus diuji di handheld
> sungguhan lebih dulu** &mdash; komentar di manifest menyebut plugin
> `blue_thermal_printer` mengembalikan daftar printer kosong tanpa izin itu.
> Jangan dilakukan tanpa pengujian: taruhannya printer di 30 handheld.

### 4.3 Akses aplikasi (kredensial peninjau)

Isi bagian *App access &rarr; All functionality requires special access*:

```
Nama pengguna : DEMO.PLAY          (atau: guest)
Kata sandi    : - (tidak ada, login hanya memakai NIK)

Petunjuk:
1. Saat aplikasi pertama dibuka, isi nama perangkat apa saja, mis. "REVIEW".
2. Pada layar login, masukkan NIK di atas, lalu tekan Masuk.
3. Aplikasi otomatis mendaftarkan perangkat ini dan langsung masuk.

Catatan: aplikasi memerlukan sambungan internet ke server perusahaan
(https://mspin.newarmada.biz). Fitur cetak memerlukan printer label termal
yang tidak tersedia di lingkungan pengujian; fungsi lain berjalan penuh.
```

### 4.4 Kategori & kelayakan

- Kategori: **Business**
- Content rating: kuesioner &rarr; tidak ada konten sensitif; hasilnya
  *Everyone* / 3+
- Target audience: **18+** (aplikasi kerja)
- Ads: **Tidak ada iklan**
- Government app: Tidak

### 4.5 Teks listing

**Nama aplikasi (maks 30):**
```
STO Mekar Armada
```

**Deskripsi singkat (maks 80):**
```
Aplikasi stock take opname untuk karyawan PT Mekar Armada Jaya.
```

**Deskripsi lengkap:**
```
STO adalah aplikasi internal PT Mekar Armada Jaya untuk pelaksanaan stock
take opname (perhitungan persediaan) di lingkungan pabrik.

Aplikasi ini hanya dapat digunakan oleh karyawan yang telah didaftarkan oleh
administrator perusahaan. Tanpa akun tersebut, aplikasi tidak dapat
digunakan.

Fitur:
- Menyiapkan dan mencetak tag inventaris ke printer label termal
- Memindai tag lewat kamera untuk mencatat jumlah barang
- Perhitungan ganda oleh dua tim, dengan hasil tiap tim tersimpan terpisah
- Pengajuan dan persetujuan pembatalan tag
- Riwayat lengkap: tag yang dibuat, dihitung, dan dibatalkan
- Kotak pesan antara operator lapangan dan administrator

Seluruh data tersimpan di server perusahaan dan tidak dibagikan kepada pihak
mana pun.
```

**Aset grafis yang wajib:**

| Aset | Ukuran |
|---|---|
| Ikon aplikasi | 512 &times; 512 PNG |
| Feature graphic | 1024 &times; 500 PNG/JPG |
| Tangkapan layar ponsel | minimal 2, sisi pendek &ge; 320 px |

---

## 5. Kebijakan privasi

`docs/kebijakan-privasi.html` siap pakai, tinggal **isi alamat surel yang
dipantau** di bagian Kontak. Berkas ini harus bisa dibuka publik &mdash;
peninjau Google membukanya dari luar jaringan pabrik.

Pilihan host, dari yang paling cepat:

1. **GitHub Pages** pada repo yang sudah ada &mdash; gratis, langsung
   publik, tidak menyentuh server siapa pun.
2. Direktori publik di `mspin.newarmada.biz` &mdash; perlu izin dev backend.

---

## 6. Jalur rilis yang disarankan

| Jalur | Review | Cocok untuk |
|---|---|---|
| **Internal testing** | praktis tanpa review | **Mulai dari sini.** Sampai 100 penguji lewat daftar surel, pembaruan otomatis, tidak terpengaruh masalah di bagian 0.1 |
| Closed testing | review ringan | Uji lebih luas sebelum produksi |
| Production | review penuh | Perlu bagian 0.1 dan 0.2 beres lebih dulu |

Untuk 30 handheld yang dipegang sendiri, **Internal testing sudah menjawab
seluruh kebutuhan** &mdash; pembaruan otomatis tanpa membagikan APK manual,
tanpa harus menunggu peninjau Google bisa masuk ke aplikasi.

---

## 7. Urutan kerja

1. [ ] Putuskan NIK uji (bagian 0.2) &mdash; disarankan `DEMO.PLAY`, bukan `guest`
2. [ ] Host `docs/kebijakan-privasi.html`, catat URL-nya
3. [ ] Siapkan ikon 512, feature graphic, dan 2 tangkapan layar
4. [ ] Daftar Play Console (biaya sekali seumur hidup, USD 25)
5. [ ] `flutter build appbundle --release`
6. [ ] Unggah ke track **Internal testing**, isi Data safety + deklarasi lokasi
7. [ ] Uji pasang dari Play di satu handheld &mdash; **pastikan ANDROID_ID
       berubah dan klaim perangkat berjalan** sebelum menyentuh handheld lain
8. [ ] Minta dev backend men-deploy kode server 67 ke mspin
9. [ ] Baru setelah itu, naik ke Production bila memang diperlukan
