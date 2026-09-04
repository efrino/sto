/// Daftar endpoint STO pada backend MAJSF (controller `api/Sto.php`).
///
/// Base URL: http://192.168.10.67/majsf_rest_api/api  (bisa diubah di Setting)
/// Belum ada auth: tidak ada header Authorization pada endpoint STO.
///
/// Sembilan belas endpoint di bawah adalah SELURUH yang tersedia hari ini.
/// Fitur aplikasi yang belum punya endpoint (master part, detail tag,
/// pengajuan batal, CRUD user) masih dilayani database lokal - daftarnya ada
/// di docs/API_CONTRACT.md bagian "Belum ada di API".
class ApiEndpoints {
  ApiEndpoints._();

  // ------------------------------------------------------------------ akun
  /// POST { nik, role, tim?, ip_address?, area[]? } -> user baru
  static const String register = '/sto/register';

  /// POST { nik, device_id? } -> { id, nik, role, tim, device_id, area[] }
  static const String login = '/sto/login';

  // Pengelolaan user hanya untuk admin. `nik` berarti NIK admin pengakses,
  // sasarannya `nik_user`. Tidak ada endpoint daftar user - daftarnya
  // dipelihara di perangkat.
  /// GET ?nik=NIK-admin&q=&id_device=&role=&limit=
  static const String userList = '/sto/user-list';
  static const String userUpdate = '/sto/user-update';
  static const String userDelete = '/sto/user-delete';

  // -------------------------------------------------------------- perangkat
  // Sepuluh endpoint CRUD device & event hanya boleh diakses role admin:
  // seluruhnya wajib menyertakan `nik` milik admin.
  static const String deviceList = '/sto/device-list';
  static const String deviceDetail = '/sto/device-detail';
  static const String deviceCreate = '/sto/device-create';
  static const String deviceUpdate = '/sto/device-update';
  static const String deviceDelete = '/sto/device-delete';

  // ------------------------------------------------------------------ event
  static const String eventList = '/sto/event-list';
  static const String eventDetail = '/sto/event-detail';
  static const String eventCreate = '/sto/event-create';
  static const String eventUpdate = '/sto/event-update';
  static const String eventDelete = '/sto/event-delete';

  // ------------------------------------------------------------------- tag
  /// POST { area, part_number|job_number, id_item?, id_event?, nik? }
  /// -> satu tag baru (satu panggilan = satu tag)
  static const String printTag = '/sto/print-tag';

  /// GET ?id_tag= -> detail satu tag (sto_data + master_data)
  static const String tagDetail = '/sto/tag-detail';

  /// GET  ?nik=&id_tag_ok=   -> satu Tag OK beserta keadaannya
  static const String tagOk = '/sto/tag-ok';

  /// POST { nik, id_tag_ok } -> menyiapkan Tag OK (scan_open = 1)
  static const String tagOkOpen = '/sto/tag-ok-open';

  /// POST { nik, id_tag_ok, qty } -> mencatat hasil hitung lalu menutupnya
  static const String tagOkScan = '/sto/tag-ok-scan';

  /// GET ?nik=&open=&area=&q=&batal=&limit= -> daftar Tag OK + ringkasan
  static const String tagOkList = '/sto/tag-ok-list';

  /// GET  ?nik=            -> daftar percakapan + jumlah belum dibaca
  static const String chatThreads = '/sto/chat-threads';

  /// GET  ?nik=&thread=&after_id=&limit= -> isi satu percakapan
  static const String chatMessages = '/sto/chat-messages';

  /// POST { nik, thread, body } -> kirim pesan
  static const String chatSend = '/sto/chat-send';

  /// POST { nik, thread, last_id } -> tandai sudah dibaca
  static const String chatRead = '/sto/chat-read';

  /// POST { nik, nik_user, menit } -> bisukan user (admin)
  static const String chatMute = '/sto/chat-mute';

  /// POST { nik, id_tag_ok, alasan } -> mengajukan batal Tag OK
  /// POST { nik, id_tag_ok, keputusan } -> keputusan admin (setuju/tolak)
  static const String tagOkCancel = '/sto/tag-ok-cancel';

  /// POST { nik, id_tag, status: draft|printed|error, message? }
  ///
  /// Keadaan cetak dicatat di server, bukan di perangkat: tag yang lembarannya
  /// tidak keluar tetap harus terlihat admin dan perangkat lain.
  static const String printStatus = '/sto/print-status';

  /// GET  ?nik= -> setelan printer bersama (semua user terdaftar)
  /// POST { nik (admin), gap_antar_tag_dots?, feed_akhir_dots?,
  ///        tarik_awal_baris?, paper_size? } -> menyimpan setelan
  static const String printerSetting = '/sto/printer-setting';

  /// GET ?nik=&status=draft,error&area=&id_event=&limit=
  /// -> riwayat cetak + `summary` (total/draft/printed/error/dibatalkan)
  static const String printHistory = '/sto/print-history';

  /// POST { nik, id_tag, reason } -> pengajuan pembatalan tercatat di server
  /// (tag BELUM dibatalkan - `is_canceled` tidak disentuh).
  static const String cancelRequest = '/sto/cancel-request';

  /// POST { nik (admin), id_tag } -> pengajuan pembatalan ditarik kembali
  static const String cancelReject = '/sto/cancel-reject';

  /// GET ?nik=(admin)&area=&limit= -> antrean pengajuan pembatalan yang
  /// masih menunggu keputusan (is_canceled = 2).
  static const String cancelRequests = '/sto/cancel-requests';

  /// POST { nik (admin), id_tag } -> pengajuan disetujui, tag dibatalkan
  static const String cancelApprove = '/sto/cancel-approve';

  /// POST { id_tag, nik, tim, qty, confirm? } -> hasil hitung tersimpan
  static const String scanTag = '/sto/scan-tag';

  /// POST { id_tag } (string atau array) -> is_canceled = 1
  static const String cancelTag = '/sto/cancel-tag';

  /// GET ?area=&area[]=&q=&limit= -> master part (tanpa gerbang admin)
  static const String partList = '/sto/part-list';

  // --------------------------------------------------------------- laporan
  /// GET ?nik=&tim=&area=&id_tag=&start_date=&end_date=&limit=
  static const String scanHistory = '/sto/scan-history';

  /// GET ?start_date=&end_date=  (wajib keduanya)
  static const String summaryArea = '/sto/summary-area';
  static const String summaryPart = '/sto/summary-part';

  /// Warisan: POST { ids[] } - pembatalan berdasarkan id_tag_ok lama.
  static const String cancelTagOk = '/sto/cancel-tag-ok';
}
