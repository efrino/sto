# Kontrak API - STO Preparation

Ada **dua bagian** di dokumen ini:

1. **Bagian A - API yang sudah ada** (`api/Sto.php`, referensi "MAJSF STO API").
   Sembilan endpoint, sudah dipakai `HttpStoApi`.
2. **Bagian B - yang belum ada.** Fitur aplikasi yang endpoint-nya belum
   tersedia, lengkap dengan bentuk yang diusulkan. Selama belum ada, fitur itu
   dilayani database lokal perangkat (mode simulasi sudah dibuang
   menyala).

- Base URL: `http://192.168.10.67/majsf_rest_api/api` (bisa diubah di Setting)
- Belum ada auth - tidak perlu header `Authorization` pada endpoint STO.
- `Content-Type: application/json` (form-urlencoded juga diterima; daftar
  dikirim sebagai `nama[]` atau satu string dipisah koma).
- Sisi aplikasi: path ada di `lib/data/remote/api_endpoints.dart`, parsing di
  `lib/data/remote/sto_api.dart`.

## Amplop respons

Setiap balasan punya `status` dan `message`, payload menyusul di bawahnya.

| status | Arti |
| --- | --- |
| `success` | Diproses. Bisa juga berarti "tidak ada yang perlu diproses" - baca field jumlahnya. |
| `failed` | Ditolak. Validasi mengembalikan array `errors`. |
| `confirm` | Khusus `scan-tag`: data lama belum ditimpa. Kirim ulang dengan `confirm: true`. |
| `multiple` | Khusus `print-tag`: pencarian menemukan lebih dari satu item. Pilih lewat `id_item`. |

`confirm` dan `multiple` tetap dikirim dengan **HTTP 200**, begitu pula
`failed`. Jadi kode HTTP saja tidak cukup - `ApiClient._decode` memeriksa field
`status`, bukan status HTTP.

Tanggal: `YYYY-MM-DD` atau `YYYY-MM-DD HH:MM:SS`. Bila hanya tanggal,
rentangnya dilebarkan otomatis (`start` -> `00:00:00`, `end` -> `23:59:59`);
alias `start` / `end` diterima.

---

# BAGIAN A - API yang sudah ada

| Method | Path | Dipakai untuk |
| --- | --- | --- |
| POST | `/sto/register` | membuat akun STO — **wajib `created_by`** (`nik`, `role`, `tim?`, `device_id?`, `area[]?`) |
| GET | `/sto/user-list` | daftar akun: `q`, `id_device`, `role`, `limit` (admin) |
| POST | `/sto/user-update` | ubah `role`/`tim`/`device_id`/`area`/`permissions` sebuah akun (admin) |
| POST | `/sto/user-delete` | hapus akun (admin) |
| POST | `/sto/login` | login dengan NIK saja |
| POST | `/sto/print-tag` | membuat **satu** tag baru di `sto_data` |
| POST | `/sto/scan-tag` | menyimpan hasil hitung (`id_tag`, `nik`, `tim`, `qty`, `confirm?`) |
| POST | `/sto/cancel-tag` | `is_canceled = 1`, satu id_tag atau array (maks 5.000) |
| GET | `/sto/part-list` | master part: `area` (satu/`area[]`/dipisah koma), `q`, `limit` (default 1000, maks 10000) — **tanpa gerbang admin** |
| GET | `/sto/scan-history` | riwayat scan (`nik`, `tim`, `area`, `id_tag`, `start_date`, `end_date`, `limit`) |
| GET | `/sto/summary-area` | rekap per area (`start_date` & `end_date` wajib) |
| GET | `/sto/summary-part` | rekap per part number (idem) |
| POST | `/sto/cancel-tag-ok` | warisan: pembatalan berdasarkan `ids[]` id_tag_ok lama |
| GET | `/sto/device-list` · `/sto/device-detail` | daftar & detail perangkat |
| POST | `/sto/device-create` · `device-update` · `device-delete` | CRUD perangkat |
| GET | `/sto/event-list` · `/sto/event-detail` | daftar & detail periode STO |
| POST | `/sto/event-create` · `event-update` · `event-delete` | CRUD periode STO |
| POST | `/sto/print-status` | menandai keadaan cetak tag: draft / printed / error (+ `message`) |
| GET | `/sto/tag-ok` | satu Tag OK beserta keadaannya (semua user terdaftar) |
| POST | `/sto/tag-ok-open` | SIAPKAN Tag OK - `scan_open` = 1 |
| POST | `/sto/tag-ok-scan` | HITUNG Tag OK - `qty_scan`, `scanned_by`, `scan_open` = 0 |
| GET | `/sto/tag-ok-list` | daftar Tag OK + ringkasan (terbuka/tertutup/batal/pengajuan/total qty); saring `open`, `q`, `milik`, `batal` |
| GET | `/sto/chat-threads` | daftar percakapan + jumlah belum dibaca |
| GET | `/sto/chat-messages` | isi satu percakapan; `after_id` untuk penyegaran berkala |
| POST | `/sto/chat-send` | kirim pesan; utas `BROADCAST` khusus admin; ditolak 429 bila kena penjagaan spam |
| POST | `/sto/chat-read` | tandai percakapan dibaca sampai `last_id` |
| POST | `/sto/chat-mute` | admin membisukan NIK selama `menit` (0 = lepas) |
| POST | `/sto/tag-ok-cancel` | ajukan batal Tag OK (`alasan`) atau keputusan admin (`keputusan` = `setuju`/`tolak`) |
| GET | `/sto/print-history` | riwayat cetak (+`q=` pencarian, `summary` masih dikirim walau layar tidak lagi menampilkannya) |
| POST | `/sto/cancel-request` | operator MENGAJUKAN pembatalan (`is_canceled` tidak disentuh; `reason` wajib) |
| POST | `/sto/cancel-reject` | admin menolak pengajuan - kolom pengajuan dikosongkan |
| GET | `/sto/printer-setting` | setelan printer bersama (semua user terdaftar) |
| POST | `/sto/printer-setting` | menyimpan setelan printer - **hanya admin** |

