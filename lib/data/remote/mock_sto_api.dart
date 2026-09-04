import '../models/app_user.dart';
import '../models/part_item.dart';
import '../models/print_batch.dart';
import '../models/pengajuan_batal.dart';
import '../models/print_entry.dart';
import '../models/sto_count.dart';
import '../models/chat_message.dart';
import '../models/sto_tag.dart';
import '../models/tag_ok.dart';
import 'api_client.dart';
import 'sto_api.dart';

/// Implementasi tiruan supaya seluruh alur (login -> cari -> generate ->
/// preview -> print -> cancel -> sync) bisa dijalankan sebelum API terbit.
///
/// Ganti ke [HttpStoApi] lewat halaman Setting (toggle "Gunakan data dummy")
/// atau ubah [AppConfig.useMockApi] menjadi false.
class MockStoApi implements StoApi {
  MockStoApi({this.lastUsedSequence});

  /// Dipakai untuk melanjutkan penomoran setelah aplikasi ditutup.
  ///
  /// Server asli menyimpan counter-nya sendiri; mock ini hanya hidup di memori,
  /// jadi tanpa ini nomor akan mengulang dari 1 setiap aplikasi dijalankan dan
  /// bentrok dengan tag yang sudah tersimpan (UNIQUE tag_no => DatabaseException).
  /// Di aplikasi nilainya diambil dari nomor tertinggi pada database lokal.
  final Future<int> Function(String prefix)? lastUsedSequence;

  static const Duration _latency = Duration(milliseconds: 450);

  /// Simulasi counter nomor urut milik server.
  int _serverSequence = 0;
  String? _sequencePrefix;

  /// Dipakai hanya bila mode API dinyalakan tetapi server belum ada.
  /// Pada mode simulasi, login divalidasi ke tabel `users` lokal oleh
  /// AuthRepository, bukan ke sini.
  static const Map<String, List<String>> _users = {
    'A.10525': ['EFRINO WAHYU', 'IT', 'SYSTEM DEVELOPMENT', 'admin'],
    'E.9948': ['ADMIN STO', 'IT', 'SYSTEM DEVELOPMENT', 'admin'],
    'A.20431': ['BUDI SANTOSO', 'PPIC', 'INVENTORY CONTROL', 'operator'],
    '11223344': ['SITI RAHMA', 'WAREHOUSE', 'STORAGE', 'operator'],
  };

  static final List<PartItem> _parts = _seedParts();

  @override
  Future<AppUser> login(
    String nik, {
    String? password,
    String? androidId,
  }) async {
    await Future<void>.delayed(_latency);
    final key = nik.trim().toUpperCase();
    if (key.isEmpty) {
      throw ApiException('NIK wajib diisi.');
    }
    if (key == '0000') {
      throw ApiException('NIK tidak terdaftar. Hubungi IT Department.');
    }
    final seed = _users[key];
    return AppUser(
      nik: key,
      name: seed?[0] ?? 'OPERATOR $key',
      department: seed?[1] ?? 'PRODUCTION',
      section: seed?[2] ?? 'STO TEAM',
      role: UserRole.fromName(seed?[3]),
      areas: seed?[3] == 'admin' ? const [] : const ['IFPD'],
      token: 'mock-token-$key',
    );
  }

  @override
  Future<List<PartItem>> fetchParts({
    String? keyword,
    DateTime? updatedSince,
    List<String> areas = const [],
    int limit = 1000,
  }) async {
    await Future<void>.delayed(_latency);
    final key = keyword?.trim().toLowerCase() ?? '';
    if (key.isEmpty) return List<PartItem>.from(_parts);
    return _parts.where((p) => p.searchIndex.contains(key)).toList();
  }

  @override
  Future<Map<String, dynamic>> printTag({
    required String area,
    String? partNumber,
    String? jobNumber,
    int? itemId,
    int? eventId,
    String? nik,
  }) async =>
      // Mode simulasi memakai penomoran lokal, jadi endpoint ini tak terpakai.
      throw ApiNotAvailableException('print-tag mode simulasi');

