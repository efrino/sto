# Skenario kegagalan & penanggulangannya

Daftar hal yang bisa salah saat pelaksanaan STO, apa akibatnya, dan bagaimana
aplikasi menanganinya. Ditulis untuk dipakai dua arah: sebagai catatan teknis
saat menambah fitur, dan sebagai bahan SOP untuk operator di lapangan.

Tanda:

- ✅ sudah dijaga aplikasi
- 🟡 dijaga sebagian - sisanya bergantung pada SOP / mata operator
- ❌ belum ada penanganannya

---

## Bagian 1 - Saat mencetak tag

### 1.1 Kertas habis di tengah pencetakan 🟡

**Gejala.** Printer berbunyi normal, aplikasi melapor "berhasil", tetapi tidak
ada lembar yang keluar - atau keluar separuh lalu berhenti.

**Kenapa berbahaya.** Ini kasus **cetak senyap**: `writeBytes` yang sukses
hanya berarti byte-nya masuk ke soket Bluetooth, **bukan** berarti tinta
membekas di kertas. Tanpa penjagaan, tag berpindah ke status SUDAH CETAK
padahal wujud fisiknya tidak ada. Akibatnya nomor tag itu hangus: aturan
"satu tag hanya boleh dicetak sekali" membuatnya tidak bisa dicetak ulang,
dan saat rekap nanti tag itu tercatat ada tetapi tidak pernah bisa dihitung.

**Penanggulangan sekarang.**

1. Sebelum tiap lembar, aplikasi menanyakan keadaan kertas ke printer dengan
   perintah real-time ESC/POS `DLE EOT 4` (`0x10 0x04 0x04`). Jawabannya satu
   byte: bit 5/6 menyala = kertas habis, bit 2/3 = hampir habis.
2. Bila **kertas habis**, pencetakan dihentikan **sebelum** tag ditandai. Tag
   yang belum keluar tetap berstatus BELUM CETAK, jadi setelah kertas diganti
   tinggal menekan Cetak lagi - tidak ada nomor yang hangus.
3. Bila printer **tidak menjawab** (banyak printer internal handheld memang
   bisu), statusnya `unknown`. Aplikasi tidak berpura-pura aman.
4. **Ceklis di akhir tiap batch.** Handheld menahan antrean cetak saat kertas
   habis: byte-nya sudah masuk - aplikasi menganggap sukses - tetapi
   lembarannya baru keluar setelah kertas diganti, atau tidak keluar sama
   sekali. Tidak ada sinyal yang bisa dibaca untuk itu, jadi operator
   dihadapkan pada daftar tag yang barusan dicetak dan mencentang yang tidak
   keluar / tidak terbaca. Yang dicentang **langsung masuk daftar pengajuan
   pembatalan**, tinggal disetujui admin di menu Batal. Lembarnya tidak
   dicetak ulang - nomor tag hanya boleh sekali cetak.
5. Keadaan kertas terakhir ikut ditampilkan di bar ringkasan halaman preview.

**Jalur printer.** Printer 57 mm handheld ini sebenarnya duduk di `/dev/ttyS1`
dan dibungkus service sistem pabrikan (`recieptservice.com.recieptservice`,
SRPrinter); "InnerPrinter" yang muncul di daftar Bluetooth hanya jembatan SPP.
Jalur service pabrikan sudah disiapkan lengkap (AIDL + `VendorPrinterService`),
tetapi di unit ini service-nya **menolak permintaan sambung** - tanda susunan
AIDL-nya berbeda dari yang bisa dibaca dari APK-nya yang sudah di-obfuscate.
Karena itu aplikasi tetap memakai jalur Bluetooth ke `00:11:22:33:44:55`
(InnerPrinter), jalur yang sejak awal terbukti mencetak. Begitu pabrikan
mengirim berkas AIDL resminya, timpa `PrinterInterface.aidl` lalu kembalikan
pemilihan di `_printerPerangkat()`.