**Endpoint CRUD Device dan Event hanya untuk role `admin`** - semuanya wajib
menyertakan `nik` admin (termasuk yang GET). Tanpa itu balasannya `failed`
dengan pesan "Endpoint ini hanya bisa diakses user dengan role admin".

Pengecualian sejak 3 Sep 2026: `event-list` dan `event-detail` boleh dibaca
**semua user terdaftar**, bukan hanya admin. Alasannya lugas - tag hanya boleh
dibuat saat ada event berjalan, jadi operator yang menyiapkan tag justru yang
paling butuh daftar itu. `nik` tetap wajib dan NIK asing tetap ditolak; yang
dikunci admin adalah `event-create` / `event-update` / `event-delete`.

`device-delete` dan `event-delete` membalas status `confirm` bila barisnya
masih dipakai; ulangi dengan `force: true` bila memang disengaja. Di aplikasi
hal ini menjadi `ApiConfirmRequiredException`.

## Aturan auth (mengikuti kontrak MAJSF STO API)

1. **login** wajib `nik` **dan** `android_id`. Server mencocokkan ANDROID_ID
   dengan perangkat yang terdaftar pada NIK itu; tidak cocok - termasuk bila
   user belum punya perangkat - dibalas **403** beserta `device_terdaftar`.
   Login hanya **memverifikasi**, tidak menugaskan perangkat: kalau login bisa
   menugaskan ulang, pemeriksaannya jadi tidak ada gunanya.
2. **register** admin-only, tapi gerbangnya bernama **`created_by`** (bukan
   `nik`, yang di sini sudah dipakai untuk akun yang didaftarkan). Nilainya
   ikut disimpan sebagai jejak siapa yang mendaftarkan.
3. **user-update / user-delete** admin-only; sasarannya `nik_user` atau
   `id_user`, sedangkan `nik` selalu berarti admin pengakses.
4. **NIK tidak bisa diubah** (409). `sto_data.nik_a`/`nik_b` menyimpan NIK
   sebagai teks biasa, jadi menggantinya membuat riwayat scan lama yatim -
   hapus akun lalu daftarkan yang baru.
5. **Penugasan perangkat** lewat `register` (`device_id`) atau `user-update`
   (`device_id`); melepasnya dengan mengirim `device_id: ""`. Tidak ada
   endpoint khusus untuk memasang/melepas.