  @override
  Future<SequenceReservation> reserveSequence({
    required int qty,
    required String area,
    required String nik,
  }) async {
    await Future<void>.delayed(_latency);

    final now = DateTime.now();
    final prefix = 'STO'
        '${now.year.toString().substring(2)}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';

    // Ganti hari atau aplikasi baru dijalankan -> lanjutkan dari nomor
    // tertinggi yang sudah ada supaya tidak menabrak tag lama.
    if (_sequencePrefix != prefix) {
      _sequencePrefix = prefix;
      _serverSequence = await lastUsedSequence?.call(prefix) ?? 0;
    }

    final start = _serverSequence + 1;
    _serverSequence += qty;
    return SequenceReservation(
      prefix: prefix,
      start: start,
      end: _serverSequence,
    );
  }

  @override
  Future<void> createBatch(PrintBatch batch, List<StoTag> tags) async =>
      Future<void>.delayed(_latency);

  @override
  Future<void> confirmPrint(StoTag tag) async {
    await Future<void>.delayed(_latency);
    _keadaanCetak[tag.tagNo] = PrintState.printed;
  }

  @override
  Future<void> reportPrintFailed(StoTag tag, String message) async {
    await Future<void>.delayed(_latency);
    _keadaanCetak[tag.tagNo] = PrintState.error;
    _pesanGagal[tag.tagNo] = message;
  }

  /// Keadaan cetak tiruan - di server ini kolom pada baris tag itu sendiri.
  final Map<String, PrintState> _keadaanCetak = {};
  final Map<String, String> _pesanGagal = {};

  /// Tag OK tiruan - di server ini satu tabel bersama.
  final Map<String, TagOk> _tagOk = {};

  TagOk _tagOkContoh(String id) => TagOk(
        idTagOk: id,
        area: 'IFPP',
        partNumber: 'P61163-BZ420-00',
        jobNumber: '61163-BZ420',
        qtyKbn: '36',
        status: 'STP',
      );

  /// Pesan tiruan - di server ini satu tabel bersama.
  final List<ChatMessage> _chat = [];

  @override
  Future<List<ChatThread>> fetchChatThreads(String nik) async {
    await Future<void>.delayed(_latency);
    return [
      const ChatThread(thread: ChatThread.broadcastKey, broadcast: true),
      ChatThread(thread: nik),
    ];
  }

  @override
  Future<List<ChatMessage>> fetchChatMessages({
    required String nik,
    required String thread,
    int afterId = 0,
    int limit = 50,
  }) async {
    await Future<void>.delayed(_latency);
    return _chat
        .where((m) => m.thread == thread && m.id > afterId)
        .take(limit)
        .toList();
  }

  @override
  Future<ChatMessage> sendChat({
    required String nik,
    required String thread,
    required String body,
  }) async {
    await Future<void>.delayed(_latency);
    final pesan = ChatMessage(
      id: _chat.length + 1,
      thread: thread,
      fromNik: nik,
      body: body,
      broadcast: thread == ChatThread.broadcastKey,
      createdAt: DateTime.now(),
    );
    _chat.add(pesan);
    return pesan;
  }

  @override
  Future<void> markChatRead({
    required String nik,
    required String thread,
    required int lastId,
  }) async {
    await Future<void>.delayed(_latency);
  }

  @override
  Future<void> muteChat({
    required String nik,
    required String nikUser,
    required int menit,
  }) async {
    await Future<void>.delayed(_latency);
  }

  @override
  Future<TagOk> fetchTagOk(String nik, String idTagOk) async {
    await Future<void>.delayed(_latency);
    return _tagOk[idTagOk] ?? _tagOkContoh(idTagOk);
  }

