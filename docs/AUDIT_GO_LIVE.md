# Audit menjelang go-live — Aplikasi STO

Tanggal: 11 September 2026. Cakupan: seluruh kode aplikasi Flutter (`lib/`,
95 berkas, ±25 ribu baris), sisi server `api/Sto.php` + `models/sto/` di
server 67, dan pemeriksaan langsung di dua handheld H10.

Hasil: `flutter analyze` bersih, **250 tes lolos**. Temuan di bawah diurutkan
dari yang paling berbahaya. Kolom *Keadaan* menyebut apa yang sudah
dikerjakan hari ini dan apa yang menunggu keputusan.

---

## KRITIS — perlu keputusan sebelum go-live

### K1. Tidak ada autentikasi, hanya identifikasi

Login memakai NIK saja, dan **setiap endpoint mempercayai parameter `nik`
apa adanya**. Siapa pun yang tahu NIK admin bisa memanggil `event-update`,
`user-update`, `cancel-approve` langsung dari alat apa pun — tanpa aplikasi,
tanpa perangkat terdaftar. Pemasangan perangkat hanya memagari *login di
aplikasi*, bukan API-nya.

Ini bukan bug; ini rancangan awal yang kini menanggung beban yang tidak
dimaksudkan untuknya.

| Keadaan | |
|---|---|
| Sudah dikerjakan | NIK admin tidak lagi tampil di layar operator (chat, pembatalan Tag OK). Ini menutup jalur bocor yang paling mudah, **bukan** kerentanannya. |
| Perlu keputusan | Pilih salah satu: (a) PIN 4–6 digit untuk akun admin saja, diperiksa server; (b) token sesi dari `login`, wajib di tiap permintaan admin. Keduanya perubahan server + aplikasi. **Rekomendasi: (a)** — kecil, cukup untuk akun yang berbahaya, operator tidak terganggu. |

### K1b. Tiga NIK admin tertanam di kode aplikasi — DIBUANG

Ditemukan saat merevisi penyegaran event: `['E.9948', 'F.9964', 'S.9390']`
ditanam di dua tempat (`admin_repository.syncEvents`, `device_repository.
pulihkanNamaDariServer`) sebagai "NIK cadangan" untuk memanggil endpoint
admin atas nama operator. Siapa pun yang membongkar APK mendapat tiga NIK
admin — dan dengan K1, itu kunci penuh.

Keduanya dibuang. `event-list` ternyata memang boleh dibaca semua user
terdaftar (diperiksa di server 67 dan sto-v2), jadi cadangannya tidak pernah
diperlukan. Pemulihan nama perangkat saat pasang ulang dihapus: mengetik
ulang nama sekali lebih murah daripada NIK admin di APK.

**Tindakan yang tetap perlu:** APK yang sudah dibagikan sebelum hari ini
memuat ketiga NIK itu. Anggap ketiganya sudah bocor — begitu K1 (PIN admin)
dipasang, kebocoran ini tidak lagi berarti.

### K2. Penjaga kepemilikan scan belum ada di sto-v2

Aturan "hanya pencatat yang boleh mengubah angkanya" hidup di server 67
(blok 13), **tidak** di sto-v2 — dan sto-v2 yang dipakai aplikasi secara
bawaan. Terbukti 8 Sep: uji tulis lewat sto-v2 menimpa hitungan produksi.

| Keadaan | |
|---|---|
| Perlu dev backend | Pasang tambalan yang sama di sto-v2 (`scan_tag_post`, sebelum blok `confirm`). |

---

## TINGGI — diperbaiki hari ini

### T1. Antrean kiriman mengulang selamanya item yang ditolak server

`SyncRepository.flush` memperlakukan **semua** kegagalan sama: item tetap di
antrean dan dicoba lagi tiap sinkron. Penolakan tetap dari server (403 angka
milik orang lain, 404 tag tidak ada, 400 tidak valid) tidak akan pernah
berubah — akibatnya lencana "belum sinkron" menyala **selamanya**, setiap
sinkron melaporkan "gagal 1", dan operator tidak tahu apa yang salah. Bila
item semacam ini menumpuk melewati 50, kiriman sah di belakangnya **tidak
pernah terkirim** (antrean diambil 50 tertua).

**Perbaikan:** 4xx (kecuali 408/429) dikeluarkan dari antrean, barisnya
ditandai GAGAL SINKRON supaya masih terlihat di riwayat, dan alasan server
ditampilkan apa adanya: *"1 kiriman ditolak server: Tag ini sudah discan tim
B oleh R.10664…"*. Kegagalan jaringan tetap dicoba lagi otomatis.

### T2. Status printer "Tersambung" yang basi

Bluetooth yang dimatikan tidak melewati satu pun method aplikasi, jadi layar
tetap "Tersambung" — tag dibuat, ditandai tercetak, kertas tidak keluar.
Diperbaiki 8 Sep: aliran keadaan dari plugin, pemeriksaan ulang sebelum
cetak, dan `ensureReady` melaporkan keadaan sesudahnya (bukan hasil
`connect()` yang bisa "berhasil" tanpa sambungan). Dua tes.

### T3. `dispose()` mencari provider lewat `context`

Melempar *"Looking up a deactivated widget's ancestor"* dan — yang penting —
**baris itu gagal dijalankan**, sehingga denyut penyegar chat tidak pernah
berhenti setelah layar ditinggalkan. Diperbaiki di chat (2 tempat) dan
dijadikan pola yang sama di dua layar Riwayat.

### T4. Galat teknis sampai ke layar operator

`PlatformException(read failed, socket might closed…)`, `DatabaseException(
UNIQUE constraint failed…)`, `Null check operator used on a null value` —
semuanya bisa muncul di snackbar apa adanya. Tidak menolong operator, tidak
menolong admin yang menerimanya lewat telepon.