**Sisa risikonya.** Pada printer bisu, satu-satunya sensor adalah mata
operator. Karena itu SOP-nya: **jangan mulai satu batch besar dengan sisa
kertas menipis** - ganti dulu. Operator juga sebaiknya membandingkan jumlah
lembar di tangan dengan angka "tercetak" di bar ringkasan sebelum keluar dari
halaman preview.

### 1.2 Bluetooth putus di tengah batch ✅

Tag yang sedang dikirim melempar `PrinterException`, perulangan berhenti, dan
tag itu **tidak** ditandai tercetak. Tag berikutnya tetap BELUM CETAK. Setelah
printer tersambung lagi, tombol Cetak melanjutkan dari tag yang tertinggal.

### 1.3 Aplikasi tertutup / HP mati saat mencetak ✅

Status tag ditulis ke sqflite **setelah** printer melapor sukses, satu per
satu. Jadi kondisi terburuknya adalah satu lembar yang keluar tapi belum
sempat tercatat - tag itu masih BELUM CETAK dan akan dicetak lagi. Ini
disengaja: lebih baik satu lembar dobel (yang kelihatan mata dan bisa dibuang)
daripada satu nomor hangus tanpa wujud.

### 1.4 Hasil cetak pudar / tidak terbaca 🟡

Kepala termal kotor atau baterai lemah membuat barcode tidak bisa discan
padahal tag-nya sah. Tidak ada sensor untuk ini. Penanggulangannya di alur
kerja: **operator melihat preview sebelum kertas keluar**, dan tag yang
tercetak buruk dibatalkan lewat Ajukan Pembatalan dengan alasan "Kertas rusak /
hasil cetak tidak terbaca" - alasan itu memang sudah disediakan di dialog.

Untuk keadaan darurat, nomor tag juga dicetak sebagai teks besar di atas QR,
sehingga masih bisa diketik manual di kolom "atau ketik nomor tag".

### 1.5 Operator menekan Cetak dua kali ✅

`TagDao.markPrinted` memakai `UPDATE ... WHERE status = 'draft'`, jadi
perubahan status hanya berlaku sekali. Tombol cetak per tag juga mati begitu
statusnya SUDAH CETAK, dan lembar preview diberi cap air "SUDAH DICETAK".

### 1.6 Printer belum tersambung saat preview terbuka ✅

Preview mencoba menyambungkan printer internal otomatis. Kalau gagal, operator
ditawari membuka pengaturan printer; tidak ada tag yang ditandai tercetak
selama itu.

---

## Bagian 2 - Nomor tag & data

### 2.1 Jaringan mati saat membuat tag ✅

Nomor urut diambil dari counter lokal dan diberi tanda `offlineSequence` serta
prefix khusus, lalu ikut antre di outbox untuk direkonsiliasi saat server bisa
dihubungi. Tag tetap bisa dicetak dan dipakai menghitung.

### 2.2 Dua perangkat membuat nomor yang sama 🟡

Kolom `tag_no` UNIQUE di perangkat, dan `sto_data.id_tag` UNIQUE di server.
Saat sinkron, tag bernomor bentrok akan ditolak server. Ini belum diuji
ujung-ke-ujung karena endpoint pembuatan tag di server (`print-tag`) memberi
nomornya sendiri - lihat catatan di `API_CONTRACT.md` BAGIAN B nomor 2.

### 2.3 Event STO ditutup di tengah pekerjaan ✅

Pembuatan tag baru wajib punya event berstatus BUKA yang mencakup hari ini.
Tag yang terlanjur dibuat tetap membawa `event_id`-nya, jadi jejaknya utuh.

### 2.4 Tag hilang / rusak di lapangan 🟡

Tidak bisa dicetak ulang - itu memang aturannya, supaya tidak ada dua lembar
dengan nomor sama beredar. Prosedurnya: ajukan pembatalan tag itu, lalu buat
tag baru untuk part yang sama.

### 2.5 Sambungan ke server terputus tepat saat dipakai ✅

**Gejala.** Halaman admin menampilkan *"Connection closed before full header was
received"* padahal URL yang sama dibuka di browser berhasil.