  @override
  Future<TagOk> openTagOk(String nik, String idTagOk) async {
    await Future<void>.delayed(_latency);
    final dasar = _tagOk[idTagOk] ?? _tagOkContoh(idTagOk);
    final baru = TagOk(
      idTagOk: dasar.idTagOk,
      area: dasar.area,
      partNumber: dasar.partNumber,
      jobNumber: dasar.jobNumber,
      qtyKbn: dasar.qtyKbn,
      status: dasar.status,
      terbuka: true,
      openedBy: nik,
      openedAt: DateTime.now(),
    );
    _tagOk[idTagOk] = baru;
    return baru;
  }

  @override
  Future<TagOk> scanTagOk(String nik, String idTagOk, int qty) async {
    await Future<void>.delayed(_latency);
    final dasar = _tagOk[idTagOk] ?? _tagOkContoh(idTagOk);
    final baru = TagOk(
      idTagOk: dasar.idTagOk,
      area: dasar.area,
      partNumber: dasar.partNumber,
      jobNumber: dasar.jobNumber,
      qtyKbn: dasar.qtyKbn,
      status: dasar.status,
      openedBy: dasar.openedBy,
      openedAt: dasar.openedAt,
      qtyScan: qty,
      scannedBy: nik,
      scannedAt: DateTime.now(),
    );
    _tagOk[idTagOk] = baru;
    return baru;
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
    await Future<void>.delayed(_latency);
    return _tagOk.values
        .where((t) => terbuka == null || t.terbuka == terbuka)
        .where((t) => batal == null || t.batal == batal)
        .take(limit)
        .toList();
  }

  @override
  Future<TagOk> cancelTagOk({
    required String nik,
    required String idTagOk,
    String alasan = '',
    String? keputusan,
  }) async {
    await Future<void>.delayed(_latency);
    final dasar = _tagOk[idTagOk] ?? _tagOkContoh(idTagOk);
    final nilai = (keputusan == null || keputusan.isEmpty)
        ? 2
        : (keputusan == 'setuju' ? 1 : 0);
    final baru = TagOk(
      idTagOk: dasar.idTagOk,
      area: dasar.area,
      partNumber: dasar.partNumber,
      jobNumber: dasar.jobNumber,
      qtyKbn: dasar.qtyKbn,
      status: dasar.status,
      terbuka: dasar.terbuka,
      openedBy: dasar.openedBy,
      openedAt: dasar.openedAt,
      qtyScan: dasar.qtyScan,
      scannedBy: dasar.scannedBy,
      scannedAt: dasar.scannedAt,
      batal: nilai,
      cancelReason: nilai == 0 ? '' : alasan,
      canceledBy: nilai == 0 ? '' : nik,
      canceledAt: nilai == 0 ? null : DateTime.now(),
    );
    _tagOk[idTagOk] = baru;
    return baru;
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
    await Future<void>.delayed(_latency);
    // Mode simulasi tidak punya riwayat bersama; layar memakai catatan lokal.
    return const [];
  }

  @override
  Future<List<PengajuanBatal>> fetchCancelRequests(
    String adminNik, {
    int limit = 100,
  }) async {
    await Future<void>.delayed(_latency);
    // Mode simulasi tidak punya antrean bersama; layar memakai catatan lokal.
    return const [];
  }

  /// Setelan tiruan - di server ini satu tabel bersama.
  final Map<String, String> _setelanPrinter = {};

  @override
  Future<Map<String, String>> fetchPrinterSetting(String nik) async {
    await Future<void>.delayed(_latency);
    return Map<String, String>.from(_setelanPrinter);
  }

  @override
  Future<Map<String, String>> savePrinterSetting(
    String adminNik,
    Map<String, Object> setelan,
  ) async {
    await Future<void>.delayed(_latency);
    setelan.forEach((k, v) => _setelanPrinter[k] = '$v');
    return Map<String, String>.from(_setelanPrinter);
  }