6. `area` (izin area) tersimpan di `users_area`, satu baris per area - **satu
   user boleh punya lebih dari satu**. Pada `user-update`, daftar yang dikirim
   **mengganti** seluruh area. Nilainya harus sama persis dengan
   `master_data.area`: `IFRM`, `PRESS`, `IFPP`, `WELD`, `IFPD` - perhatikan
   **`WELD`, bukan `WELDING`**.
7. **Hak akses menu (`permissions`)** tersimpan di kolom `users.permissions`,
   berisi gabungan `prepare`, `scan`, `cancel` dipisah koma. Dibaca dan
   ditulis `register`, `user-update`, `user-list`, dan `login`; nilai di luar
   ketiganya ditolak. Balasan mengembalikannya sebagai array - kosong berarti
   belum diatur admin, dan aplikasi memperlakukannya sebagai "semua terbuka".
8. **Login admin tidak diperiksa perangkatnya.** Pemasangan hanya bisa
   dilakukan admin, jadi kalau admin ikut dikunci, perangkat baru terkunci
   total - tidak ada yang bisa masuk untuk memasangkan siapa pun.

Pada `user-update` dan `user-delete`, parameter `nik` berarti **NIK admin
pengakses**; sasarannya ditunjuk lewat `target_nik` (atau `id_user`). Field yang
tidak dikirim tidak disentuh, kecuali `area` yang **mengganti seluruh** daftar
area. `new_nik` dipakai untuk mengganti NIK, dan ditolak 409 bila sudah dipakai
orang lain. Admin terakhir tidak bisa dihapus maupun diturunkan perannya.
`user-delete` membalas `confirm` bila user itu pernah mencetak tag - menghapusnya
tidak menghapus tagnya, tapi `sto_data.created_by` dikosongkan sehingga jejak
pencetaknya hilang; ulangi dengan `force: true` bila memang dikehendaki.

**Hanya satu event berjalan - dijaga aplikasi, bukan API.** Server membolehkan
beberapa event berstatus `1` dan hanya memberi `warnings`. Tetapi `print-tag`
menolak (**409**) selama ada lebih dari satu event berjalan, jadi aturannya
tetap harus dijaga. Aplikasi melakukannya: saat admin membuka sebuah event,
event lain yang masih berjalan ditampilkan lebih dulu sebagai pertanyaan, lalu
ditutup lewat `event-update` **setelah** event ini tersimpan - supaya tidak ada
saat di mana tidak ada event berjalan sama sekali.

Bentuk perangkat: `id`, `name` (mis. `HT IFPD 01`), `android_id` (unik, maks
64 karakter), `total_user`. `device-create` membalas 409 bila `android_id`
sudah terdaftar - jadi satu perangkat fisik tidak bisa masuk dua kali.

> **Diperbaiki & diuji 3 September 2026.** Dua model tertinggal saat deploy:
>
> - `M_sto_device.php` belum ada sama sekali - kelima endpoint `device-*`
>   membalas RuntimeException (`api/Sto.php` baris 531). Dibuat mengikuti pola
>   `M_sto_event.php`: tabel `devices`, `total_user` dari LEFT JOIN ke `users`.
> - `M_sto_user.php` masih versi lama: memilih kolom `ip_address` yang sudah
>   dihapus dari tabel, dan belum punya `update_device()` / `get_device()` yang
>   dipanggil controller baru. Akibatnya **`register` dan `login` mati total**.
>   Diperbarui: `get_user_by_nik` kini LEFT JOIN ke `devices` sehingga
>   `format_user()` mendapat `device_name` & `android_id`. Versi lamanya
>   disimpan sebagai `M_sto_user.php.bak-20260903` di server.
>
> Seluruh CRUD device sudah diuji ujung-ke-ujung dengan admin `E.9948`: list,
> create, duplikat `android_id` (409), detail lewat `id_device` maupun
> `android_id`, update sebagian, pencarian `q`, pairing user (`total_user`
> naik jadi 1), `confirm` saat menghapus device yang masih dipakai, force
> delete, dan `users.device_id` ikut kosong karena ON DELETE SET NULL. Data uji
> sudah dibersihkan.