**Sebabnya.** Apache di server memakai `KeepAlive On` dengan
`KeepAliveTimeout 5`. Aplikasi handheld jarang mengirim permintaan, jadi
sambungan yang disimpan `package:http` untuk dipakai ulang sudah ditutup server
lebih dulu - permintaan berikutnya masuk ke soket yang sudah mati. Browser dan
`curl` tidak kena karena selalu membuka sambungan baru.

**Penanggulangan.** Semua permintaan aplikasi dikirim dengan `Connection: close`
sehingga tidak pernah mewarisi sambungan basi. Bila tetap terputus, **GET**
diulang sekali (aman, tidak mengubah apa pun) sedangkan **POST tidak pernah
diulang** - mengirim ulang bisa berarti dua tag tercetak atau dua user
terdaftar; lebih baik operator melihat pesan gagal lalu menekan sendiri.

---

## Bagian 3 - Saat menghitung (scan)

### 3.1 Tag yang sudah dibatalkan ikut discan ✅

Ditolak dua lapis: halaman Scan menolak sebelum kolom qty terbuka, dan
`CountRepository.submit` menolaknya sekali lagi. Pesannya menyebut alasannya
(sudah dibatalkan / sedang diajukan batal).

### 3.2 Satu tag dihitung dua tim ✅ (memang boleh)

Tim A dan tim B menghitung tag yang sama sebagai dua catatan terpisah - itu
gunanya hitungan ganda. Di server keduanya menempati satu baris `sto_data`
(`qty_a` dan `qty_b`).

### 3.3 Orang lain di tim yang sama mengoreksi angka ✅

Ditolak: dalam satu tim hanya pencatat pertama yang boleh mengubah angkanya.

### 3.4 Hasil hitung nol dianggap "belum discan" ✅

Penanda "sudah discan" adalah kolom waktu (`updated_a`/`updated_b`) yang
terisi, **bukan** `qty > 0`. Rak kosong yang benar-benar nol tetap tercatat
sebagai sudah dihitung dan tidak bisa tertimpa diam-diam.

### 3.5 Hasil hitung belum terkirim ke server ✅

Semua hasil masuk outbox dan ditandai BELUM SINKRON di Riwayat Scan; jumlah
antreannya tampil di kartu ringkasan halaman utama dengan tombol kirim ulang.

---

## Bagian 4 - Perangkat & wewenang

### 4.1 Aplikasi dipakai di HP pribadi ✅

Operator hanya bisa login di perangkat yang NIK-nya sudah dipasangkan admin
(ANDROID_ID + nomor aset). Admin bebas login di mana saja supaya tidak ada
perangkat yang terkunci tanpa admin.

### 4.2 Operator membatalkan tag sendiri ✅

Semua pembatalan - siapa pun yang scan, admin sekalipun - masuk daftar
pengajuan dulu. Hanya admin yang bisa menyetujui atau menolak, dan aturan itu
ditegakkan di repository, bukan sekadar menyembunyikan tombol.

### 4.3 Perangkat hilang saat event masih berjalan 🟡

Admin bisa menonaktifkan perangkat atau melepas NIK dari daftar perangkat di
aplikasi. Di sisi server, melepas pairing belum bisa - lihat `API_CONTRACT.md`
BAGIAN B nomor 8.

### 4.4 Siapa pun bisa mendaftarkan dirinya sebagai admin ❌

`POST /sto/register` di server belum punya auth dan menerima `role` bebas.
Siapa pun di jaringan bisa membuat akun ber-role `admin` lalu memakai sepuluh
endpoint admin. Penanggulangan yang disarankan: kunci `register` supaya hanya
admin yang boleh memanggilnya, kecuali saat tabel `users` masih kosong
(bootstrap admin pertama), dan batasi nilai `role`.


## Tag yang tidak keluar dari printer

Sejak 3 Sep 2026 keadaan cetak tiap tag disimpan di server (`sto_data`:
`print_status`, `print_error`, `printed_at`), bukan di perangkat:

- cetak berhasil -> `POST print-status` status `printed`;
- kertas habis / printer menolak -> status `error` beserta alasannya, dan
  status lokalnya sengaja tetap BELUM CETAK sehingga tag yang sama akan
  dicetak ulang;
- keduanya lewat outbox, jadi jaringan yang mati hanya menunda, tidak
  menghilangkan.

Halaman **Riwayat Cetak** membaca `print-history` (termasuk `summary` untuk
kartu ringkasan). Tag yang tertinggal dicetak ulang otomatis begitu printer
normal, memakai nomor tag yang sama - bukan nomor baru. Yang tetap tertinggal
bisa dibatalkan admin langsung dari halaman itu.


## Kotak isian yang hilang dari kertas

Cetakan 3 Sep 2026 keluar lengkap sampai QR, tetapi kotak isian (Nama Hitung /
Nama Catat A-B) tidak ada - padahal ada di preview. Sebabnya
`printImageBytes` milik plugin: perintahnya diterima printer ini tanpa error,
tetapi tidak menghasilkan apa pun di kertas, sehingga jalur teks cadangan pun
tidak pernah dipakai (tidak ada kesalahan yang bisa ditangkap).

Sejak itu kotak isian dikirim sebagai raster ESC/POS `GS v 0` lewat
`writeBytes` - jalur yang sama dengan teks tag, yang memang terbukti jalan.
Urutan cadangannya: raster -> `printImageBytes` -> teks `+ - |`.


## Jarak kertas antar tag

`paperCut()` milik plugin mengirim `GS V 66 0` - "maju ke posisi potong lalu
potong". Printer handheld ini tidak punya pisau, tetapi tetap memajukan kertas
sejauh posisi potong bawaannya. Sisa kertas itu muncul DUA kali: sebagai ekor
tag yang sedang dicetak, lalu sebagai kepala kosong tag berikutnya (kertas
antara kepala cetak dan bibir sobek memang tertinggal di dalam printer).

Tag sekarang berhenti tepat di kotak isian (tidak ada `LabelFeed` lagi di
`LabelBuilder`); jarak maju kertasnya sepenuhnya urusan printer, dikirim lewat
`ESC J n` (n dalam titik, 8 titik = 1 mm).

**Kalibrasi dot-ke-mm ternyata tidak seragam antar unit printer klon** -
tebakan 90 titik lalu 32 titik dua-duanya masih dilaporkan "boros" di
handheld yang dipakai untuk uji coba. Karena itu jarak ini TIDAK LAGI
konstanta tetap di kode:

- **Setting > Printer > "Jarak sobek kertas"** - slider 0-160 titik (0-20 mm)
  + tombol **"Uji jarak ini"** yang mengirim satu baris penanda pendek + jarak
  terpilih, tanpa mencetak tag utuh. Operator bisa menggeser dan menekan uji
  berkali-kali sampai pas, tanpa build ulang aplikasi maupun memboroskan
  kertas untuk tag sungguhan.
- Nilainya disimpan per perangkat (`PrefsStore.paperFeedDots`) dan dipakai
  otomatis pada tiap `printTag` berikutnya.
- `feedAfterTagDots` di `app_config.dart` tinggal jadi nilai AWAL sebelum
  operator pernah mengaturnya - bukan lagi satu-satunya sumber kebenaran.

Bila nanti dapat kalibrasi resmi dari pabrikan printer, angkanya tinggal
disetel lewat slider itu - tidak perlu menyentuh kode lagi.


## Riwayat mengikuti izin, bukan peran

Halaman Riwayat (`/history`) punya paling banyak dua tab: **STO** dan
**Tag OK**. Cetak, scan, dan pembatalan dulu berdiri sebagai tiga tab terpisah,
padahal ketiganya kejadian pada tag yang sama - satu tag jadi harus ditelusuri
dengan berpindah-pindah tab. Sekarang ketiganya satu daftar berurutan waktu,
dengan saringan chip seperti riwayat Tag OK.