  @override
  Future<PrintHistory> fetchPrintHistory({
    required String nik,
    List<PrintState> statuses = const [],
    String? keyword,
    int limit = 100,
  }) async {
    await Future<void>.delayed(_latency);

    final entries = _keadaanCetak.entries
        .where((e) => statuses.isEmpty || statuses.contains(e.value))
        .take(limit)
        .map(
          (e) => PrintEntry(
            tagNo: e.key,
            area: '-',
            state: e.value,
            errorMessage: _pesanGagal[e.key] ?? '',
            createdBy: nik,
            createdAt: DateTime.now(),
          ),
        )
        .toList();

    return PrintHistory(
      entries: entries,
      summary: {
        'total': _keadaanCetak.length,
        'draft': _hitung(PrintState.draft),
        'printed': _hitung(PrintState.printed),
        'error': _hitung(PrintState.error),
        'dibatalkan': 0,
      },
    );
  }

  int _hitung(PrintState state) =>
      _keadaanCetak.values.where((e) => e == state).length;

  @override
  Future<void> cancelTag(StoTag tag, String reason) async =>
      Future<void>.delayed(_latency);

  @override
  Future<void> requestCancelTag(StoTag tag, String reason) async =>
      Future<void>.delayed(_latency);

  @override
  Future<void> rejectCancelTag(StoTag tag) async =>
      Future<void>.delayed(_latency);

  /// Tag milik perangkat lain: dijawab dengan data tiruan yang bentuknya sama
  /// dengan respons server, supaya alur scan & pembatalan lintas perangkat
  /// bisa diuji sebelum API terbit.
  @override
  Future<Map<String, dynamic>?> fetchTagDetail(String tagNo) async {
    await Future<void>.delayed(_latency);
    final nomor = tagNo.trim().toUpperCase();
    if (nomor.isEmpty || nomor == '0000') return null;

    // Part dipilih tetap berdasarkan nomor tag supaya hasilnya konsisten
    // setiap kali tag yang sama discan.
    final part = _parts[nomor.hashCode.abs() % _parts.length];
    return {
      'tag_no': nomor,
      'part_number': part.partNumber,
      'job_number': part.jobNumber,
      'part_name': part.partName,
      'area': part.area,
      'part_type': part.partType,
      'unit': part.unit,
      'created_by': 'PERANGKAT LAIN',
      'status': 'printed',
    };
  }

  @override
  Future<void> submitCount(Map<String, dynamic> payload) async =>
      Future<void>.delayed(_latency);