Catatan penting dari skema `majsf_sto`:

- `users`: `id`, `nik` (unik), `role` (teks bebas), `tim` (enum A/B, boleh
  null), `ip_address`; **tidak ada** kolom nama karyawan maupun hak akses menu.
- `users_area`: satu user boleh punya banyak area.
- `events`: `id_event`, `event_name`, `start_date`, `end_date`, `status`
  (1 = berjalan). Dipakai `print-tag` bila `id_event` tidak dikirim.
- `master_data` (6.508 baris): identitas part; `sto_data` menyimpannya lewat
  `id_item` (FK, `ON DELETE RESTRICT`), bukan menyalin teksnya.
- `sto_data`: `id_tag` (unik), `id_event`, `id_item`, `area`,
  `nik_a`/`qty_a`/`updated_a`, `nik_b`/`qty_b`/`updated_b`, `is_canceled`,
  `created_by`. Hasil tim A dan tim B ada pada **satu baris**.
- Penanda "sudah discan" adalah `updated_a` / `updated_b` yang terisi, **bukan**
  `qty > 0` - jadi hasil hitung nol tetap sah dan tidak bisa tertimpa diam-diam.

---

## Yang sudah dipakai aplikasi

| Halaman | Endpoint | Catatan |
| --- | --- | --- |
| Setting > Event STO | `event-list`, `event-create`, `event-update`, `event-delete` | server jadi sumber kebenaran, hasilnya disalin ke cache lokal supaya pemeriksaan "event berjalan" tetap jalan saat jaringan mati |
| Setting > User & izin | `user-list`, `register`, `user-update`, `user-delete` | **tanpa salinan lokal** - jaringan mati berarti daftarnya kosong dengan pesan, bukan data lama |
| Setting > Perangkat & pairing | `device-*` + `user-list?id_device=` | daftar perangkat **dan** NIK terpasangnya dari server |
| Setting > Perangkat & pairing | `device-list`, `device-create`, `device-update`, `device-delete` | nomor aset = kolom `name` di server; daftar NIK per perangkat masih catatan lokal karena belum ada endpointnya |
| Login | `login` (+ `android_id`) | server yang memutuskan pemasangan; balasannya (`device_id`, `device_name`) disalin ke catatan perangkat lokal |
| Setting > Printer | `printer-setting` | jarak antar tag / jarak akhir / tarik mundur disimpan di tabel `printer_settings`; operator hanya bisa melihat |
| Riwayat (tab STO, baris hitung) | `scan-history?nik=&q=` | hanya hasil hitung NIK yang login; pencarian dilakukan server atas seluruh riwayat |
| Batal Tag (tab Pengajuan) | `cancel-requests`, `cancel-approve`, `cancel-reject` | antrean & keputusan langsung ke server, tanpa antrean lokal |
| Riwayat (tab STO, baris cetak) | `print-history`, `print-status`, `cancel-request`, `cancel-reject` | keadaan cetak (draft/printed/error) milik server; perangkat hanya menampilkan, kartu ringkasan memakai `summary` dari server |
| Siapkan Tag | `event-list` | event berjalan ditarik saat halaman dibuka dan sebelum tag dibuat, untuk operator maupun admin |

Keduanya hanya menyentuh server bila yang membuka adalah **admin** dan toggle
server terjangkau. Bila tidak,
halaman tetap terisi dari cache dan memasang pemberitahuan "diambil dari cache".

---

# BAGIAN B - Belum ada di API (masih dilayani data lokal)

Urut dari yang paling menghambat:

| # | Kebutuhan aplikasi | Usulan endpoint | Kenapa perlu |
| --- | --- | --- | --- |
| 1 | Cetak N tag sekaligus | `qty` pada `print-tag`, atau `POST /sto/print-tag-bulk` | Satu panggilan = satu tag, jadi aplikasi membatasi **maksimal 5 tag sekali cetak**: tiap nomor yang terlanjur dibuat tidak bisa dicetak ulang, sehingga batch besar berarti risiko besar bila putus di tengah. |
| 2 | Detail tag tanpa menghitung | `GET /sto/tag-detail?id_tag=` | Halaman Scan perlu menampilkan part sebelum operator mengisi qty. `scan-history` hanya memuat tag yang **sudah** dihitung. |
| 3 | Alur pengajuan pembatalan | `POST /sto/cancel-request`, `GET /sto/cancel-requests`, `POST /sto/cancel-approve`, `POST /sto/cancel-reject` | `cancel-tag` membatalkan seketika. Aturan yang dipakai: semua orang mengajukan, admin menyetujui - butuh kolom `cancel_reason`, `cancel_requested_by/at`, `cancel_approved_by`. |
| 5 | Nama karyawan | kolom `name` di `users` (atau join ke master karyawan) | Layar hanya bisa menampilkan NIK. |
| 6 | Konfirmasi tag benar tercetak | `POST /sto/tag-printed` | `print-tag` membuat baris walau kertasnya gagal keluar; belum ada cara menandai tag yang batal cetak. |

Sudah terjawab pada pembaruan 3 September 2026:

- **CRUD event** (`event-*`) dan **CRUD perangkat** (`device-*`).
- **CRUD user**: `register`, `user-update`, `user-delete` (tanpa endpoint
  daftar user).
- **Pairing NIK ke perangkat** lewat kolom `users.device_id`, diisi
  `register`/`user-update` dan dikosongkan dengan `device_id: ""`.
- Kolom `users.ip_address` **sudah tidak ada**; digantikan `device_id`.
- Tersedia **dua deployment dengan kontrak identik**: CI3 di
  `http://192.168.10.67/majsf_rest_api` dan CI4 di `http://192.168.10.55/sto`.
  Keduanya menunjuk database yang sama (`majsf_sto` di 10.67), jadi alamat
  server di menu Setting bisa diarahkan ke salah satunya.

Bagian di bawah ini adalah **usulan bentuk request/response** untuk nomor-nomor
di atas - dipakai `MockStoApi` supaya alurnya sudah bisa diuji sekarang.

---

## 1. `POST /sto_prep/login`

Verifikasi NIK operator.

```json
// request
{
  "nik": "A.10525",
  "device_id": "20a92433c2f589cd",
  "asset_name": "016-HSS-TBN"
}

// response 200
{
  "nik": "A.10525",
  "name": "EFRINO WAHYU",
  "department": "IT",
  "section": "SYSTEM DEVELOPMENT",
  "role": "admin",
  "areas": ["WAREHOUSE 1", "WAREHOUSE 2"],
  "team": "A",
  "permissions": ["prepare", "scan", "cancel"],
  "active": true,
  "token": "opsional-jwt"
}
```

`role` menentukan wewenang: **admin** boleh membuka menu Setting dan
menyetujui pembatalan; **operator** hanya menyiapkan/mencetak/scan dan
mengajukan pembatalan. `areas` membatasi part yang boleh disiapkan operator
(kosong = semua area). Aplikasi menerima `areas` berupa array maupun teks
dipisah koma.

`permissions` menentukan menu yang muncul di halaman utama operator -
gabungan bebas dari `prepare` (siapkan & cetak), `scan` (scan & input qty),
dan `cancel` (ajukan pembatalan). Boleh dikirim sebagai array maupun teks
dipisah koma. Bila field ini tidak ada, aplikasi menganggap user punya semua
akses supaya user lama tidak mendadak kehilangan menu; admin selalu dianggap
punya semuanya.

`team` berisi nama tim saja (mis. `"A"`), bukan `"TIM A"` - daftarnya
dikelola admin lewat `GET /sto_prep/teams`. Nilai lama berawalan `TIM ` dan
huruf kecil tetap diterima lalu diseragamkan oleh aplikasi.

`device_id` = ANDROID_ID perangkat (MAC address tidak bisa dibaca aplikasi
sejak Android 6/10). Server sebaiknya menolak login operator yang NIK-nya tidak
terpasang pada `device_id` tersebut, dengan pesan yang bisa dibaca operator.

Gagal: HTTP 4xx dengan `{ "message": "NIK tidak terdaftar" }` atau
`{ "message": "NIK belum dipasangkan pada perangkat 016-HSS-TBN" }`.

---

## 2. `GET /sto_prep/parts?keyword=&updated_since=`

