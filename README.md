# STO Preparation (sto_prep)

Aplikasi Android untuk persiapan **Stock Taking Opname (STO)** di PT. Mekar Armada Jaya
Plant Tambun. Target perangkat: **Blueprint MPOS 332** (handheld Android dengan
printer termal internal 58mm).

Alur pemakaian:

```
Siapkan : Login (NIK) -> Cari Job/Part -> Jumlah tag -> Preview + cetak otomatis
Scan    : Scan QR tag -> detail part tampil -> isi qty -> POST {nik, tag_no, tim, qty}
Batal   : Scan tag (punya sendiri / cetakan orang lain) -> ajukan -> admin menyetujui
          (semua pembatalan lewat pengajuan, admin sekalipun)
```

Tiga kotak menu utama di halaman awal - **Siapkan**, **Scan**, **Batal** -
dibuat setara bentuk dan ikonnya, dan hanya muncul bila haknya diberikan
admin. Kartu **Ringkasan hari ini** pun mengikuti hak itu: tag discan (akses
scan), tag dicetak (akses siapkan), dan tag batal (akses batal). Menu
**Riwayat Scan** berisi hasil hitung, **Setting** hanya untuk admin.

## Login dikunci ke perangkat (pairing)

Operator hanya bisa login di perangkat yang NIK-nya sudah dipasangkan admin.
Admin bebas login di perangkat mana pun supaya bisa mendaftarkan perangkat baru
dan melepas pemasangan saat event selesai.

**MAC address sengaja tidak dipakai**: sejak Android 6 (Wi-Fi/Bluetooth) dan
Android 10 (nomor seri), aplikasi biasa selalu menerima `02:00:00:00:00:00`
kecuali dipasang sebagai Device Owner lewat MDM. Penggantinya `ANDROID_ID`
(dibaca lewat MethodChannel `sto_prep/device` di MainActivity): tetap sama
setelah restart maupun install ulang selama APK ditandatangani kunci yang sama,
dan berubah hanya bila perangkat di-factory reset.

Admin memberi tiap perangkat **nomor aset perusahaan** (mis. `016-HSS-TBN`) agar
mudah dikenali di lapangan, lalu memasangkan satu atau beberapa NIK (mis. shift
pagi & malam). Menu: **Setting > Perangkat & pairing** - di sana juga ada
tombol *Lepas semua* untuk dipakai saat event STO selesai, dan sakelar
menonaktifkan perangkat.

Pemasangan dicabut = sesi yang masih tersimpan ikut gugur pada pembukaan
aplikasi berikutnya.

## Peran

| | Operator | Admin |
| --- | --- | --- |
| Siapkan & cetak tag | ya | ya |
| Scan tag | ya | ya |
| Batalkan tag | **mengajukan** (tag yang sudah tercetak) | juga **mengajukan**, lalu **menyetujui / menolak** di tab Pengajuan |
| Menu Setting (event, user, tim, perangkat, server, data) | tidak | ya |
| Menu yang muncul di halaman utama | sesuai izin `prepare` / `scan` / `cancel` dari admin | semuanya |
| Part yang terlihat | hanya area yang diberikan admin | semua area |

Pengaturan printer sengaja tetap bisa diakses operator lewat kartu Printer di
halaman utama - urusan perangkat, bukan urusan wewenang.

## Aturan bisnis yang dijaga aplikasi

