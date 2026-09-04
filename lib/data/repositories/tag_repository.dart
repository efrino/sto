import '../../core/config/app_config.dart';
import '../local/outbox_dao.dart';
import '../local/tag_dao.dart';
import '../models/app_user.dart';
import '../models/part_item.dart';
import '../models/print_batch.dart';
import '../models/sto_tag.dart';
import '../remote/api_gateway.dart';

/// Hasil pembuatan satu batch tag.
class GeneratedBatch {
  const GeneratedBatch({
    required this.batch,
    required this.tags,
    required this.fromServerSequence,
  });

  final PrintBatch batch;
  final List<StoTag> tags;

  /// false = nomor urut diambil offline, perlu rekonsiliasi saat sinkron.
  final bool fromServerSequence;
}

/// Sumber kebenaran tag STO di perangkat.
///
/// Semua perubahan status ditulis ke sqflite lebih dulu, baru diantrekan ke
/// outbox untuk dikirim ke server. Dengan begitu bukti "sudah dicetak" tidak
/// pernah hilang walau aplikasi ditutup atau jaringan mati.
class TagRepository {
  TagRepository({
    required this.tagDao,
    required this.outboxDao,
    required this.api,
  });

  final TagDao tagDao;
  final OutboxDao outboxDao;
  final ApiGateway api;

  /// Membuat N tag unik untuk satu part/job.
  /// Catatan: qty = jumlah TAG (nomor berbeda), bukan jumlah copy.
  /// Membuat tag lewat `print-tag`, satu panggilan per lembar.
  ///
  /// Gagal di tengah tidak dibatalkan: tag yang sudah terbuat memang sudah ada
  /// di server, jadi yang tersimpan di perangkat pun apa adanya - lebih baik
  /// operator mencetak sisanya daripada nomor server menggantung tanpa
  /// pasangan lokal.
  Future<GeneratedBatch> _generateLewatServer({
    required PartItem part,
    required int qty,
    required AppUser user,
    required String area,
    String? note,
    int qtyPerTag = 0,
  }) async {
    final now = DateTime.now();
    final nikSlug = user.nik.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final batchId =
        '$nikSlug-${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    final batch = PrintBatch(
      batchId: batchId,
      partNumber: part.partNumber,
      jobNumber: part.jobNumber,
      partName: part.partName,
      area: area,
      qty: qty,
      createdBy: user.nik,
      createdAt: now,
      note: note,
    );

    final tags = <StoTag>[];
    for (var i = 0; i < qty; i++) {
      final hasil = await api.printTag(
        area: area,
        // Keduanya dikirim supaya pencariannya sempit: area + part number
        // saja masih menyisakan kombinasi ganda di master.
        partNumber: part.partNumber,
        jobNumber: part.jobNumber,
        nik: user.nik,
      );

      final idTag = '${hasil['id_tag'] ?? ''}'.trim();
      if (idTag.isEmpty) {
        throw TagStateException(
          'Server tidak mengirim nomor tag pada lembar ke-${i + 1}.',
        );
      }

      tags.add(
        StoTag.fromPart(
          part: part,
          tagNo: idTag,
          sequence: i + 1,
          batchId: batchId,
          createdBy: user.nik,
          createdAt: now,
          areaOverride: area,
          note: note,
          eventId: '${hasil['id_event'] ?? ''}',
          qty: qtyPerTag,
        ),
      );
    }

    final saved = await tagDao.insertBatch(batch, tags);