  static List<PartItem> _seedParts() {
    const rows = [
      // partNumber | jobNumber | partName | customer | model | area | lokasi | stdPack | FP/WIP
      // Area memakai kode yang sama dengan master server (IFRM, PRESS,
      // IFPP, WELD, IFPD) supaya penyaringan per izin area bisa dicoba
      // di mode simulasi persis seperti di lapangan.
      // --- ADM (Daihatsu) ---
      ['53801-BZ010', 'JOB-2601', 'PANEL SIDE OUTER RH', 'ADM', 'AYLA', 'IFPD', 'RAK A-01', 50, 'FP'],
      ['53802-BZ010', 'JOB-2602', 'PANEL SIDE OUTER LH', 'ADM', 'AYLA', 'IFPD', 'RAK A-02', 50, 'FP'],
      ['53801-BZ010-W', 'JOB-2601W', 'PANEL SIDE OUTER RH SUB ASSY WELDING', 'ADM', 'AYLA', 'WELD', 'STAGING W-01', 20, 'WIP'],
      ['57104-BZ150', 'JOB-2603', 'MEMBER FLOOR SIDE RH', 'ADM', 'SIGRA', 'IFPD', 'RAK A-05', 40, 'FP'],
      ['57105-BZ150', 'JOB-2604', 'MEMBER FLOOR SIDE LH', 'ADM', 'SIGRA', 'IFPD', 'RAK A-06', 40, 'FP'],
      ['57104-BZ150-P', 'JOB-2603P', 'MEMBER FLOOR SIDE RH HASIL PRESS BELUM WELDING', 'ADM', 'SIGRA', 'PRESS', 'PALLET P-12', 100, 'WIP'],
      ['61101-BZ400', 'JOB-2605', 'PANEL ROOF', 'ADM', 'CALYA', 'IFPP', 'RAK B-01', 20, 'FP'],
      ['53301-BZ180', 'JOB-2609', 'HOOD SUB ASSY', 'ADM', 'TERIOS', 'IFRM', 'RAK C-01', 15, 'FP'],
      ['53301-BZ180-W', 'JOB-2609W', 'HOOD INNER PANEL BELUM HEMMING', 'ADM', 'TERIOS', 'WELD', 'STAGING W-08', 12, 'WIP'],
      ['67001-BZ330', 'JOB-2610', 'DOOR PANEL FRONT RH', 'ADM', 'XENIA', 'IFRM', 'RAK C-02', 20, 'FP'],
      ['67002-BZ330', 'JOB-2611', 'DOOR PANEL FRONT LH', 'ADM', 'XENIA', 'IFRM', 'RAK C-03', 20, 'FP'],
      ['67003-BZ330', 'JOB-2612', 'DOOR PANEL REAR RH', 'ADM', 'XENIA', 'IFRM', 'RAK C-04', 20, 'FP'],
      ['67004-BZ330', 'JOB-2613', 'DOOR PANEL REAR LH', 'ADM', 'XENIA', 'IFRM', 'RAK C-05', 20, 'FP'],
      ['48601-BZ010', 'JOB-2620', 'BRACKET SUSPENSION UPPER', 'ADM', 'GRANMAX', 'IFPP', 'RAK B-14', 100, 'FP'],
      ['48602-BZ010', 'JOB-2621', 'BRACKET SUSPENSION LOWER', 'ADM', 'GRANMAX', 'IFPP', 'RAK B-15', 100, 'FP'],
      ['57601-BZ330', 'JOB-2622', 'MEMBER ROOF CENTER', 'ADM', 'ROCKY', 'IFRM', 'RAK C-11', 40, 'FP'],
      ['57602-BZ330', 'JOB-2623', 'MEMBER ROOF FRONT', 'ADM', 'ROCKY', 'IFRM', 'RAK C-12', 40, 'FP'],
      ['57602-BZ330-P', 'JOB-2623P', 'MEMBER ROOF FRONT BLANK PRESS', 'ADM', 'ROCKY', 'PRESS', 'PALLET P-03', 200, 'WIP'],
      // --- TMMIN (Toyota) ---
      ['58111-BZ090', 'JOB-2606', 'PAN FLOOR FRONT', 'TMMIN', 'AVANZA', 'IFPP', 'RAK B-04', 25, 'FP'],
      ['58112-BZ090', 'JOB-2607', 'PAN FLOOR REAR', 'TMMIN', 'AVANZA', 'IFPP', 'RAK B-05', 25, 'FP'],
      ['58111-BZ090-W', 'JOB-2606W', 'PAN FLOOR FRONT SUB ASSY', 'TMMIN', 'AVANZA', 'WELD', 'STAGING W-04', 10, 'WIP'],
      ['55101-BZ220', 'JOB-2608', 'REINF INSTRUMENT PANEL', 'TMMIN', 'RUSH', 'IFPP', 'RAK B-09', 60, 'FP'],
      ['58301-BZ110', 'JOB-2624', 'PANEL WHEEL HOUSE RH', 'TMMIN', 'CALYA', 'IFPD', 'RAK A-21', 30, 'FP'],
      ['58302-BZ110', 'JOB-2625', 'PANEL WHEEL HOUSE LH', 'TMMIN', 'CALYA', 'IFPD', 'RAK A-22', 30, 'FP'],
      ['58302-BZ110-P', 'JOB-2625P', 'PANEL WHEEL HOUSE LH BLANK', 'TMMIN', 'CALYA', 'PRESS', 'PALLET P-21', 150, 'WIP'],
      // --- HMSI / HPM (Honda) ---
      ['64101-BZ260', 'JOB-2614', 'PANEL BACK', 'HMSI', 'BRIO', 'IFPD', 'RAK A-11', 30, 'FP'],
      ['65101-BZ100', 'JOB-2615', 'DECK FLOOR', 'HMSI', 'BRIO', 'IFPD', 'RAK A-12', 30, 'FP'],
      ['65101-BZ100-W', 'JOB-2615W', 'DECK FLOOR SUB ASSY WELDING PROSES 2', 'HMSI', 'BRIO', 'WELD', 'STAGING W-15', 15, 'WIP'],
      ['66100-BZ870', 'JOB-2626', 'PANEL FLOOR REAR', 'HPM', 'BR-V', 'IFRM', 'RAK D-11', 24, 'FP'],
      // --- MMKI (Mitsubishi) ---
      ['51201-BZ050', 'JOB-2616', 'CROSSMEMBER SUSPENSION', 'MMKI', 'XPANDER', 'IFRM', 'RAK D-01', 35, 'FP'],
      ['51202-BZ050', 'JOB-2617', 'BRACKET ENGINE MOUNT', 'MMKI', 'XPANDER', 'IFRM', 'RAK D-02', 80, 'FP'],
      ['51201-BZ050-W', 'JOB-2616W', 'CROSSMEMBER SUSPENSION BELUM PAINTING', 'MMKI', 'XPANDER', 'PRESS', 'STAGING PT-02', 30, 'WIP'],
      // --- SIM (Suzuki) ---
      ['52101-BZ700', 'JOB-2618', 'REINF BUMPER FRONT', 'SIM', 'ERTIGA', 'IFRM', 'RAK D-06', 45, 'FP'],
      ['52102-BZ700', 'JOB-2619', 'REINF BUMPER REAR', 'SIM', 'ERTIGA', 'IFRM', 'RAK D-07', 45, 'FP'],
      ['52103-BZ700', 'JOB-2627', 'REINF BUMPER SIDE STAY LH', 'SIM', 'CARRY', 'IFRM', 'RAK D-08', 60, 'FP'],
      // --- kasus uji khusus ---
      ['99001-TEST-PANJANG', 'JOB-2699', 'PANEL BODY SIDE OUTER COMPLETE ASSY DENGAN NAMA SANGAT PANJANG UNTUK UJI POTONG BARIS', 'ADM', 'AYLA', 'IFPD', 'RAK A-99', 5, 'WIP'],
      ['99002-TEST-KOSONG', 'JOB-2698', 'PART TANPA LOKASI DAN STD PACK', 'TMMIN', '-', 'IFPP', '-', 0, 'FP'],
      ['99003-TEST-QTY', 'JOB-2697', 'PART STD PACK BESAR (UJI CHIP JUMLAH)', 'HMSI', 'BRIO', 'IFRM', 'RAK C-99', 100, 'FP'],
    ];

    return rows
        .map(
          (r) => PartItem(
            partNumber: r[0] as String,
            jobNumber: r[1] as String,
            partName: r[2] as String,
            customer: r[3] as String,
            model: r[4] as String,
            unit: 'PCS',
            area: r[5] as String,
            location: r[6] as String,
            stdPack: r[7] as int,
            partType: r[8] as String,
            updatedAt: DateTime.now(),
          ),
        )
        .toList();
  }