| Aturan | Cara dijaga |
| --- | --- |
| Jumlah cetak = jumlah **tag unik**, bukan copy | Nomor urut dipesan per batch (`sequence/reserve`), tiap lembar dapat `tag_no` sendiri |
| Tidak boleh ada nomor tag yang tidak tercetak | Halaman preview langsung mencetak begitu terbuka (tanpa konfirmasi); tag yang gagal keluar tetap berstatus BELUM TERCETAK dan bisa diulang |
| Tag hanya dibuat pada periode resmi | Wajib ada event STO berstatus BUKA yang mencakup hari ini; `event_id`-nya ikut disimpan pada tiap tag |
| Tidak ada tag batal tanpa jejak persetujuan | Siapa pun yang scan di menu Batal - operator maupun admin - menghasilkan pengajuan (status DIAJUKAN BATAL); admin menyetujui atau menolaknya di tab Pengajuan |
| Tag yang batal tidak boleh ikut dihitung | Halaman Scan menolak tag berstatus DIAJUKAN BATAL / DIBATALKAN sebelum kolom qty terbuka, dan `CountRepository.submit` menolaknya sekali lagi |
| Operator hanya menyiapkan area miliknya | Pencarian part memakai `WHERE UPPER(area) IN (...)` sesuai izin dari admin |
| Aplikasi hanya jalan di perangkat resmi | Login operator wajib lolos pemasangan NIK <-> ANDROID_ID perangkat (tabel `devices`) |
| Satu tag hanya boleh dicetak **satu kali** | Kolom `tag_no` UNIQUE + `UPDATE ... WHERE status='draft'` di `TagDao.markPrinted`; tombol cetak mati dan tag diberi watermark "SUDAH DICETAK" |
| Operator melihat hasil sebelum mencetak | Halaman preview merender `LabelDocument` yang sama persis dengan yang dikirim ke printer |
| Mispart harus bisa dibatalkan | Tombol Batalkan (per tag / satu batch) dengan pilihan alasan; status jadi `cancelled` dan tidak bisa dicetak lagi |
| Tag yang sudah tersebar di lapangan bisa dibatalkan cepat | Kotak **Batal**: QR discan (termasuk tag cetakan perangkat lain), lalu diajukan/dibatalkan sesuai peran |
| Satu tim hanya boleh satu angka per tag | Kunci `tag_no + tim` pada tabel `sto_counts`; tim lain tetap boleh menghitung tag yang sama |
| Nama tim tidak boleh salah ketik | Tim dipilih dari daftar milik admin (tabel `teams`, bawaan A dan B), bukan diketik bebas |
| Koreksi angka hanya oleh pencatatnya | Baris hasil hitung menyimpan NIK; scan ulang oleh NIK lain di tim yang sama ditolak |
| Tetap jalan saat jaringan mati | Cache sqflite + outbox; nomor urut fallback lokal (prefix `L`) yang ditandai untuk rekonsiliasi |

Skenario kegagalan yang mungkin terjadi di lapangan - kertas habis, Bluetooth
putus, tag rusak, sampai wewenang pembatalan - beserta cara aplikasi
menanganinya ada di [docs/SKENARIO_CETAK.md](docs/SKENARIO_CETAK.md).

## Status API

**Seluruh endpoint masih menyusul.** Aplikasi memakai `MockStoApi` (data part
contoh + login bebas) sehingga alur bisa diuji penuh sekarang.

Saat API siap:

1. Buka **Setting > Server & API**, pilih alamat server yang dipakai.
2. Sesuaikan path endpoint di `lib/data/remote/api_endpoints.dart` bila berbeda.
3. Kontrak request/response ada di [`docs/API_CONTRACT.md`](docs/API_CONTRACT.md),
   termasuk usulan tabel `sto_tag` & `sto_sequence`.

## Menjalankan

```bash
flutter pub get
flutter run                 # pasang ke perangkat MPOS / HP Android
flutter build apk --release # rilis
```

Di emulator atau HP tanpa printer internal, aplikasi memakai printer simulasi sendiri
(hasil cetak ditulis ke log, alur lain tetap sama).

Pengujian:

```bash
flutter test                     # unit + golden test layout tag
flutter test --update-goldens    # setelah sengaja mengubah layout kertas
```

## Struktur

```
lib/
  core/          konfigurasi, tema, util, widget bersama, perakitan dependensi
  data/
    models/      AppUser, PartItem, StoTag, PrintBatch, StoEvent, StoCount,
                 StoDevice
    local/       sqflite (parts, tags, batches, outbox) + SharedPreferences
    remote/      ApiClient, kontrak StoApi, HttpStoApi, MockStoApi, ApiGateway
    repositories/ auth, part (cache-first), tag (sumber kebenaran status), sync
  services/
    printer/     LabelDocument -> LabelBuilder -> Bluetooth/Mock PrinterService
    sequence/    pemesanan nomor urut (server + fallback lokal)
    device/      identitas perangkat (ANDROID_ID) untuk pairing
    feedback/    bunyi & getar
  state/         provider: session, printer, prepare, history, settings
  features/      splash, auth, home, search, prepare, preview, scan (hitung),
                 cancel (batal tag), history (riwayat scan),
                 settings (termasuk CRUD event & user untuk admin)
```