Master part/job untuk pencarian. Dipanggil saat cache kosong / basi (TTL 12 jam)
atau saat operator menekan tombol perbarui. Kirim seluruh master bila `keyword`
kosong - aplikasi menyimpannya ke sqflite agar pencarian tetap jalan offline.

```json
[
  {
    "part_number": "53801-BZ010",
    "job_number": "JOB-2601",
    "part_name": "PANEL SIDE OUTER RH",
    "customer": "ADM",
    "model": "AYLA",
    "unit": "PCS",
    "area": "WAREHOUSE 1",
    "location": "RAK A-01",
    "part_type": "FP",
    "std_pack": 50,
    "updated_at": "2026-09-01 08:00:00"
  }
]
```

Alias yang juga diterima aplikasi: `partno`, `job_no`, `description`/`desc`,
`tipe`, `uom`, `lokasi`, `lot_size`.

`part_type` = status part yang dicetak pada tag: **FP** (finish part) atau
**WIP** (work in process). Alias yang diterima: `status`, `type`. Nilai bebas
seperti "Finish Part" / "work in process" ikut dinormalkan jadi FP/WIP;
kosong dianggap FP.

---

## 3. `POST /sto_prep/sequence/reserve`

**Endpoint paling penting.** Server memesan blok nomor urut supaya nomor tag
unik lintas perangkat (beberapa MPOS bisa mencetak bersamaan).

```json
// request
{ "qty": 5, "area": "WAREHOUSE 1", "nik": "A.10525" }

// response 200
{ "prefix": "STO260902", "start": 121, "end": 125 }
```

Aturan:
- `prefix` disarankan `STO` + `yyMMdd`; nomor akhir dirakit aplikasi menjadi
  `STO260902-000121` (padding 6 digit).
- Blok yang sudah dipesan **tidak boleh** diberikan ke perangkat lain, walau
  tagnya batal dicetak (nomor hangus - itu wajar dan justru jadi jejak audit).
- Bila endpoint ini gagal/timeout, aplikasi memakai counter lokal dengan prefix
  berawalan `L` (mis. `LSTO260902-000004`) dan menandai tag `offline_sequence: true`.
  Server harus menerima nomor tersebut saat sinkronisasi dan merekonsiliasinya.

---

## 4. `POST /sto_prep/batch`

Dikirim saat satu sesi tag dibuat (sebelum dicetak).

```json
{
  "batch": {
    "batch_id": "A10525-M1K2J3",
    "part_number": "53801-BZ010",
    "job_number": "JOB-2601",
    "part_name": "PANEL SIDE OUTER RH",
    "area": "WAREHOUSE 1",
    "qty": 5,
    "created_by": "A.10525",
    "created_at": "2026-09-02T07:45:00.000",
    "note": null
  },
  "tags": [ { "tag_no": "STO260902-000121", "sequence": 121, "...": "..." } ]
}
```

---

## 5. `POST /sto_prep/tag/print`

Konfirmasi tag benar-benar keluar dari printer. **Harus idempoten**: kiriman
berulang dengan `tag_no` sama cukup dijawab 200 tanpa efek ganda (aplikasi bisa
mengirim ulang setelah sempat offline).

```json
{
  "tag_no": "STO260902-000121",
  "printed_at": "2026-09-02T07:46:10.000",
  "nik": "A.10525"
}
```

---

## 6. Alur pembatalan (dua tahap)

Siapa pun yang memindai tag di menu Batal - operator **maupun admin** -
menghasilkan **pengajuan** lebih dulu; admin kemudian **menyetujui atau
menolaknya** di tab Pengajuan. Tidak ada jalur pembatalan langsung, supaya
setiap tag batal selalu punya jejak siapa mengajukan dan siapa menyetujui.
Server sebaiknya menolak permintaan approve/reject dari user non-admin.

### 6a. `POST /sto_prep/tag/cancel-request` (siapa pun yang scan)

```json
{
  "tag_no": "STO260902-000121",
  "reason": "Mispart - part tidak sesuai",
  "requested_by": "A.20431",
  "requested_at": "2026-09-02T07:50:00.000"
}
```

Tag berpindah ke status `pending_cancel`. Sejak titik ini tag **tidak boleh
lagi dihitung**: halaman Scan menolak tag berstatus `pending_cancel` maupun
`cancelled`, jadi `GET /sto_prep/tag/detail` wajib mengembalikan `status`
yang mutakhir.

