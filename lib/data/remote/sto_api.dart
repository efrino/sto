import '../models/app_user.dart';
import '../models/part_item.dart';
import '../models/print_batch.dart';
import '../models/pengajuan_batal.dart';
import '../models/print_entry.dart';
import '../models/sto_count.dart';
import '../../core/config/app_config.dart';
import '../models/chat_message.dart';
import '../models/sto_tag.dart';
import '../models/tag_ok.dart';
import 'api_client.dart';
import 'api_endpoints.dart';

/// Blok nomor urut yang dipesan ke server sebelum tag dibuat.
class SequenceReservation {
  const SequenceReservation({
    required this.prefix,
    required this.start,
    required this.end,
    this.fromServer = true,
  });

  final String prefix;
  final int start;
  final int end;

  /// false = nomor diambil dari counter lokal (mode offline).
  final bool fromServer;

  int get length => end - start + 1;
}

/// Dilempar saat print-tag menemukan lebih dari satu item untuk kriteria
/// pencarian; pemanggil harus meminta operator memilih salah satu `id_item`.
class ApiMultipleItemException extends ApiException {
  ApiMultipleItemException(super.message, {required this.candidates});

  final List<Map<String, dynamic>> candidates;
}

/// Dilempar saat backend membalas `confirm`: aksinya ditahan sampai
/// dipertegas, dan belum ada yang berubah di server.
class ApiConfirmRequiredException extends ApiException {
  ApiConfirmRequiredException(super.message);
}

/// Kontrak API aplikasi. Satu implementasi: [HttpStoApi], backend MAJSF
/// (`api/Sto.php`) di 192.168.10.67.
abstract class StoApi {
  /// [deviceId] = `devices.id` di server. Bila dikirim, backend sekaligus
  /// memasangkan NIK ini ke perangkat tersebut (`users.device_id`), jadi
  /// pairing tercatat di server - bukan hanya di perangkat.
  /// [androidId] wajib: server mencocokkannya dengan perangkat yang
  /// terdaftar pada NIK tersebut dan menolak 403 bila tidak cocok. Login
  /// hanya memverifikasi - penugasan perangkat lewat register/user-update.
  Future<AppUser> login(
    String nik, {
    String? password,
    String? androidId,
  });

  /// Master part dari `part-list`. [areas] menyaring per area kerja -
  /// kosong berarti seluruh area.
  Future<List<PartItem>> fetchParts({
    String? keyword,
    DateTime? updatedSince,
    List<String> areas,
    int limit,
  });

  /// Membuat SATU tag di server; nomornya (`id_tag`) dibuat server.
  Future<Map<String, dynamic>> printTag({
    required String area,
    String? partNumber,
    String? jobNumber,
    int? itemId,
    int? eventId,
    String? nik,
  });

  Future<SequenceReservation> reserveSequence({
    required int qty,
    required String area,
    required String nik,
  });

  Future<void> createBatch(PrintBatch batch, List<StoTag> tags);

  /// Menandai lembaran tag benar-benar keluar dari printer.
  Future<void> confirmPrint(StoTag tag);

  /// Melaporkan percobaan cetak yang gagal - tag tetap ada di server dengan
  /// keadaan `error` beserta alasannya, jadi bisa dicetak ulang atau
  /// dibatalkan admin.
  Future<void> reportPrintFailed(StoTag tag, String message);

  /// Setelan printer bersama dari server, sebagai nama -> nilai.
  ///
  /// Angkanya milik bersama, bukan milik perangkat: selama disimpan di
  /// masing-masing handheld, hasil cetak antar operator berbeda-beda.
  Future<Map<String, String>> fetchPrinterSetting(String nik);

  /// Menyimpan setelan printer. Server menolak NIK non-admin.
  Future<Map<String, String>> savePrinterSetting(
    String adminNik,
    Map<String, Object> setelan,
  );

  /// Riwayat cetak + ringkasannya, langsung dari server.
  Future<PrintHistory> fetchPrintHistory({
    required String nik,
    List<PrintState> statuses,
    String? keyword,
    int limit,
  });

  Future<void> cancelTag(StoTag tag, String reason);

  /// Operator mengajukan pembatalan tag tercetak (menunggu persetujuan admin).
  Future<void> requestCancelTag(StoTag tag, String reason);

  /// Admin menolak pengajuan pembatalan.
  Future<void> rejectCancelTag(StoTag tag);

  /// Antrean pengajuan pembatalan yang menunggu keputusan admin.
  ///
  /// Datanya milik server: pengajuan bisa datang dari handheld mana pun,
  /// jadi tidak mungkin dibaca dari catatan perangkat yang sedang dipakai.
  /// Tiap baris membawa jejak tag-nya (keadaan cetak + hasil hitung) supaya
  /// admin memutuskan dengan tahu apa yang ikut hilang.
  Future<List<PengajuanBatal>> fetchCancelRequests(
    String adminNik, {
    int limit,
  });

  /// Detail tag untuk halaman scan - dipakai bila tagnya dicetak perangkat
  /// lain sehingga tidak ada di database lokal. null = tidak ditemukan.
  Future<Map<String, dynamic>?> fetchTagDetail(String tagNo, {String? nik});

  /// Mengirim hasil hitung STO: { nik, tag_no, tim, qty }.
  Future<void> submitCount(Map<String, dynamic> payload);

  // -------------------------------------------------------------- pesan
  /// Daftar percakapan beserta jumlah pesan belum dibaca.
  Future<List<ChatThread>> fetchChatThreads(String nik);