**Perbaikan:** satu penerjemah (`PesanGalat.manusiawi`) di titik tunggal
`AppFeedback.error`, peringatan sinkron, dan layar galat rendering. Galat
yang sudah berbahasa manusia dibiarkan; yang teknis diganti kalimat yang
menyebut apa yang bisa dicoba. Lima tes.

### T5. Aplikasi mati putih bila database perangkat gagal dibuka

`AppDependencies.bootstrap()` yang melempar (migrasi gagal, penyimpanan
penuh) berarti layar putih tanpa penjelasan — handheld itu mati total sampai
ada yang menghapus datanya secara manual. **Perbaikan:** layar
*"Aplikasi tidak bisa dimulai"* dengan sebabnya dan langkah pemulihan
(semua data ada di server, hapus data aplikasi aman).

### T6. Operator tanpa izin area justru bebas ke semua area

Daftar area yang kosong dibaca "tanpa batas" - masuk akal untuk admin, tapi
untuk operator berarti akun yang **belum diatur admin paling leluasa**: bisa
mencari dan mencetak tag untuk area mana saja, dan seluruh master part ikut
tersalin ke handheld-nya. Pagar yang terbuka saat belum disetel adalah pagar
yang salah arah.

**Perbaikan:** kosong berarti kosong untuk operator (`tanpaAksesArea`).
Pencarian tidak dijalankan, master tidak diunduh, dropdown area Tag OK
kosong - dan layar menyebut sebabnya terang-terangan: *"Area kerja belum
diatur admin"*, bukan daftar kosong yang membuat operator menekan tombol
unduh berulang kali. Admin tetap bebas. Catatan: server `part-list` dan
`print-tag` tidak memeriksa area per user - penegakan ini masih di aplikasi,
dan baru bisa dipindah ke server setelah K1.

---

## SEDANG — diperbaiki hari ini

| # | Temuan | Perbaikan |
|---|---|---|
| S1 | Dua tombol di Setting > Printer dalam `Row` — meluber pada layar sempit dengan huruf sistem diperbesar | `Wrap`, tombol kedua turun baris |
| S2 | Label jadwal event di kartu Setting > Event tanpa `Flexible` | `Flexible` + ellipsis |
| S3 | Kepala beranda meluber 6–7 px (dua kali) karena tinggi dihitung terpisah dari yang digambar | satu sumber angka + `FittedBox` sebagai jaring |
| S4 | Server 67 tidak menegakkan `allow_print` — tag tetap dicetak saat admin menutup pencetakan | penjaga di `tentukan_event()`, blok 18 |
| S5 | `event-list`/`event-update` server 67 belum kenal `allow_print`/`total_tim` | disamakan dengan sto-v2, blok 17 |
| S6 | Widget teks berjalan: `late final` controller dibuat saat `dispose` → galat; teks terpotong selebar ruang | dibuat di `initState`; `OverflowBox` |

---

## RENDAH — dicatat, tidak diubah

| # | Temuan | Catatan |
|---|---|---|
| R1 | **Ping-pong klaim perangkat.** Dua perangkat yang memakai satu NIK saling mengeluarkan tiap 15 detik (klaim → refresh 403 → logout → login → klaim). | Konsekuensi langsung dari klaim mandiri yang diminta. Jejaknya ada di `device-claims`. Tidak ada obat tanpa K1. |
| R2 | `ACCESS_FINE_LOCATION` di manifest | Dibutuhkan plugin printer di Android ≤11. Aplikasi tidak membaca lokasi. Hanya jadi urusan bila ke Play Store. |
| R3 | `enableOnBackInvokedCallback` belum disetel | Peringatan Android 13+, tidak berdampak fungsi. |
| R4 | Sesi menanyai `/login` tiap 15 detik per handheld | 30 handheld ≈ 2 permintaan/detik. Ringan. Hanya 403/404 yang mengeluarkan sesi; gangguan jaringan tidak. |
| R5 | `scan-history` mengirim dua baris untuk tag mode 1 tim | Perilaku sto-v2 yang disengaja (didokumentasikan). Aplikasi menampilkannya apa adanya. |

---

## Yang diperiksa dan BERSIH

- Semua endpoint admin di server 67 berpagar `is_admin` (17 endpoint diperiksa otomatis).
- Semua query mentah memakai binding `?` atau `(int)`/`escape()` — tidak ada penyusupan SQL.
- Tidak ada kata sandi/token/kunci tertanam di kode aplikasi.
- Tidak ada `print()`/`debugPrint()` yang membocorkan data ke logcat selain penangkap galat global.
- Semua `Timer.periodic` dan `StreamSubscription` dibatalkan di `dispose`.
- Penjaga ketukan ganda ada di cetak (`_printing`), buat tag (`_generating`), scan (`_handling`).
- Lalu lintas polos (HTTP) hanya ke `192.168.10.67`; selain itu ditolak Android.
- `allowBackup=false` — data tidak ikut cadangan cloud.
- Tag hanya ditandai tercetak **setelah** printer menjawab; kertas habis dilaporkan sebagai gagal, bukan sukses.

---

## Urutan yang disarankan sebelum go-live

1. **Putuskan K1** (PIN admin). Tanpa ini, semua pengaman lain bisa dilewati oleh siapa pun yang tahu satu NIK admin.
2. Minta dev sto-v2 memasang **K2** (penjaga kepemilikan scan).
3. Build dari kode ini (semua perbaikan T1–T5, S1–S6 sudah di dalamnya), uji di satu handheld: matikan Bluetooth saat di beranda → kartu printer harus berubah sendiri.
4. Pastikan **event yang benar dibuka** dan `allow_print = 1` sebelum shift pertama.
