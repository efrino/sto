import '../local/count_dao.dart';
import '../local/outbox_dao.dart';
import '../local/tag_dao.dart';
import '../models/app_user.dart';
import '../models/part_item.dart';
import '../models/sto_count.dart';
import '../models/sto_tag.dart';
import '../remote/api_client.dart';
import '../remote/api_gateway.dart';

/// Detail tag yang dipakai halaman scan: dari database lokal bila tagnya
/// dicetak di perangkat ini, atau dari server bila dicetak perangkat lain.
class ScannedTag {
  const ScannedTag({
    required this.tagNo,
    required this.partNumber,
    required this.jobNumber,
    required this.partName,
    required this.area,
    this.partType = 'FP',
    this.unit = 'PCS',
    this.printedBy = '-',
    this.status,
    this.fromServer = false,
  });

  final String tagNo;
  final String partNumber;
  final String jobNumber;
  final String partName;
  final String area;
  final String partType;
  final String unit;
  final String printedBy;

  /// Status tag bila diketahui (null untuk tag milik perangkat lain).
  final TagStatus? status;

  /// true bila detailnya diambil dari server, bukan dari database perangkat.
  final bool fromServer;

  /// Tag hanya boleh dihitung bila benar-benar tercetak dan tidak sedang
  /// diajukan batal / sudah dibatalkan. Status null (tag dari perangkat lain
  /// yang detailnya dari server) dianggap boleh - server yang menentukan.
  bool get bolehDihitung =>
      status == null || status == TagStatus.printed;

  /// Alasan penolakan untuk ditampilkan ke operator.
  String get alasanTidakBolehDihitung {
    switch (status) {
      case TagStatus.cancelled:
        return 'Tag ini sudah DIBATALKAN, jadi tidak boleh ikut dihitung.';
      case TagStatus.pendingCancel:
        return 'Pembatalan tag ini sedang menunggu keputusan admin, '
            'jadi belum boleh dihitung.';
      case TagStatus.draft:
        return 'Tag ini tercatat belum keluar dari printer.';
      case TagStatus.printed:
      case null:
        return '';
    }
  }

  factory ScannedTag.fromTag(StoTag tag) => ScannedTag(
        tagNo: tag.tagNo,
        partNumber: tag.partNumber,
        jobNumber: tag.jobNumber,
        partName: tag.partName,
        area: tag.area,
        partType: tag.partType,
        unit: tag.unit,
        printedBy: tag.createdBy,
        status: tag.status,
      );

  factory ScannedTag.fromJson(String tagNo, Map<String, dynamic> json) {
    TagStatus? status;
    final isCanceled = '${json['is_canceled'] ?? 0}' == '1';
    final isPendingCancel = !isCanceled &&
        (json['cancel_requested_at'] != null &&
            '${json['cancel_requested_at']}'.trim().isNotEmpty);
    final printStatus = '${json['print_status'] ?? ''}'.trim().toLowerCase();

    if (isCanceled) {
      status = TagStatus.cancelled;
    } else if (isPendingCancel) {
      status = TagStatus.pendingCancel;
    } else if (printStatus == 'draft' || printStatus == 'error') {
      status = TagStatus.draft;
    } else if (printStatus == 'printed') {
      status = TagStatus.printed;
    }

    return ScannedTag(
      tagNo: (json['tag_no'] ?? json['id_tag'] ?? tagNo).toString(),
      partNumber: (json['part_number'] ?? json['partno'] ?? '-').toString(),
      jobNumber: (json['job_number'] ?? json['job_no'] ?? '-').toString(),
      partName: (json['part_name'] ??
              json['material_description'] ??
              json['part_description'] ??
              '-')
          .toString(),
      area: (json['area'] ?? '-').toString(),
      partType: PartItem.normalizeType(
        (json['part_type'] ?? json['type'] ?? 'FP').toString(),
      ),
      unit: (json['unit'] ?? json['uom'] ?? 'PCS').toString(),
      printedBy: (json['created_by'] ?? json['printed_by'] ?? '-').toString(),
      status: status,
      fromServer: true,
    );
  }
}

/// Alur hitung STO: scan tag -> ambil detail part -> operator mengisi qty ->
/// simpan lokal + antre POST { nik, tag_no, tim, qty }.
class CountRepository {
  CountRepository({
    required this.countDao,
    required this.tagDao,
    required this.outboxDao,
    required this.api,
  });

  final CountDao countDao;
  final TagDao tagDao;
  final OutboxDao outboxDao;
  final ApiGateway api;