  /// Isi satu percakapan; [afterId] > 0 hanya mengambil yang lebih baru.
  Future<List<ChatMessage>> fetchChatMessages({
    required String nik,
    required String thread,
    int afterId,
    int limit,
  });

  /// Mengirim satu pesan. Melempar [ApiException] bila ditolak penjagaan
  /// spam server - pesannya sudah berupa kalimat yang bisa ditampilkan.
  Future<ChatMessage> sendChat({
    required String nik,
    required String thread,
    required String body,
  });

  /// Menandai percakapan sudah dibaca sampai [lastId].
  Future<void> markChatRead({
    required String nik,
    required String thread,
    required int lastId,
  });

  /// Membisukan user selama [menit]; 0 melepas pembisuan (admin).
  Future<void> muteChat({
    required String nik,
    required String nikUser,
    required int menit,
  });

  // ------------------------------------------------------------- tag OK
  /// Satu Tag OK beserta keadaannya. Melempar [ApiException] bila tidak ada.
  Future<TagOk> fetchTagOk(String nik, String idTagOk);

  /// Detail tag dari sumber produksi, untuk tag yang belum terdaftar pada
  /// STO. Melempar [ApiException] bila tagnya memang tidak ada.
  Future<TagOk> fetchTagOkPrepare(String nik, String idTagOk);

  /// Menyiapkan Tag OK: menandainya siap dihitung.
  ///
  /// [keterangan] dikirim untuk tag yang belum terdaftar - job number, qty
  /// kanban, project, dan customer tidak ada di tabel sumber, jadi ikut dari
  /// hasil [fetchTagOkPrepare] supaya barisnya lengkap sejak didaftarkan.
  Future<TagOk> openTagOk(String nik, String idTagOk, {TagOk? keterangan});

  /// Mencatat hasil hitung fisik lalu menutup Tag OK.
  Future<TagOk> scanTagOk(String nik, String idTagOk, int qty);

  /// Daftar Tag OK; [terbuka] null berarti semua keadaan.
  Future<List<TagOk>> fetchTagOkList({
    required String nik,
    bool? terbuka,
    String? keyword,
    String? milik,
    int? batal,
    int limit,
  });

  /// Mengajukan pembatalan Tag OK, atau - bila [keputusan] diisi - memutuskan
  /// pengajuan yang menunggu. [keputusan]: 'setuju' atau 'tolak'.
  Future<TagOk> cancelTagOk({
    required String nik,
    required String idTagOk,
    String alasan = '',
    String? keputusan,
  });

  /// Riwayat scan dari server. [nik] kosong berarti semua pencatat.
  Future<List<StoCount>> fetchScanHistory({
    String? nik,
    String? team,
    String? area,
    String? keyword,
    DateTime? start,
    DateTime? end,
    int limit,
  });

  // --------------------------------------------------- perangkat & event
  // Sepuluh operasi di bawah hanya untuk admin: backend menolak `nik` yang
  // bukan admin, jadi NIK admin selalu ikut dikirim.

  /// Mendaftarkan akun baru. `created_by` berisi NIK admin yang
  /// mendaftarkan - itulah gerbang aksesnya, sekaligus jejak siapa yang
  /// membuat akun. Hak akses menu tidak ikut dikirim: server belum
  /// membacanya, jadi tetap disimpan di perangkat.
  Future<AppUser> registerUser(
    AppUser user, {
    required String createdBy,
    int? deviceId,
  });

  /// Daftar akun dari server. [deviceId] menyaring per perangkat - dipakai
  /// halaman Perangkat untuk menampilkan siapa saja yang terpasang.
  Future<List<AppUser>> fetchUsers(
    String adminNik, {
    int? deviceId,
    String? keyword,
    int limit = 200,
  });

  /// Ubah sebagian data akun. [areas] null = daftar areanya tidak disentuh;
  /// daftar yang dikirim MENGGANTI seluruh area user.
  ///
  /// NIK tidak bisa diubah - `sto_data.nik_a/nik_b` menyimpannya sebagai teks
  /// biasa, jadi mengubahnya membuat riwayat scan lama yatim. Hapus akun lalu
  /// daftarkan yang baru bila NIK-nya keliru.
  ///
  /// [deviceId] `0` melepas perangkat dari user, null berarti tidak disentuh.
  Future<Map<String, dynamic>> updateUser({
    required String adminNik,
    required String targetNik,
    String? role,
    String? team,
    int? deviceId,
    List<String>? areas,
    List<String>? permissions,
  });

  /// Hapus akun. Server membalas `confirm` bila user itu pernah mencetak tag.
  Future<Map<String, dynamic>> deleteUser({
    required String adminNik,
    required String targetNik,
    bool force = false,
  });

  Future<List<Map<String, dynamic>>> fetchDevices(String adminNik);

  Future<Map<String, dynamic>?> fetchDeviceDetail(
    String adminNik, {
    int? deviceId,
    String? androidId,
  });

  Future<Map<String, dynamic>> createDevice({
    required String adminNik,
    required String name,
    required String androidId,
  });

  Future<Map<String, dynamic>> updateDevice({
    required String adminNik,
    required int deviceId,
    String? name,
    String? androidId,
  });

  Future<Map<String, dynamic>> deleteDevice({
    required String adminNik,
    required int deviceId,
    bool force = false,
  });

  Future<List<Map<String, dynamic>>> fetchEvents(String adminNik);