    return GeneratedBatch(batch: batch, tags: saved, fromServerSequence: true);
  }

  Future<GeneratedBatch> generate({
    required PartItem part,
    required int qty,
    required AppUser user,
    required String eventId,
    String? areaOverride,
    String? note,
    int qtyPerTag = 0,
  }) async {
    final area = (areaOverride?.isNotEmpty ?? false) ? areaOverride! : part.area;

    if (qty > AppConfig.maxTagPerBatch) {
      throw TagStateException(
        'Maksimal ${AppConfig.maxTagPerBatch} tag sekali cetak.',
      );
    }

    // Nomor tag dibuat SERVER lewat print-tag; aplikasi memakai `id_tag` dari
    // balasannya apa adanya. Penomoran lokal sudah dibuang - nomor yang dibuat
    // sendiri akan berbeda dari barisnya di `sto_data`.
    return _generateLewatServer(
      part: part,
      qty: qty,
      user: user,
      area: area,
      note: note,
      qtyPerTag: qtyPerTag,
    );
  }


  /// Dipanggil SETELAH printer selesai mencetak. Melempar
  /// [TagStateException] bila tag sudah pernah dicetak/dibatalkan.
  Future<StoTag> markPrinted(StoTag tag) async {
    final updated = await tagDao.markPrinted(tag);
    await outboxDao.enqueue(
      OutboxType.tagPrinted,
      updated.tagNo,
      updated.toApiJson(),
    );
    return updated;
  }

  /// Dipanggil saat percobaan cetak GAGAL.
  ///
  /// Status lokalnya sengaja dibiarkan BELUM CETAK - yang berubah hanya
  /// catatan di server, supaya tag ini muncul di riwayat sebagai gagal
  /// beserta alasannya. Begitu printer normal, tag yang sama dicetak ulang;
  /// kalau tetap tertinggal, admin yang membatalkannya.
  Future<void> markPrintFailed(StoTag tag, String message) async {
    await outboxDao.enqueue(OutboxType.printFailed, tag.tagNo, {
      ...tag.toApiJson(),
      'message': message,
    });
  }

  /// Operator mengajukan pembatalan tag yang sudah tercetak.
  Future<StoTag> requestCancel(
    String tagNo,
    String reason,
    AppUser requester,
  ) async {
    final updated = await tagDao.requestCancel(tagNo, reason, requester.nik);
    await outboxDao.enqueue(OutboxType.cancelRequested, updated.tagNo, {
      ...updated.toApiJson(),
      'reason': reason,
      'requested_by': requester.nik,
    });
    return updated;
  }

  /// Menolak siapa pun yang bukan admin.
  ///
  /// Layar sudah menyembunyikan tombolnya dan provider sudah memeriksa, tapi
  /// keputusan pembatalan terlalu mahal untuk hanya dijaga di lapisan tampilan:
  /// aturannya ditegakkan di sini supaya berlaku untuk semua pemanggil.
  static void pastikanAdmin(AppUser user, String tindakan) {
    if (user.isAdmin) return;
    throw TagStateException(
      'Hanya admin yang boleh $tindakan. NIK ${user.nik} berperan '
      '${user.role.label}.',
    );
  }

  /// Admin menyetujui pembatalan (atau membatalkan langsung tag tercetak).
  Future<StoTag> approveCancel(
    String tagNo,
    AppUser admin, {
    String? reason,
  }) async {
    pastikanAdmin(admin, 'menyetujui pengajuan pembatalan');
    final updated = await tagDao.approveCancel(
      tagNo,
      admin.nik,
      reason: reason,
    );
    await outboxDao.enqueue(OutboxType.tagCancelled, updated.tagNo, {
      ...updated.toApiJson(),
      'reason': updated.cancelReason ?? reason ?? '-',
      'approved_by': admin.nik,
    });
    return updated;
  }

  /// Admin menolak pengajuan - tag kembali berstatus SUDAH CETAK.
  Future<StoTag> rejectCancel(String tagNo, AppUser admin) async {
    pastikanAdmin(admin, 'menolak pengajuan pembatalan');
    final updated = await tagDao.rejectCancel(tagNo, admin.nik);
    await outboxDao.enqueue(OutboxType.cancelRejected, updated.tagNo, {
      ...updated.toApiJson(),
      'rejected_by': admin.nik,
    });
    return updated;
  }

  Future<int> cancelBatch(
    String batchId,
    String reason,
    AppUser admin,
  ) async {
    pastikanAdmin(admin, 'membatalkan satu batch sekaligus');
    final affected = await tagDao.cancelBatch(batchId, reason, admin.nik);
    final tags = await tagDao.byBatch(batchId);
    for (final tag in tags.where((t) => t.status == TagStatus.cancelled)) {
      await outboxDao.enqueue(OutboxType.tagCancelled, tag.tagNo, {
        ...tag.toApiJson(),
        'reason': reason,
        'approved_by': admin.nik,
      });
    }
    return affected;
  }

  Future<List<StoTag>> pendingCancelRequests({int limit = 100}) =>
      tagDao.pendingCancelRequests(limit: limit);

  Future<List<StoTag>> byBatch(String batchId) => tagDao.byBatch(batchId);

  Future<List<StoTag>> history({
    int limit = 100,
    TagStatus? status,
    String? keyword,
  }) =>
      tagDao.recent(limit: limit, status: status, keyword: keyword);

  Future<List<PrintBatch>> recentBatches({int limit = 30}) =>
      tagDao.recentBatches(limit: limit);

  Future<Map<String, int>> todaySummary() => tagDao.todaySummary();

  /// Cetak & pembatalan hari ini - untuk kartu ringkasan.
  Future<Map<String, int>> todayActivity() => tagDao.todayActivity();

  Future<StoTag?> findByTagNo(String tagNo) => tagDao.findByTagNo(tagNo);
}