### Isi tag yang dicetak

Judul `PT. MEKAR ARMADA JAYA` + `TAG STO - 02/09/2026 10.50 AM` (waktu cetak),
nomor tag besar, lalu PART NO, JOB NO, NAMA, CUST, AREA, **STATUS (FP/WIP)**,
**DICETAK (NIK)**, dan CATATAN bila diisi. Di bawah QR ada empat kotak isian
manual 2x2 - Nama Hitung A / Nama Hitung B di baris atas, Nama Catat A /
Nama Catat B di baris bawah (tim A dan tim B, sesuai hitungan ganda). **Tag berakhir tepat di kotak itu** - tidak ada blok apa pun di
bawahnya.

Empat kotak isian itu **dicetak sebagai gambar** (`BoxGridBitmap` -> PNG ->
`printImageBytes`, jalur yang sama dengan QR) supaya garisnya menyambung seperti
di preview; printer termal hanya punya karakter teks, jadi versi `+ - |`
keluar sebagai garis putus-putus. Bila menggambar/mengirim gambar gagal,
aplikasi otomatis memakai versi teks agar tag tetap keluar.

### Kenapa `LabelDocument`?

Layout tag dibuat sekali sebagai daftar elemen netral (`LabelText`, `LabelKeyValue`,
`LabelDivider`, `LabelQr`, `LabelFeed`). Elemen itu dipakai dua kali:

- `LabelPaper` (layar) - preview yang dilihat operator,
- `BluetoothPrinterService` - diterjemahkan jadi perintah ESC/POS.

Jadi preview bukan tiruan manual: kalau layout berubah, keduanya ikut berubah.

## Setting (khusus admin)

- **Event STO** - CRUD periode: nama, tanggal mulai/selesai, area yang dihitung,
  status buka/tutup. **Hanya satu event yang boleh berjalan**: membuka event
  baru saat masih ada yang berjalan akan menanyakan lebih dulu, lalu menutup
  yang lama begitu admin menegaskan. Event yang sudah dipakai tag tidak bisa dihapus (tutup saja),
  supaya jejak cetak tetap utuh.
- **User & izin** - CRUD user: NIK, **tim** (A atau B - enum kolom
  `users.tim` di server, bukan daftar yang bisa ditambah), peran
  (admin/operator), **hak akses menu** (siapkan / scan / batal), area yang boleh
  disiapkan (boleh lebih dari satu: **IFRM, PRESS, IFPP, WELD, IFPD** - sama
  persis dengan master server), dan status aktif. Akun STO dikenali dari NIK saja - tabel `users`
  di server tidak punya kolom nama, departemen, maupun seksi, jadi form ini pun
  tidak menanyakannya. Tim wajib diisi sebelum user itu bisa mencatat hasil
  hitung. Admin terakhir tidak bisa dihapus atau diturunkan perannya.
- **Perangkat & pairing** - daftar perangkat beserta nomor aset dan NIK yang
  terpasang; pasang/lepas NIK, lepas semua saat event selesai, dan nonaktifkan
  perangkat yang hilang atau diperbaiki.
- Sisanya seperti sebelumnya: alamat server, cache master part, dan hapus
  data lokal.

Data contoh (master part, periode contoh, tag DEMO) otomatis **dibuang** begitu
server. Akun tidak ikut dibuang: di situlah hak akses menu tersimpan.

Perangkat baru otomatis disemai admin bawaan (`E.9948`, `A.10525`) dan satu
periode STO bulan berjalan, supaya tidak ada perangkat yang terkunci tanpa admin
atau tanpa event.

## Scan tag (menghitung isi)

Menu **Scan Tag** dipakai saat pelaksanaan STO:

1. QR tag discan (kamera, scanner fisik, atau ketik manual);
2. aplikasi menampilkan detail part - dari database lokal bila tagnya dicetak
   di perangkat ini, atau dari server bila dicetak perangkat lain (sementara
   dilayani data tiruan sampai API siap);
3. operator mengisi **qty**; tim diambil otomatis dari data user;
4. hasilnya tersimpan lokal dan diantre sebagai `POST { nik, tag_no, tim, qty }`.

Aturannya: **tim lain boleh** menghitung tag yang sama (baris terpisah per tim),
tetapi di dalam satu tim hanya pencatat pertama yang boleh mengoreksi angkanya.
Semua hasil hitung tampil di menu **Riwayat Scan** lengkap dengan tim, waktu,
dan status pengiriman.