### 6b. `POST /sto_prep/tag/cancel` (admin menyetujui)

```json
{
  "tag_no": "STO260902-000121",
  "reason": "Mispart - part tidak sesuai",
  "cancelled_at": "2026-09-02T08:10:00.000",
  "approved_by": "A.10525"
}
```

### 6c. `POST /sto_prep/tag/cancel-reject` (admin menolak)

```json
{ "tag_no": "STO260902-000121", "rejected_by": "A.10525" }
```

Tag kembali ke status `printed` dan tetap dihitung saat STO.

---

## 7. Scan & hasil hitung

### 7a. `GET /sto_prep/tag/detail?tag_no=STO260902-000121`

Dipakai halaman Scan saat tag dicetak perangkat lain (tidak ada di database
lokal). Balas detail part apa adanya:

```json
{
  "tag_no": "STO260902-000121",
  "part_number": "48601-BZ010",
  "job_number": "JOB-2620",
  "part_name": "BRACKET SUSPENSION UPPER",
  "area": "WAREHOUSE 2",
  "part_type": "FP",
  "unit": "PCS",
  "created_by": "A.20431",
  "status": "printed"
}
```

Tag tidak dikenal cukup dijawab 404 atau `data: null`.

### 7b. `POST /sto_prep/count`

Hasil hitung satu tag oleh satu tim.

```json
{
  "nik": "A.20431",
  "tag_no": "STO260902-000121",
  "tim": "A",
  "qty": 24,
  "counted_at": "2026-09-03T08:10:00.000",
  "updated_at": null
}
```

Aturan yang dipakai aplikasi dan sebaiknya ditegakkan juga di server:

- kunci unik **(tag_no, tim)** - tim lain boleh mengirim angka untuk tag yang
  sama, tetapi satu tim hanya punya satu angka;
- pengiriman berikutnya dengan pasangan (tag_no, tim) yang sama = **koreksi**,
  dan hanya sah bila `nik`-nya sama dengan pencatat pertama;
- endpoint harus idempoten: kiriman ulang setelah offline tidak boleh
  menghasilkan baris ganda;
- tag berstatus `pending_cancel` / `cancelled` ditolak - aplikasi sudah
  menyaringnya di layar, tapi server tetap perlu menjaganya.

---

## 8. Endpoint admin

| Endpoint | Isi |
| --- | --- |
| `GET /sto_prep/users` | daftar user: `nik`, `name`, `department`, `section`, `role`, `areas[]`, `team`, `permissions[]`, `active` |
| `POST /sto_prep/users/save` | tambah/ubah user (kirim objek user; `previous_nik` bila NIK diganti) |
| `POST /sto_prep/users/delete` | `{ "nik": "A.20431" }` - tolak bila itu admin aktif terakhir |
| `GET /sto_prep/events` | daftar event: `id`, `name`, `start_date`, `end_date`, `areas[]`, `status` (`open`/`closed`) |
| `POST /sto_prep/events/save` | tambah/ubah event |
| `POST /sto_prep/events/delete` | `{ "id": "STO-202609" }` - tolak bila sudah dipakai tag |
| `GET /sto_prep/teams` | daftar tim: `name` (`"A"`, `"B"`, ...), `active` |
| `POST /sto_prep/teams/save` | `{ "name": "C", "active": true }` |
| `POST /sto_prep/teams/delete` | `{ "name": "C" }` - tolak bila masih dipakai user / hasil hitung |

Aplikasi memakai event untuk mengunci pembuatan tag: hanya event `open` yang
tanggalnya mencakup hari ini yang boleh dipakai, dan `event_id`-nya ikut
dikirim pada payload tag.

Tag yang sudah dibatalkan tidak boleh bisa dicetak ulang dari sisi mana pun -
di aplikasi hal ini dijaga oleh `TagDao.markPrinted` (UPDATE bersyarat
`status = 'draft'`) dan kolom `tag_no` yang UNIQUE.

---

## Usulan tabel server