  // ------------------------------------------------------ pengelolaan user
  // Mode simulasi memakai tabel `users` lokal sebagai master, jadi ketiga
  // operasi ini cukup mengembalikan bentuk yang sama tanpa menyimpan apa pun.
  @override
  Future<AppUser> registerUser(
    AppUser user, {
    required String createdBy,
    int? deviceId,
  }) async =>
      user;

  @override
  Future<List<AppUser>> fetchUsers(
    String adminNik, {
    int? deviceId,
    String? keyword,
    int limit = 200,
  }) async =>
      const [];

  @override
  Future<Map<String, dynamic>> updateUser({
    required String adminNik,
    required String targetNik,
    String? role,
    String? team,
    int? deviceId,
    List<String>? areas,
    List<String>? permissions,
  }) async =>
      {'status': 'success', 'nik': targetNik};

  @override
  Future<Map<String, dynamic>> deleteUser({
    required String adminNik,
    required String targetNik,
    bool force = false,
  }) async =>
      {'status': 'success', 'nik': targetNik};

  // --------------------------------------------------- perangkat & event
  // Cermin sederhana dari tabel `devices` dan `events` di server, supaya
  // halaman admin bisa dicoba tanpa jaringan.
  final List<Map<String, dynamic>> _devices = [];
  final List<Map<String, dynamic>> _events = [
    {
      'id_event': 1,
      'event_name': 'STO SIMULASI BULAN INI',
      'start_date': '2026-09-01',
      'end_date': '2026-09-30',
      'status': 1,
      'total_tag': 0,
    },
  ];
  int _deviceSeq = 0;
  int _eventSeq = 1;