## Batal tag (kotak menu tersendiri)

Kotak **Batal** punya dua tab:

- **Scan Tag** - tombolnya *Ajukan Pembatalan* untuk semua orang, admin
  sekalipun; setelah diajukan aplikasi langsung pindah ke tab Pengajuan.
  Dibuat begitu supaya tiap tag batal punya jejak lengkap siapa mengajukan dan
  siapa menyetujui. Tag yang dicetak perangkat lain ikut bisa diproses:
  detailnya diambil dari server lalu dicatat lokal sebagai tag luar
  (`batch_id = EXTERNAL`) supaya alurnya sama.
- **Pengajuan** - daftar permintaan yang menunggu; admin menyetujui atau
  menolak di sini.

Status lain yang mungkin muncul:
- tag belum tercetak -> ditolak dengan penjelasan;
- tag sudah dibatalkan -> hanya ditampilkan statusnya;
- tag tidak ada di perangkat -> diberitahu bahwa tag itu dicetak dari
  perangkat lain.

Ada kolom ketik manual di bawah pemindai: dipakai bila kamera bermasalah, dan
sekaligus menampung perangkat yang punya scanner laser bawaan (input keyboard).
Pembacaan kode ditangani `ScanCode.extractTagNo` sehingga spasi, huruf kecil,
atau awalan tambahan tetap terbaca.

## Printer

`PrinterService` adalah abstraksi; implementasi saat ini:

- `BluetoothPrinterService` - ESC/POS via Bluetooth SPP (`blue_thermal_printer`).
  Printer internal MPOS biasanya muncul sebagai perangkat bonded bernama
  *InnerPrinter* / *BluePrint* / *MPOS* dan otomatis ditaruh paling atas daftar.
- `MockPrinterService` - simulasi untuk pengembangan.

Bila Blueprint menyediakan SDK khusus (AIDL/JNI), cukup tambah implementasi baru
`PrinterService` dan daftarkan di `AppDependencies` - halaman preview tidak berubah.

Izin Android: `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, dan **`ACCESS_FINE_LOCATION`
tanpa `maxSdkVersion`** - blue_thermal_printer 1.2.3 menolak membaca daftar
printer di Android 12+ bila ketiganya belum granted (dan Future-nya menggantung
karena requestCode plugin tidak cocok dengan callback-nya), jadi izin diminta
lebih dulu di `BluetoothPrinterService.ensurePermissions()`. Ditambah `INTERNET`,
`VIBRATE`, dan `usesCleartextTraffic` untuk server internal http.

## Caching

| Lapis | Isi | Catatan |
| --- | --- | --- |
| sqflite `parts` | master part/job + kolom `search_index` | TTL 12 jam, pencarian offline |
| sqflite `tags` / `batches` | seluruh tag beserta status cetak/batal | sumber kebenaran, tidak ikut terhapus saat cache part dibersihkan |
| sqflite `outbox` | antrian kirim ke server | dihapus hanya setelah server membalas sukses |
| SharedPreferences | sesi login, riwayat NIK & pencarian, setting printer/kertas/area | ringan, dibaca saat splash |

## Aset

Diambil dari aset korporat yang sudah dipakai aplikasi MAJ lain
(`inventory-dashboard-vue3` dan aplikasi Flutter `sto`):

- `assets/images/logo-maj.png` - logo pada splash & login
- `assets/images/icon-maj.png` - ikon launcher (via `flutter_launcher_icons`) & header
- `assets/images/logo-print.png`, `logo-white.png`, `logo-slogan.png` - cadangan
  (mis. bila header struk nanti ingin memakai logo bitmap)
- `assets/sounds/beep.mp3`, `succeed.mp3` - umpan balik cetak

## Yang belum dikerjakan (menunggu keputusan/API)

- Endpoint asli + autentikasi token (sementara NIK saja).
- Pemindaian barcode part memakai scanner bawaan MPOS (bila diperlukan).
- Sinkronisasi otomatis terjadwal (saat ini manual lewat tombol Sinkron).
- Cetak ulang tag rusak: sengaja **tidak** disediakan; prosedurnya membatalkan
  tag lama lalu membuat tag baru agar jejak audit tetap utuh.