```sql
CREATE TABLE sto_tag (
  tag_no        VARCHAR(24) PRIMARY KEY,
  sequence_no   INT NOT NULL,
  batch_id      VARCHAR(32) NOT NULL,
  part_number   VARCHAR(32) NOT NULL,
  job_number    VARCHAR(32) NOT NULL,
  part_name     VARCHAR(120),
  customer      VARCHAR(32),
  model         VARCHAR(32),
  unit          VARCHAR(8),
  area          VARCHAR(64),
  location      VARCHAR(64),
  part_type     ENUM('FP','WIP') DEFAULT 'FP',
  qty           INT DEFAULT 0,
  status        ENUM('draft','printed','pending_cancel','cancelled') DEFAULT 'draft',
  event_id      VARCHAR(32) NULL,
  created_by    VARCHAR(20),   -- NIK string, bisa beralfabet (A.10525)
  created_at    DATETIME,
  printed_at    DATETIME NULL,
  cancelled_at  DATETIME NULL,
  cancel_reason       VARCHAR(120) NULL,
  cancel_requested_by VARCHAR(20) NULL,
  cancel_requested_at DATETIME NULL,
  cancel_approved_by  VARCHAR(20) NULL,
  offline_seq   TINYINT(1) DEFAULT 0,
  device_id     VARCHAR(64) NULL,
  INDEX (batch_id), INDEX (part_number, job_number), INDEX (status)
);

CREATE TABLE sto_user (
  nik        VARCHAR(20) PRIMARY KEY,
  name       VARCHAR(80) NOT NULL,
  department VARCHAR(40),
  section    VARCHAR(40),
  team        VARCHAR(10),          -- nama tim ('A'), dikirim saat POST count
  role        ENUM('admin','operator') DEFAULT 'operator',
  areas       VARCHAR(255),         -- dipisah koma, kosong = semua area
  permissions VARCHAR(64),          -- dipisah koma: prepare,scan,cancel
  active      TINYINT(1) DEFAULT 1,
  FOREIGN KEY (team) REFERENCES sto_team (name)
);

CREATE TABLE sto_team (
  name   VARCHAR(10) PRIMARY KEY,   -- 'A', 'B', ...
  active TINYINT(1) DEFAULT 1
);

CREATE TABLE sto_event (
  id         VARCHAR(32) PRIMARY KEY,
  name       VARCHAR(80) NOT NULL,
  start_date DATE NOT NULL,
  end_date   DATE NOT NULL,
  areas      VARCHAR(255),          -- kosong = semua area
  status     ENUM('open','closed') DEFAULT 'open',
  created_by VARCHAR(20),
  created_at DATETIME
);

CREATE TABLE sto_device (
  device_id     VARCHAR(64) PRIMARY KEY,   -- ANDROID_ID perangkat
  asset_name    VARCHAR(32) UNIQUE,        -- nomor aset perusahaan, mis. 016-HSS-TBN
  model         VARCHAR(64),
  active        TINYINT(1) DEFAULT 1,
  registered_at DATETIME,
  registered_by VARCHAR(20),
  last_seen_at  DATETIME NULL
);

CREATE TABLE sto_device_nik (
  device_id VARCHAR(64) NOT NULL,
  nik       VARCHAR(20) NOT NULL,
  paired_at DATETIME,
  paired_by VARCHAR(20),
  PRIMARY KEY (device_id, nik)
);

CREATE TABLE sto_count (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  tag_no     VARCHAR(24) NOT NULL,
  nik        VARCHAR(20) NOT NULL,
  tim        VARCHAR(10) NOT NULL,
  qty        INT NOT NULL DEFAULT 0,
  counted_at DATETIME,
  updated_at DATETIME NULL,
  UNIQUE KEY uniq_tag_tim (tag_no, tim),
  INDEX (nik), INDEX (tim)
);

CREATE TABLE sto_sequence (
  prefix     VARCHAR(16) PRIMARY KEY,
  last_value INT NOT NULL DEFAULT 0,
  updated_at DATETIME
);
```

Pemesanan blok nomor sebaiknya dalam satu transaksi:

```sql
UPDATE sto_sequence SET last_value = last_value + :qty WHERE prefix = :prefix;
SELECT last_value FROM sto_sequence WHERE prefix = :prefix; -- end
-- start = end - qty + 1
```