| Izin | Yang muncul di tab STO |
| --- | --- |
| prepare | baris cetak (TERCETAK / BELUM CETAK / GAGAL CETAK) + saringan Belum cetak & Gagal cetak |
| scan | baris hasil hitung + saringan Sudah discan + tombol sinkron di AppBar |
| cancel | baris tag yang diajukan batal / sudah dibatalkan + saringan Pembatalan |

Yang hanya memegang `cancel` tidak melihat seluruh riwayat cetak orang lain -
cukup tag yang batal, yang memang urusannya. Cetak ulang otomatis hanya
dijalankan untuk pemegang `prepare`; membuka riwayat untuk memeriksa pengajuan
tidak boleh diam-diam menyalakan printer.

Satu tab berarti isinya langsung tampil tanpa TabBar.

Pengajuan pembatalan kini tersimpan di server (`cancel-request` mengisi
`cancel_requested_by` / `_at` / `cancel_reason` tanpa menyentuh `is_canceled`),
jadi terlihat dari perangkat lain dan tidak hilang saat aplikasi dipasang
ulang. Tag yang sedang diajukan batal juga ditahan dari cetak ulang otomatis -
percuma mencetak lembar yang mungkin sebentar lagi dibatalkan.


## Warna aplikasi

Warna utama sekarang **biru MAJ** (`AppColors.primary`), bukan merah. Merah
korporat (`AppColors.accent` = #C8102E) tinggal dipakai untuk keadaan yang
memang gagal (gagal cetak, dibatalkan), indikator tab, dan badge - kira-kira
1/3 porsi, sisanya biru. Alasannya sederhana: merah sebagai warna AppBar dan
tombol membuat seluruh layar terbaca seperti sedang error padahal keadaannya
normal.

Hijau dan kuning tidak dipakai sama sekali. "Beres" memakai biru terang
(`success`), "perlu perhatian" memakai perunggu (`warning`) - keduanya tetap
terbedakan tanpa warna lampu lalu lintas. Aturan ini dijaga
`test/app_colors_test.dart`: tidak boleh ada warna palet yang jatuh di rentang
rona kuning-hijau, dan warna utama wajib biru.


## Dua jarak kertas, bukan satu

Cetakan uji 4 Sep 2026 menunjukkan sebabnya: menurunkan jarak akhir dari 90 ke
32 titik **hampir tidak mengubah panjang ekor tag**. Artinya sebagian besar
jarak itu bukan dari aplikasi - firmware printer sendiri yang memajukan kertas
ke posisi sobek begitu aliran data berhenti. Jarak itu muncul dua kali: sebagai
ekor cetakan ini, lalu sebagai kepala kosong cetakan berikutnya.

Sebaliknya, di TENGAH batch aliran datanya tidak pernah berhenti, jadi firmware
tidak menyisipkan apa pun - dan 12 titik yang dikirim aplikasi terlalu kecil,
sehingga kotak isian tag sebelumnya menempel ke kepala tag berikutnya.

Karena itu jaraknya dipisah jadi dua setelan (Setting > Printer, keduanya
tersimpan per perangkat):

| Setelan | Bawaan | Untuk apa |
| --- | --- | --- |
| `gapAntarTagDots` - **antar tag** | 28 titik (~3,5 mm) | jarak gunting antar lembar di satu batch; sepenuhnya dari aplikasi |
| `feedAfterTagDots` - **tambahan di akhir** | 0 | hanya untuk printer yang TIDAK maju sendiri; di handheld ini biarkan 0 |

Tombol **"Uji jarak ini"** mencetak dua penanda pendek: jarak antar tag di
antaranya, jarak akhir sesudahnya - kedua jarak langsung terlihat dalam satu
cetakan uji, tanpa memboroskan kertas untuk tag utuh.


## `ESC J` diabaikan printer ini

Cetakan uji 4 Sep 2026 (tag 516-517) menutup dugaan terakhir: jarak antar tag
tetap NOL walau aplikasi mengirim `ESC J 28`, dan sebelumnya mengubah jarak
akhir dari 90 ke 32 lalu ke 0 juga tidak mengubah panjang kertas sama sekali.
Kesimpulannya, printer handheld ini **menerima `ESC J n` tanpa error tetapi
tidak menjalankannya** - persis pola yang sama dengan `printImageBytes` pada
kotak isian.

Sejak itu semua jarak kertas diwujudkan sebagai **baris kosong (LF)**, satu-
satunya perintah maju yang pasti dijalankan (badan tag sendiri dicetak baris
demi baris). Setelan tetap dalam mm, lalu dibulatkan: 1 baris = 24 titik = 3 mm,
dan jumlah barisnya ikut ditampilkan di slider supaya pembulatannya terlihat.

Jarak kosong di kepala cetakan asalnya berbeda: itu kertas antara kepala cetak
dan bibir sobek, dimajukan firmware saat cetakan sebelumnya berhenti. Kertas
itu sudah lewat kepala cetak - tidak bisa dicetaki.

**Percobaan menariknya kembali GAGAL dan dibatalkan.** Perintah `ESC e n`
(mundur n baris) ternyata tidak dijalankan printer ini, DAN lebih buruk dari
sekadar diabaikan: huruf "e"-nya ikut tercetak, jadi kepala tag pertama tiap
batch berbunyi "ePT. MEKAR ARMADA JAYA". Perintahnya sudah dicabut dari
aplikasi dan dari daftar setelan server.

Kesimpulan yang berlaku sekarang: printer ini HANYA menjalankan perintah gerak
berbasis baris (LF). `ESC J` (maju n titik) diabaikan diam-diam, `ESC e`
(mundur n baris) mencetak sampah. Jangan menambahkan perintah gerak selain LF.

Terlepas dari itu, mencetak beberapa tag dalam SATU batch tetap jauh lebih
hemat daripada beberapa kali cetak satuan - kepala kosong itu muncul sekali
per batch, bukan sekali per tag.


## Jarak menganggur DI DALAM tag (sekeliling QR)

Selama beberapa putaran saya salah sasaran: yang dikeluhkan lapangan ternyata
jarak di dalam tag - blok putih lebar di atas dan bawah QR - bukan jarak antar
tag maupun ekor cetakan.

Sebabnya `printQRcode` bawaan plugin: penggambarannya diserahkan ke ZXing,
yang selalu menyisipkan *quiet zone* 4 modul lalu memuaikan gambarnya ke
ukuran yang diminta (180x180 titik). Jadi yang tercetak bukan hanya QR, tetapi
kotak putih 180 titik dengan QR kecil di tengahnya.

Sekarang matriks QR digambar sendiri (`QrBitmap`, memakai paket `qr`) dengan
margin 1 modul dan 3 titik per modul, lalu dikirim sebagai raster `GS v 0` -
jalur yang sama dengan kotak isian dan sudah terbukti dijalankan printer ini.
Tinggi QR turun dari 180 titik menjadi ~80 titik (~1 cm hemat per tag).

Bila penggambaran gagal (data terlalu panjang, kertas terlalu sempit), jalur
plugin tetap dipakai - lebih baik marginnya lebar daripada tag keluar tanpa QR.


## Setelan jarak pindah ke server

Selama setelan jarak disimpan di masing-masing handheld, tiap HT punya angka
sendiri: hasil cetak antar operator berbeda-beda dan tidak ada yang bisa
memastikan mana yang benar. Sejak 4 Sep 2026 angkanya disimpan di
`majsf_sto.printer_settings` (tabel nama-nilai, satu baris per setelan).

- `GET /api/sto/printer-setting` - dibaca SEMUA user terdaftar; tiap handheld
  memerlukannya saat mencetak.
- `POST /api/sto/printer-setting` - **hanya admin**. Kirim hanya field yang
  ingin diubah. Nilai di luar batas ditolak (`tarik_awal_baris` 0-5,
  `paper_size` mm58/mm80).

Di aplikasi, slider di Setting > Printer hidup hanya untuk admin, dengan tombol
**"Simpan ke server"**. Operator melihat angkanya tetapi tidak bisa
menggesernya. Nilai lokal tetap dipakai sebagai cache supaya printer tetap
jalan saat jaringan mati - begitu server menjawab, angkanyalah yang berlaku.

Percobaan yang DIBATALKAN: menggambar QR sendiri dengan margin ketat
(`QrBitmap`). Hasil cetaknya jelek di lapangan, jadi dikembalikan ke
`printQRcode` bawaan plugin.


## Apa yang masih boleh disimpan di perangkat

Setelah pembersihan 4 Sep 2026, sqflite tinggal dipakai untuk tiga hal, dan
ketiganya punya alasan yang tidak bisa digantikan jaringan:

| Isi | Alasan |
| --- | --- |
| **Outbox** | antrean kirim saat jaringan mati (pengajuan pembatalan, hasil scan). Keputusan admin TIDAK lewat sini - gagal terang-terangan lebih baik daripada terlihat berhasil |
| **Master part** | 6.508 baris, dicari berkali-kali per menit. Dibatasi 2.000 baris/area + pencarian ke server saat tidak ketemu |
| **Tag & batch yang sedang dicetak** | dipakai layar Preview; justru saat printer bermasalah jaringan tidak boleh jadi syarat |
| **Baris perangkat INI** | ANDROID_ID harus tetap dikenali offline - login memeriksa pemasangan lewat itu |

Yang DIBUANG: salinan daftar user, event, dan perangkat lain. Ketiganya kini
dibaca langsung dari server; bila jaringan mati layarnya kosong dengan pesan,
bukan menampilkan data lama yang menyamar sebagai data terkini. Salinan itulah
yang dulu membuat antrean pengajuan terlihat kosong dan izin hasil suntingan
seolah kembali sendiri.


## Tag OK: dua langkah yang sengaja dipisah

Tabel `majsf_sto.tag_ok_data` sudah ada (2.035 baris dari STO sebelumnya).
Yang ditambahkan hanya kolom alur barunya: `scan_open`, `opened_by`,
`opened_at`, `qty_scan`, `scanned_by`, `scanned_at`.

1. **Siapkan Tag OK** - petugas memindai tag di lapangan lalu menyetujuinya;
   `scan_open` menjadi 1. Artinya "tag ini ada dan siap dihitung".
2. **Scan Tag OK** - penghitung memindai tag yang sama lalu mengisi qty
   fisiknya; tag tertutup kembali beserta `qty_scan` dan `scanned_by`.

Pemisahan itu yang membuat selisih bisa ditelusuri: tag yang disiapkan tapi
tidak pernah dihitung tetap terlihat (`scan_open = 1`), dan tag tidak mungkin
dihitung tanpa pernah disiapkan - syarat `scan_open = 1` ada di klausa WHERE
UPDATE, bukan sekadar diperiksa controller, supaya dua handheld yang memindai
bersamaan tidak menghasilkan hitungan ganda.

Kode Tag OK (mis. `MAJ2708260202754`) tidak bertanda hubung sehingga tidak
cocok dengan pola tag STO - pembacaannya terpisah (`ScanCode.extractTagOk`),
dan pemindainya menerima barcode Code128/Code39/EAN13 selain QR.

## Pembatalan Tag OK

Alurnya mengikuti pembatalan tag STO: siapa pun yang mengajukan - termasuk
admin - masuk daftar pengajuan lebih dulu (`is_canceled` = 2), lalu admin
memutuskan setuju (1) atau tolak (kembali 0). Jejaknya tersimpan di
`cancel_reason`, `canceled_by`, dan `canceled_at`.

Tag dengan `is_canceled` bukan 0 tidak bisa disiapkan maupun dihitung.
Syaratnya ada di klausa WHERE, bukan sekadar diperiksa controller, supaya dua
handheld yang bekerja bersamaan tidak bisa menembusnya; controller-nya tetap
memeriksa lebih dulu agar pesannya jelas, bukan sekadar "0 baris berubah".

Tag yang dibatalkan juga dikeluarkan dari ringkasan `terbuka`/`tertutup` dan
dari `total_qty` - memasukkannya membuat hasil hitung STO terlihat lebih besar
dari yang benar-benar tercatat.

### Izin

`prepareOk`, `scanOk`, dan `cancelOk` terpisah dari izin tag STO: petugas Tag
OK sering orang yang berbeda, jadi memegang "Siapkan Tag" tidak otomatis
berarti berhak menyiapkan Tag OK.

## Kotak pesan (chat)

Dua arah antara operator dan admin, ditambah utas `BROADCAST` untuk pengumuman
yang hanya bisa ditulis admin. Satu operator = satu utas, dan SEMUA admin
membaca utas yang sama - di lapangan operator butuh jawabannya datang, bukan
jawabannya datang dari admin tertentu.

**Tidak ada notifikasi sistem.** Handheld ini di jaringan pabrik tanpa akses
keluar, jadi FCM tidak bisa diandalkan sampai di perangkat; memasangnya hanya
menghasilkan notifikasi yang kadang datang kadang tidak. Sebagai gantinya:
badge jumlah belum dibaca di kartu Pesan pada beranda, dan penyegaran berkala
(8 detik, `after_id` sehingga hanya pesan baru yang ditarik) selama layar
percakapan terbuka. Denyutnya berhenti begitu layar ditinggalkan.

### Penjagaan spam

Semuanya di server (`M_sto_chat`), bukan di aplikasi - aturan di aplikasi bisa
dilewati dengan memanggil API langsung, dan mengubahnya berarti memasang ulang
APK ke puluhan handheld:

| Aturan | Nilai |
| --- | --- |
| Maksimal pesan per menit per NIK | 10 |
| Jeda minimum antar pesan | 2 detik |
| Pesan sama persis berturut-turut | ditolak dalam 5 menit |
| Panjang maksimal | 1000 huruf |
| Pembisuan oleh admin | `users.chat_muted_until`, lewat `chat-mute` |

Penolakannya memakai HTTP 429, bukan 400: keadaannya sementara, bukan
permintaan yang salah bentuk.

## Dari mana tag OK berasal

`majsf_sto.tag_ok_data` bukan sumber tag, melainkan **catatan STO**: barisnya
baru ada setelah seseorang menyiapkan tag itu. Sumber aslinya dua:

| Jalur | Tabel sumber | Kelengkapan |
| --- | --- | --- |
| PRESS / IFPP | `majsf_inventory.table_sto_tag_ok` | lengkap (job number, qty kanban, project, customer, area) |
| WELDING | `majsf_andon_welding.welding_production_tag_ok` | hanya identitas; job number & area dilengkapi dari `majsf_sto.master_data`, qty kanban ikut dari `tag-ok-prepare` |

Keduanya **dibaca saja** - tabel itu milik sistem lain dan tidak pernah
ditulis dari sini. Yang ditulis hanya `tag_ok_data`.

Alurnya: menu Siapkan memanggil `GET /sto/tag-ok`; bila tagnya belum
terdaftar, aplikasi mengambil detailnya lewat `GET /sto/tag-ok-prepare`
(endpoint tim backend lain), lalu `POST /sto/tag-ok-open` mendaftarkan
barisnya. Server memastikan sendiri tag itu memang terbit di salah satu tabel
sumber sebelum mendaftarkan - keterangan dari aplikasi hanya menambal kolom
yang tidak ada di sumbernya, tidak pernah menentukan keabsahan tag.

Menu Hitung dan Batal sengaja tidak mencari ke sumber produksi: tag yang belum
disiapkan memang belum boleh dihitung.

**Dua deployment.** Server 67 (`majsf_rest_api`) dan mspin (`/sto`) menjalankan
salinan kode yang berbeda; perubahan di 67 tidak otomatis sampai ke mspin,
padahal aplikasi memakai HTTPS sebagai bawaan. Setiap perubahan endpoint STO
harus disalin ke sana juga.