  /// Detail tag untuk halaman scan. Tag yang dicetak perangkat lain diambil
  /// dari server (print-history atau scan-history).
  Future<ScannedTag?> lookup(String tagNo, {String? nik}) async {
    final lokal = await tagDao.findByTagNo(tagNo);
    if (lokal != null) return ScannedTag.fromTag(lokal);

    try {
      final json = await api.fetchTagDetail(tagNo, nik: nik);
      if (json == null) return null;
      return ScannedTag.fromJson(tagNo, json);
    } catch (_) {
      return null;
    }
  }

  /// Catatan hitung milik tim user (bila sudah ada) beserta catatan tim lain.
  Future<List<StoCount>> countsForTag(String tagNo) => countDao.byTag(tagNo);

  Future<StoCount?> myTeamCount(String tagNo, AppUser user) =>
      countDao.findByTagAndTeam(tagNo, user.team);

  /// Menyimpan hasil hitung.
  ///
  /// Aturan:
  /// - tim lain boleh menghitung tag yang sama (baris terpisah);
  /// - dalam satu tim hanya pencatat pertama yang boleh mengoreksi angkanya.
  Future<StoCount> submit({
    required ScannedTag tag,
    required AppUser user,
    required int qty,
  }) async {
    if (!user.hasTeam) {
      throw CountRuleException(
        'Tim untuk NIK ${user.nik} belum diatur admin. Minta admin '
        'mengisinya lewat menu Setting > User.',
      );
    }
    if (qty < 0) {
      throw CountRuleException('Qty tidak boleh negatif.');
    }
    if (!tag.bolehDihitung) {
      throw CountRuleException(tag.alasanTidakBolehDihitung);
    }

    final now = DateTime.now();
    final existing = await countDao.findByTagAndTeam(tag.tagNo, user.team);

    if (existing != null && existing.nik != user.nik) {
      throw CountRuleException(
        'Tag ${tag.tagNo} sudah dihitung ${existing.nik} dari ${existing.team}. '
        'Koreksi hanya boleh oleh pencatatnya.',
      );
    }

    final record = existing == null
        ? StoCount(
            tagNo: tag.tagNo,
            nik: user.nik,
            team: user.team,
            qty: qty,
            partNumber: tag.partNumber,
            jobNumber: tag.jobNumber,
            partName: tag.partName,
            area: tag.area,
            unit: tag.unit,
            countedAt: now,
          )
        : existing.copyWith(
            qty: qty,
            updatedAt: now,
            syncStatus: SyncStatus.pending,
          );

    final saved = await countDao.save(record);
    await outboxDao.enqueue(
      OutboxType.countSubmitted,
      saved.tagNo,
      saved.toApiJson(),
    );
    return saved;
  }

  /// Diisi bila riwayat terpaksa dibaca dari catatan perangkat ini.
  String? peringatanRiwayat;

  /// Riwayat scan dari server.
  ///
  /// Hasil hitung tim A dan tim B bisa datang dari handheld berbeda, jadi
  /// catatan satu perangkat tidak pernah utuh - server yang menyimpan
  /// semuanya. Catatan lokal tinggal cadangan saat jaringan mati.
  Future<List<StoCount>> history({
    int limit = 200,
    String? keyword,
    AppUser? user,
  }) async {
    peringatanRiwayat = null;

    try {
      // Operator hanya melihat hasil hitungnya sendiri - ia hanya bertanggung
      // jawab atas angkanya, dan daftar bercampur menyulitkan saat mencari
      // catatan yang mau dikoreksi. Admin melihat semuanya, karena dialah yang
      // memeriksa jalannya STO.
      return await api.fetchScanHistory(
        nik: (user?.isAdmin ?? false) ? null : user?.nik,
        keyword: keyword,
        limit: limit,
      );
    } on ApiException catch (e) {
      peringatanRiwayat =
          'Riwayat dibaca dari perangkat ini - server: $e';
      return countDao.recent(limit: limit, keyword: keyword);
    }
  }

  /// Ringkasan hari ini, dihitung dari riwayat server.
  ///
  /// Angkanya harus sama di semua handheld; menghitungnya dari catatan lokal
  /// membuat tiap perangkat melaporkan angka yang berbeda.
  Future<Map<String, int>> todaySummary({AppUser? user}) async {
    try {
      final semua = await api.fetchScanHistory(
        nik: (user?.isAdmin ?? false) ? null : user?.nik,
        limit: 500,
      );
      final kini = DateTime.now();
      final hariIni = semua.where(
        (c) =>
            c.countedAt.year == kini.year &&
            c.countedAt.month == kini.month &&
            c.countedAt.day == kini.day,
      );

      return {
        'scan': hariIni.length,
        'qty': hariIni.fold<int>(0, (jumlah, c) => jumlah + c.qty),
      };
    } on ApiException {
      return countDao.todaySummary();
    }
  }
}