  @override
  Future<List<Map<String, dynamic>>> fetchDevices(String adminNik) async =>
      List<Map<String, dynamic>>.from(_devices);

  @override
  Future<Map<String, dynamic>?> fetchDeviceDetail(
    String adminNik, {
    int? deviceId,
    String? androidId,
  }) async {
    for (final d in _devices) {
      if (deviceId != null && d['id'] == deviceId) return d;
      if (androidId != null && d['android_id'] == androidId) return d;
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> createDevice({
    required String adminNik,
    required String name,
    required String androidId,
  }) async {
    final bentrok = _devices.any((d) => d['android_id'] == androidId);
    if (bentrok) {
      throw ApiException('android_id "$androidId" sudah terdaftar');
    }
    final baru = {
      'id': ++_deviceSeq,
      'name': name,
      'android_id': androidId,
      'total_user': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': '',
    };
    _devices.add(baru);
    return baru;
  }

  @override
  Future<Map<String, dynamic>> updateDevice({
    required String adminNik,
    required int deviceId,
    String? name,
    String? androidId,
  }) async {
    final device = _devices.firstWhere(
      (d) => d['id'] == deviceId,
      orElse: () => throw ApiException('device dengan id $deviceId tidak ditemukan'),
    );
    if (name != null) device['name'] = name;
    if (androidId != null) device['android_id'] = androidId;
    device['updated_at'] = DateTime.now().toIso8601String();
    return device;
  }

  @override
  Future<Map<String, dynamic>> deleteDevice({
    required String adminNik,
    required int deviceId,
    bool force = false,
  }) async {
    _devices.removeWhere((d) => d['id'] == deviceId);
    return {'status': 'success', 'id': deviceId};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEvents(String adminNik) async =>
      List<Map<String, dynamic>>.from(_events);

  @override
  Future<Map<String, dynamic>> createEvent({
    required String adminNik,
    required String name,
    required DateTime start,
    required DateTime end,
    bool berjalan = true,
  }) async {
    // Mode simulasi ikut menjaga aturan satu event berjalan.
    if (berjalan) {
      for (final e in _events) {
        e['status'] = 0;
      }
    }
    final baru = {
      'id_event': ++_eventSeq,
      'event_name': name,
      'start_date': _tanggal(start),
      'end_date': _tanggal(end),
      'status': berjalan ? 1 : 0,
      'total_tag': 0,
    };
    _events.add(baru);
    return baru;
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
    if (berjalan == true) {
      for (final e in _events) {
        if (e['id_event'] != eventId) e['status'] = 0;
      }
    }
    final event = _events.firstWhere(
      (e) => e['id_event'] == eventId,
      orElse: () => throw ApiException('event $eventId tidak ditemukan'),
    );
    if (name != null) event['event_name'] = name;
    if (start != null) event['start_date'] = _tanggal(start);
    if (end != null) event['end_date'] = _tanggal(end);
    if (berjalan != null) event['status'] = berjalan ? 1 : 0;
    return event;
  }

  @override
  Future<Map<String, dynamic>> deleteEvent({
    required String adminNik,
    required int eventId,
    bool force = false,
  }) async {
    _events.removeWhere((e) => e['id_event'] == eventId);
    return {'status': 'success', 'id_event': eventId};
  }

  String _tanggal(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-'
      '${v.month.toString().padLeft(2, '0')}-'
      '${v.day.toString().padLeft(2, '0')}';
}