  Future<Map<String, dynamic>> createEvent({
    required String adminNik,
    required String name,
    required DateTime start,
    required DateTime end,
    bool berjalan = true,
  });

  Future<Map<String, dynamic>> updateEvent({
    required String adminNik,
    required int eventId,
    String? name,
    DateTime? start,
    DateTime? end,
    bool? berjalan,
  });

  Future<Map<String, dynamic>> deleteEvent({
    required String adminNik,
    required int eventId,
    bool force = false,
  });
}

/// Implementasi HTTP untuk backend STO yang sudah ada.
///
/// Backend menyediakan sembilan endpoint (register, login, print-tag,
/// scan-tag, cancel-tag, scan-history, summary-area, summary-part,
/// cancel-tag-ok). Fitur aplikasi yang belum punya endpoint sengaja melempar
/// [ApiNotAvailableException] supaya pemanggil tahu harus memakai data lokal,
/// bukan mengira servernya sedang bermasalah.
class HttpStoApi implements StoApi {
  HttpStoApi(this._client);

  final ApiClient _client;

  // ------------------------------------------------------------------ akun
  /// Login sekaligus memasangkan NIK ke perangkat.
  ///
  /// `device_id` hanya dikirim bila perangkat ini memang sudah terdaftar
  /// admin: mengirim id yang tidak dikenal server justru menggagalkan login.
  @override
  Future<AppUser> login(
    String nik, {
    String? password,
    String? androidId,
  }) async {
    final body = await _client.post(ApiEndpoints.login, {
      'nik': nik,
      // Wajib: server menolak 403 bila ANDROID_ID ini bukan perangkat yang
      // terdaftar pada NIK tsb. Login TIDAK menugaskan perangkat - kalau
      // bisa, pemeriksaan ini jadi tidak ada gunanya.
      'android_id': ?androidId,
    });
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons login tidak dikenali.');
    }
    _ingatPerangkat(data);
    final user = _userFromApi(data);
    if (user.nik.isEmpty) throw ApiException('NIK tidak terdaftar.');
    return user;
  }

  /// Mendaftarkan user baru (dipakai admin dari menu Setting > User).
  ///
  /// [deviceId] opsional - bila diisi, user langsung terpasang pada perangkat
  /// tersebut (harus sudah terdaftar lewat device-create).
  @override
  Future<AppUser> registerUser(
    AppUser user, {
    required String createdBy,
    int? deviceId,
  }) async {
    final body = await _client.post(ApiEndpoints.register, {
      // `nik` di sini adalah akun yang didaftarkan, jadi gerbang adminnya
      // bernama `created_by` - sekaligus jejak siapa yang mendaftarkan.
      'created_by': createdBy,
      'nik': user.nik,
      'role': user.role.name,
      if (user.hasTeam) 'tim': user.team,
      'permissions': user.permissions.map((p) => p.name).toList(),
      'device_id': ?deviceId,
      if (user.areas.isNotEmpty) 'area': user.areas,
    });
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons register tidak dikenali.');
    }
    _ingatPerangkat(data);
    return _userFromApi(data);
  }

  /// Perangkat yang terpasang pada user hasil login terakhir (bila ada).
  /// Diisi dari balasan login/register: `device_id`, `device_name`,
  /// `android_id`.
  Map<String, dynamic>? perangkatTerpasang;

  /// Mencatat perangkat yang terpasang pada user hasil LOGIN/REGISTER.
  ///
  /// Sengaja dipanggil terpisah, bukan dari [_userFromApi]: `user-list`
  /// memetakan puluhan baris lewat fungsi yang sama, dan dulu tiap baris ikut
  /// menimpa [perangkatTerpasang] - sehingga yang tersimpan adalah perangkat
  /// milik user TERAKHIR pada daftar, lalu dipakai sebagai perangkat sesi ini.
  void _ingatPerangkat(Map<String, dynamic> data) {
    final deviceId = int.tryParse('${data['device_id'] ?? ''}');
    perangkatTerpasang = deviceId == null
        ? null
        : {
            'device_id': deviceId,
            'device_name': '${data['device_name'] ?? ''}',
            'android_id': '${data['android_id'] ?? ''}',
          };
  }

  /// Backend menyimpan identitas seadanya: nik, role, tim, dan daftar area.
  /// Nama karyawan belum ada di tabel `users`, jadi sementara memakai NIK.
  AppUser _userFromApi(Map<String, dynamic> data) {
    final role = '${data['role'] ?? ''}'.trim().toLowerCase();
    return AppUser(
      nik: '${data['nik'] ?? ''}'.trim().toUpperCase(),
      name: '${data['name'] ?? data['nik'] ?? '-'}'.trim(),
      department: '${data['department'] ?? '-'}',
      section: '${data['section'] ?? '-'}',
      role: role == 'admin' ? UserRole.admin : UserRole.operator,
      areas: _areas(data['area'] ?? data['areas']),
      team: AppUser.parseTeam(data['tim'] ?? data['team']),
      // Kosong berarti KOSONG - admin memang belum (atau baru saja berhenti)
      // memberi menu apa pun.
      //
      // Dulu ini diperlakukan sebagai "semua menu terbuka", peninggalan masa
      // server belum menyimpan hak akses. Akibatnya nyata: admin mencabut
      // semua centang, server menyimpan kosong, lalu aplikasi membacanya
      // kembali sebagai SEMUA menu - suntingan izinnya seolah tidak pernah
      // tersimpan. Admin sendiri tetap terbuka lewat AppUser.can().
      permissions: AppPermission.parse(data['permissions']),
    );
  }

  /// `area` bisa berupa ["IFPD","IFPP"] maupun [{"area":"IFPD"}, ...].
  List<String> _areas(Object? raw) {
    if (raw is! List) return AppUser.parseAreas(raw);
    return raw
        .map((e) => e is Map ? '${e['area'] ?? ''}' : '$e')
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Future<List<AppUser>> fetchUsers(
    String adminNik, {
    int? deviceId,
    String? keyword,
    int limit = 200,
  }) async {
    final body = await _client.get(ApiEndpoints.userList, query: {
      'nik': adminNik,
      'id_device': deviceId,
      'q': keyword,
      'limit': limit,
    });

    var rows = _rows(body);

    // `id_device` DIABAIKAN server (diuji 4 Sep 2026: keempat perangkat
    // membalas ketujuh user yang sama), jadi tanpa saringan ini halaman
    // Perangkat menampilkan SELURUH NIK sebagai terpasang di setiap
    // perangkat. Balasannya sudah memuat `device_id` per baris, jadi
    // penyaringannya dikerjakan di sini sampai server diperbaiki.
    if (deviceId != null && deviceId != 0) {
      rows = rows
          .where((r) => int.tryParse('${r['device_id'] ?? ''}') == deviceId)
          .toList();
    }

    return rows.map(_userFromApi).toList();
  }

  @override
  Future<Map<String, dynamic>> updateUser({
    required String adminNik,
    required String targetNik,
    String? role,
    String? team,
    int? deviceId,
    List<String>? areas,
    List<String>? permissions,
  }) async {
    final body = await _client.post(ApiEndpoints.userUpdate, {
      'nik': adminNik,
      'nik_user': targetNik,
      'role': ?role,
      // String kosong = kosongkan; null = jangan disentuh. Keduanya berbeda
      // arti di server, jadi jangan disatukan.
      'tim': ?team,
      if (deviceId != null) 'device_id': deviceId == 0 ? '' : deviceId,
      'area': ?areas,
      'permissions': ?permissions,
    });
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons user-update tidak dikenali.');
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> deleteUser({
    required String adminNik,
    required String targetNik,
    bool force = false,
  }) async {
    final body = await _client.post(ApiEndpoints.userDelete, {
      'nik': adminNik,
      'nik_user': targetNik,
      if (force) 'force': true,
    });
    if (body is Map && body['status'] == 'confirm') {
      throw ApiConfirmRequiredException(
        '${body['message'] ?? 'Perlu ditegaskan sebelum dihapus.'}',
      );
    }
    return body is Map<String, dynamic> ? body : const {};
  }

  // -------------------------------------------------------------- perangkat
  // Seluruh CRUD device & event wajib menyertakan NIK admin; backend yang
  // memeriksa perannya, aplikasi tinggal mengirimkannya.

  /// Daftar perangkat terdaftar beserta jumlah user yang terpasang padanya.
  @override
  Future<List<Map<String, dynamic>>> fetchDevices(String adminNik) async {
    final body = await _client.get(
      ApiEndpoints.deviceList,
      query: {'nik': adminNik},
    );
    return _rows(body);
  }

  @override
  Future<Map<String, dynamic>?> fetchDeviceDetail(
    String adminNik, {
    int? deviceId,
    String? androidId,
  }) async {
    final body = await _client.get(ApiEndpoints.deviceDetail, query: {
      'nik': adminNik,
      'id_device': deviceId,
      'android_id': androidId,
    });
    return _data(body);
  }

  /// Mendaftarkan perangkat baru. `androidId` harus unik - satu perangkat
  /// fisik tidak bisa didaftarkan dua kali (backend membalas 409).
  @override
  Future<Map<String, dynamic>> createDevice({
    required String adminNik,
    required String name,
    required String androidId,
  }) async {
    final body = await _client.post(ApiEndpoints.deviceCreate, {
      'nik': adminNik,
      'name': name,
      'android_id': androidId,
    });
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons device-create tidak dikenali.');
    }
    return data;
  }

  /// Ubah sebagian: hanya field yang dikirim yang disentuh.
  @override
  Future<Map<String, dynamic>> updateDevice({
    required String adminNik,
    required int deviceId,
    String? name,
    String? androidId,
  }) async {
    if (name == null && androidId == null) {
      throw ApiException('Tidak ada field perangkat yang diubah.');
    }
    final body = await _client.post(ApiEndpoints.deviceUpdate, {
      'nik': adminNik,
      'id_device': deviceId,
      'name': ?name,
      'android_id': ?androidId,
    });
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons device-update tidak dikenali.');
    }
    return data;
  }

  /// Menghapus perangkat. Perangkat yang masih dipakai user dibalas
  /// `confirm` - ulangi dengan [force] true bila memang disengaja.
  @override
  Future<Map<String, dynamic>> deleteDevice({
    required String adminNik,
    required int deviceId,
    bool force = false,
  }) async {
    final body = await _client.post(ApiEndpoints.deviceDelete, {
      'nik': adminNik,
      'id_device': deviceId,
      if (force) 'force': true,
    });
    if (body is Map && body['status'] == 'confirm') {
      throw ApiConfirmRequiredException(
        '${body['message'] ?? 'Perlu ditegaskan sebelum dihapus.'}',
      );
    }
    return body is Map<String, dynamic> ? body : const {};
  }

  // ------------------------------------------------------------------ event
  @override
  Future<List<Map<String, dynamic>>> fetchEvents(String adminNik) async {
    final body = await _client.get(
      ApiEndpoints.eventList,
      query: {'nik': adminNik},
    );
    return _rows(body);
  }

  Future<Map<String, dynamic>?> fetchEventDetail(
    String adminNik,
    int eventId,
  ) async {
    final body = await _client.get(ApiEndpoints.eventDetail, query: {
      'nik': adminNik,
      'id_event': eventId,
    });
    return _data(body);
  }

  @override
  Future<Map<String, dynamic>> createEvent({
    required String adminNik,
    required String name,
    required DateTime start,
    required DateTime end,
    bool berjalan = true,
  }) async {
    final body = await _client.post(ApiEndpoints.eventCreate, {
      'nik': adminNik,
      'event_name': name,
      'start_date': _date(start),
      'end_date': _date(end),
      'status': berjalan ? 1 : 0,
    });
    // Hanya boleh ada satu event berjalan: server menahan permintaan ini
    // sampai admin menegaskan event mana yang harus ditutup.
    _pastikanBukanConfirm(body);
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons event-create tidak dikenali.');
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> updateEvent({
    required String adminNik,
    required int eventId,
    String? name,
    DateTime? start,
    DateTime? end,
    bool? berjalan,
  }) async {
    final body = await _client.post(ApiEndpoints.eventUpdate, {
      'nik': adminNik,
      'id_event': eventId,
      'event_name': ?name,
      'start_date': ?_date(start),
      'end_date': ?_date(end),
      if (berjalan != null) 'status': berjalan ? 1 : 0,
    });
    _pastikanBukanConfirm(body);
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons event-update tidak dikenali.');
    }
    return data;
  }

  /// Event yang sudah dipakai tag dibalas `confirm`; ulangi dengan [force]
  /// true hanya bila memang disengaja.
  @override
  Future<Map<String, dynamic>> deleteEvent({
    required String adminNik,
    required int eventId,
    bool force = false,
  }) async {
    final body = await _client.post(ApiEndpoints.eventDelete, {
      'nik': adminNik,
      'id_event': eventId,
      if (force) 'force': true,
    });
    if (body is Map && body['status'] == 'confirm') {
      throw ApiConfirmRequiredException(
        '${body['message'] ?? 'Perlu ditegaskan sebelum dihapus.'}',
      );
    }
    return body is Map<String, dynamic> ? body : const {};
  }

  // ------------------------------------------------------------------- tag
  /// Membuat SATU tag di server. Backend memberi nomornya sendiri (`id_tag`),
  /// jadi aplikasi tidak perlu memesan blok nomor urut lebih dulu.
  @override
  Future<Map<String, dynamic>> printTag({
    required String area,
    String? partNumber,
    String? jobNumber,
    int? itemId,
    int? eventId,
    String? nik,
  }) async {
    final body = await _client.post(ApiEndpoints.printTag, {
      'area': area,
      if (partNumber != null && partNumber.isNotEmpty) 'part_number': partNumber,
      if (jobNumber != null && jobNumber.isNotEmpty) 'job_number': jobNumber,
      'id_item': ?itemId,
      'id_event': ?eventId,
      if (nik != null && nik.isNotEmpty) 'nik': nik,
    });

    // status "multiple" = pencarian menemukan beberapa item; belum ada tag
    // yang dibuat, pemanggil harus memilih lewat id_item.
    if (body is Map && body['status'] == 'multiple') {
      throw ApiMultipleItemException(
        '${body['message'] ?? 'Pencarian menemukan lebih dari satu item.'}',
        candidates: (body['data'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            const [],
      );
    }

    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons print-tag tidak dikenali.');
    }
    return data;
  }

  @override
  Future<SequenceReservation> reserveSequence({
    required int qty,
    required String area,
    required String nik,
  }) async {
    // Nomor tag dibuat backend saat print-tag; tidak ada endpoint pemesanan.
    throw ApiNotAvailableException('Pemesanan nomor urut');
  }

  @override
  Future<void> createBatch(PrintBatch batch, List<StoTag> tags) async {
    throw ApiNotAvailableException('Pengiriman batch tag');
  }

  @override
  Future<void> confirmPrint(StoTag tag) async {
    await _client.post(ApiEndpoints.printStatus, {
      'nik': tag.createdBy,
      'id_tag': tag.tagNo,
      'status': 'printed',
    });
  }

  @override
  Future<void> reportPrintFailed(StoTag tag, String message) async {
    await _client.post(ApiEndpoints.printStatus, {
      'nik': tag.createdBy,
      'id_tag': tag.tagNo,
      'status': 'error',
      'message': message,
    });
  }

  @override
  Future<Map<String, String>> fetchPrinterSetting(String nik) async {
    final body = await _client.get(
      ApiEndpoints.printerSetting,
      query: {'nik': nik},
    );
    return _setelanDari(body);
  }

  @override
  Future<Map<String, String>> savePrinterSetting(
    String adminNik,
    Map<String, Object> setelan,
  ) async {
    final body = await _client.post(ApiEndpoints.printerSetting, {
      'nik': adminNik,
      ...setelan,
    });
    return _setelanDari(body);
  }

  Map<String, String> _setelanDari(Object? body) {
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final data = map['data'];
    if (data is! Map) return const {};
    return {for (final e in data.entries) '${e.key}': '${e.value}'};
  }

  @override
  Future<PrintHistory> fetchPrintHistory({
    required String nik,
    List<PrintState> statuses = const [],
    String? keyword,
    int limit = 100,
  }) async {
    final body = await _client.get(ApiEndpoints.printHistory, query: {
      'nik': nik,
      if (statuses.isNotEmpty) 'status': statuses.map((e) => e.name).join(','),
      // Dicari server atas seluruh riwayat, bukan menyaring baris yang
      // kebetulan sudah terambil.
      if ((keyword ?? '').trim().isNotEmpty) 'q': keyword!.trim(),
      'limit': '$limit',
    });

    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final ringkas = map['summary'];

    return PrintHistory(
      entries: _rows(body).map(PrintEntry.fromServer).toList(),
      summary: ringkas is Map
          ? {
              for (final e in ringkas.entries)
                '${e.key}': int.tryParse('${e.value}') ?? 0,
            }
          : const {},
    );
  }

  @override
  Future<void> cancelTag(StoTag tag, String reason) async {
    // Tag yang lewat pengajuan disetujui lewat cancel-approve - hanya di
    // sana jejak "disetujui siapa" ikut tersimpan. Pembatalan langsung
    // (tanpa pengajuan) tetap memakai cancel-tag.
    //
    // Penandanya adalah ADA penyetujunya, bukan status lokalnya: begitu admin
    // menekan Setujui, status lokal sudah berubah jadi DIBATALKAN, sehingga
    // memeriksa `pendingCancel` di sini tidak akan pernah benar.
    final penyetuju = tag.cancelApprovedBy ?? '';
    if (penyetuju.isNotEmpty) {
      await _client.post(ApiEndpoints.cancelApprove, {
        'nik': penyetuju,
        'id_tag': tag.tagNo,
      });
      return;
    }
    await _client.post(ApiEndpoints.cancelTag, {'id_tag': tag.tagNo});
  }

  /// Membatalkan banyak tag sekaligus (maks 5.000 per permintaan).
  Future<Map<String, dynamic>> cancelTags(List<String> tagNumbers) async {
    final body = await _client.post(
      ApiEndpoints.cancelTag,
      {'id_tag': tagNumbers},
    );
    return body is Map<String, dynamic> ? body : const {};
  }

  @override
  Future<void> requestCancelTag(StoTag tag, String reason) async {
    await _client.post(ApiEndpoints.cancelRequest, {
      'nik': tag.cancelRequestedBy ?? tag.createdBy,
      'id_tag': tag.tagNo,
      'reason': reason,
    });
  }

  @override
  Future<List<PengajuanBatal>> fetchCancelRequests(
    String adminNik, {
    int limit = 100,
  }) async {
    final body = await _client.get(ApiEndpoints.cancelRequests, query: {
      'nik': adminNik,
      'limit': '$limit',
    });
    return _rows(body)
        .map((row) => PengajuanBatal.fromServer(row, _tagPengajuanDari(row)))
        .toList();
  }

  /// Baris `cancel-requests` memakai bentuk format_tag() milik server.
  StoTag _tagPengajuanDari(Map<String, dynamic> row) {
    DateTime? waktu(Object? nilai) {
      final teks = '${nilai ?? ''}'.trim();
      return teks.isEmpty ? null : DateTime.tryParse(teks);
    }

    return StoTag(
      tagNo: '${row['id_tag'] ?? ''}',
      sequence: 0,
      batchId: 'SERVER',
      partNumber: '${row['part_number'] ?? ''}',
      jobNumber: '${row['job_number'] ?? ''}',
      partName: '${row['material_description'] ?? '-'}',
      customer: '${row['customer'] ?? '-'}',
      model: '${row['model'] ?? '-'}',
      area: '${row['area'] ?? '-'}',
      partType: PartItem.normalizeType(row['type']),
      eventId: '${row['id_event'] ?? ''}',
      status: TagStatus.pendingCancel,
      createdBy: '${row['created_by'] ?? '-'}',
      createdAt: waktu(row['created_at']) ?? DateTime.now(),
      printedAt: waktu(row['printed_at']),
      cancelReason: '${row['cancel_reason'] ?? ''}',
      // `cancel_requested_by` dari server berisi users.id; NIK-nya dikirim
      // terpisah supaya layar admin menampilkan orang, bukan angka.
      cancelRequestedBy: '${row['cancel_requested_nik'] ?? ''}'.trim().isEmpty
          ? '${row['cancel_requested_by'] ?? ''}'
          : '${row['cancel_requested_nik']}',
      cancelRequestedAt: waktu(row['cancel_requested_at']),
    );
  }

  @override
  Future<void> rejectCancelTag(StoTag tag) async {
    await _client.post(ApiEndpoints.cancelReject, {
      // Server menolak NIK non-admin, jadi yang dikirim adalah penolaknya -
      // tercatat di `cancel_approved_by` milik alur persetujuan.
      'nik': tag.cancelApprovedBy ?? tag.createdBy,
      'id_tag': tag.tagNo,
    });
  }

  // --------------------------------------------------------------- laporan
  @override
  Future<List<PartItem>> fetchParts({
    String? keyword,
    DateTime? updatedSince,
    List<String> areas = const [],
    int limit = 1000,
  }) async {
    final body = await _client.get(ApiEndpoints.partList, query: {
      // Server menerima satu area atau `area[]` berkali-kali; dipisah koma
      // juga diterima, dan itu yang paling ringkas lewat query string.
      if (areas.isNotEmpty) 'area': areas.join(','),
      'q': keyword,
      'limit': limit,
    });

    return _rows(body)
        .map(PartItem.fromServer)
        .where((p) => p.jobNumber.isNotEmpty || p.partNumber.isNotEmpty)
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchTagDetail(String tagNo, {String? nik}) async {
    final cleanTag = tagNo.trim();
    if (cleanTag.isEmpty) return null;

    final queryNik = (nik ?? '').trim();

    // 1. Endpoint resmi: GET /sto/tag-detail?id_tag=...
    try {
      final body = await _client.get(ApiEndpoints.tagDetail, query: {
        'id_tag': cleanTag,
        if (queryNik.isNotEmpty) 'nik': queryNik,
      });
      if (body is Map) {
        final data = body['data'];
        if (data is Map && data.isNotEmpty) {
          return data.cast<String, dynamic>();
        }
        if (data is List && data.isNotEmpty) {
          final first = data.first;
          if (first is Map) return first.cast<String, dynamic>();
        }
        if (body.containsKey('id_tag') || body.containsKey('part_number')) {
          return body.cast<String, dynamic>();
        }
      }
    } catch (_) {
      // Fallback bila /sto/tag-detail gagal (404 atau belum tersedia)
    }

    // 2. Fallback: Cari di riwayat cetak (print-history)
    try {
      final printBody = await _client.get(ApiEndpoints.printHistory, query: {
        if (queryNik.isNotEmpty) 'nik': queryNik,
        'q': cleanTag,
        'limit': '5',
      });
      final printRows = _rows(printBody);
      final exact = printRows.firstWhere(
        (r) =>
            '${r['id_tag'] ?? r['tag_no'] ?? ''}'.trim().toUpperCase() ==
            cleanTag.toUpperCase(),
        orElse: () =>
            printRows.isNotEmpty ? printRows.first : const <String, dynamic>{},
      );
      if (exact.isNotEmpty) return exact;
    } catch (_) {
      // Fallback bila print-history gagal / offline
    }

    // 3. Fallback: Cari di riwayat scan (scan-history)
    try {
      final body = await _client.get(ApiEndpoints.scanHistory, query: {
        if (queryNik.isNotEmpty) 'nik': queryNik,
        'id_tag': cleanTag,
        'limit': '1',
      });
      final rows = _rows(body);
      if (rows.isNotEmpty) return rows.first;
    } catch (_) {
      // Abaikan error
    }

    return null;
  }

  @override
  Future<void> submitCount(Map<String, dynamic> payload) async {
    final tagNo = '${payload['tag_no'] ?? payload['id_tag'] ?? ''}';
    await _client.post(ApiEndpoints.scanTag, {
      'id_tag': tagNo,
      'nik': payload['nik'],
      'tim': AppUser.parseTeam(payload['tim'] ?? payload['team']),
      'qty': payload['qty'],
      // Aplikasi sudah menjaga aturannya sendiri (koreksi hanya oleh pencatat
      // yang sama), jadi kiriman ulang memang dimaksudkan menimpa.
      'confirm': true,
    });
  }

  /// Riwayat scan dari server (semua perangkat), bukan hanya perangkat ini.
  ///
  /// Hasil hitung tim A dan tim B bisa datang dari handheld berbeda, jadi
  /// catatan satu perangkat tidak pernah utuh - karena itu daftarnya dibaca
  /// dari sini, bukan dari sqflite.
  @override
  Future<List<ChatThread>> fetchChatThreads(String nik) async {
    final body = await _client.get(ApiEndpoints.chatThreads, query: {
      'nik': nik,
    });
    return _rows(body).map(ChatThread.fromServer).toList();
  }

  @override
  Future<List<ChatMessage>> fetchChatMessages({
    required String nik,
    required String thread,
    int afterId = 0,
    int limit = 50,
  }) async {
    final body = await _client.get(ApiEndpoints.chatMessages, query: {
      'nik': nik,
      'thread': thread,
      if (afterId > 0) 'after_id': '$afterId',
      'limit': '$limit',
    });
    return _rows(body).map(ChatMessage.fromServer).toList();
  }

  @override
  Future<ChatMessage> sendChat({
    required String nik,
    required String thread,
    required String body,
  }) async {
    final hasil = await _client.post(ApiEndpoints.chatSend, {
      'nik': nik,
      'thread': thread,
      'body': body,
    });
    final data = _data(hasil);
    if (data == null) {
      throw ApiException('Format respons pesan tidak dikenali.');
    }
    return ChatMessage.fromServer(data);
  }

  @override
  Future<void> markChatRead({
    required String nik,
    required String thread,
    required int lastId,
  }) async {
    await _client.post(ApiEndpoints.chatRead, {
      'nik': nik,
      'thread': thread,
      'last_id': lastId,
    });
  }

  @override
  Future<void> muteChat({
    required String nik,
    required String nikUser,
    required int menit,
  }) async {
    await _client.post(ApiEndpoints.chatMute, {
      'nik': nik,
      'nik_user': nikUser,
      'menit': menit,
    });
  }

  @override
  Future<TagOk> fetchTagOk(String nik, String idTagOk) async {
    final body = await _client.get(ApiEndpoints.tagOk, query: {
      'nik': nik,
      'id_tag_ok': idTagOk,
    });
    return _tagOkDari(body);
  }

  @override
  Future<TagOk> fetchTagOkPrepare(String nik, String idTagOk) async {
    final query = {'nik': nik, 'id_tag_ok': idTagOk};
    try {
      return _tagOkDari(
        await _client.get(ApiEndpoints.tagOkPrepare, query: query),
      );
    } on ApiException {
      // Endpoint ini hanya ada di salah satu deployment: server pabrik dan
      // mspin menjalankan salinan kode yang berbeda. Daripada memaksa
      // operator berpindah alamat server, sisi satunya dicoba langsung.
      final cadangan = await _client.getAbsolute(
        AppConfig.serverPilihan.values,
        ApiEndpoints.tagOkPrepare,
        query: query,
      );
      return _tagOkDari(cadangan);
    }
  }

  @override
  Future<TagOk> openTagOk(String nik, String idTagOk, {TagOk? keterangan}) async {
    final body = await _client.post(ApiEndpoints.tagOkOpen, {
      'nik': nik,
      'id_tag_ok': idTagOk,
      if (keterangan != null) ...{
        'process': keterangan.process,
        'job_number': keterangan.jobNumber,
        'qty_kbn': keterangan.qtyKbn,
        'project': keterangan.project,
        'customer': keterangan.customer,
        'area': keterangan.area,
      },
    });
    return _tagOkDari(body);
  }

  @override
  Future<TagOk> scanTagOk(String nik, String idTagOk, int qty) async {
    final body = await _client.post(ApiEndpoints.tagOkScan, {
      'nik': nik,
      'id_tag_ok': idTagOk,
      'qty': qty,
    });
    return _tagOkDari(body);
  }

  @override
  Future<List<TagOk>> fetchTagOkList({
    required String nik,
    bool? terbuka,
    String? keyword,
    String? milik,
    int? batal,
    int limit = 100,
  }) async {
    final body = await _client.get(ApiEndpoints.tagOkList, query: {
      'nik': nik,
      if (terbuka != null) 'open': terbuka ? '1' : '0',
      if ((keyword ?? '').trim().isNotEmpty) 'q': keyword!.trim(),
      if ((milik ?? '').trim().isNotEmpty) 'milik': milik!.trim(),
      if (batal != null) 'batal': '$batal',
      'limit': '$limit',
    });
    return _rows(body).map(TagOk.fromServer).toList();
  }

  @override
  Future<TagOk> cancelTagOk({
    required String nik,
    required String idTagOk,
    String alasan = '',
    String? keputusan,
  }) async {
    final body = await _client.post(ApiEndpoints.tagOkCancel, {
      'nik': nik,
      'id_tag_ok': idTagOk,
      if (alasan.trim().isNotEmpty) 'alasan': alasan.trim(),
      if ((keputusan ?? '').isNotEmpty) 'keputusan': keputusan,
    });
    return _tagOkDari(body);
  }

  TagOk _tagOkDari(Object? body) {
    final data = _data(body);
    if (data == null) {
      throw ApiException('Format respons tag OK tidak dikenali.');
    }
    return TagOk.fromServer(data);
  }

  @override
  Future<List<StoCount>> fetchScanHistory({
    String? nik,
    String? team,
    String? area,
    String? keyword,
    DateTime? start,
    DateTime? end,
    int limit = 100,
  }) async {
    final body = await _client.get(ApiEndpoints.scanHistory, query: {
      'nik': nik,
      'tim': team == null || team.isEmpty ? null : AppUser.parseTeam(team),
      'area': area,
      'start_date': _date(start),
      'end_date': _date(end),
      'limit': limit,
    });

    final rows = _rows(body).map(StoCount.fromServer);
    final cari = (keyword ?? '').trim().toLowerCase();
    if (cari.isEmpty) return rows.toList();

    // `scan-history` belum punya penyaring kata kunci; disaring di sini supaya
    // kotak cari tetap berguna tanpa menunggu endpoint baru.
    return rows
        .where(
          (c) =>
              c.tagNo.toLowerCase().contains(cari) ||
              c.partNumber.toLowerCase().contains(cari) ||
              c.partName.toLowerCase().contains(cari) ||
              c.team.toLowerCase().contains(cari),
        )
        .toList();
  }

  /// Rekap per area untuk rentang tanggal tertentu.
  Future<Map<String, dynamic>> fetchSummaryArea({
    required DateTime start,
    required DateTime end,
  }) =>
      _summary(ApiEndpoints.summaryArea, start, end);

  /// Rekap per part number untuk rentang tanggal tertentu.
  Future<Map<String, dynamic>> fetchSummaryPart({
    required DateTime start,
    required DateTime end,
  }) =>
      _summary(ApiEndpoints.summaryPart, start, end);

  Future<Map<String, dynamic>> _summary(
    String path,
    DateTime start,
    DateTime end,
  ) async {
    final body = await _client.get(path, query: {
      'start_date': _date(start),
      'end_date': _date(end),
    });
    return body is Map<String, dynamic> ? body : const {};
  }

  // -------------------------------------------------------------- pembantu
  /// Melempar [ApiConfirmRequiredException] bila server menahan permintaan
  /// sampai ditegaskan - dipakai aturan "hanya satu event berjalan".
  void _pastikanBukanConfirm(dynamic body) {
    if (body is Map && body['status'] == 'confirm') {
      throw ApiConfirmRequiredException(
        '${body['message'] ?? 'Perlu ditegaskan sebelum disimpan.'}',
      );
    }
  }

  /// Payload utama ada di field `data`; sebagian endpoint menaruhnya langsung
  /// di akar amplop.
  Map<String, dynamic>? _data(dynamic body) {
    if (body is! Map) return null;
    final data = body['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return body.cast<String, dynamic>();
  }

  List<Map<String, dynamic>> _rows(dynamic body) {
    if (body is! Map) return const [];
    final data = body['data'];
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  String? _date(DateTime? value) {
    if (value == null) return null;
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
