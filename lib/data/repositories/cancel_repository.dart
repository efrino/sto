import '../local/tag_dao.dart';
import '../models/app_user.dart';
import '../models/print_batch.dart';
import '../models/pengajuan_batal.dart';
import '../models/print_entry.dart';
import '../models/sto_tag.dart';
import '../remote/api_client.dart';
import '../remote/api_gateway.dart';
import 'count_repository.dart';
import 'tag_repository.dart';

/// Pembatalan tag - termasuk tag yang dicetak perangkat/orang lain.
///
/// Server adalah sumber kebenarannya: antrean pengajuan dibaca dari sana, dan
/// setiap keputusan (ajukan / setujui / tolak) dikirim ke sana lebih dulu.
/// Database perangkat hanya cache supaya layar riwayat tetap terisi - tidak
/// pernah dipakai sebagai penjaga keputusan.
///
/// Satu-satunya yang masih boleh menumpuk di perangkat adalah PENGAJUAN saat
/// jaringan mati: pengajuan terjadi di lapangan, dan kehilangannya berarti tag
/// hantu ikut terhitung waktu STO. Keputusan admin sebaliknya tidak pernah
/// diantre - lebih baik gagal terang-terangan daripada terlihat berhasil
/// padahal server belum tahu.
class CancelRepository {
  CancelRepository({
    required this.tagDao,
    required this.tagRepository,
    required this.countRepository,
    required this.api,
  });

  final TagDao tagDao;
  final TagRepository tagRepository;
  final CountRepository countRepository;
  final ApiGateway api;

  /// Diisi bila antrean terpaksa dibaca dari catatan perangkat ini.
  String? peringatanAntrean;

  static const String externalBatchId = 'EXTERNAL';

  /// Mencari tag untuk dibatalkan. Bila tidak ada di perangkat ini, detailnya
  /// diambil dari server dan dicatat lokal dengan status SUDAH CETAK.
  Future<StoTag?> resolve(String tagNo) async {
    final lokal = await tagDao.findByTagNo(tagNo);
    if (lokal != null) return lokal;

    final detail = await countRepository.lookup(tagNo);
    if (detail == null) return null;
    return _simpanTagLuar(detail);
  }

  Future<StoTag> _simpanTagLuar(ScannedTag detail) async {
    final now = DateTime.now();
    final tag = StoTag(
      tagNo: detail.tagNo,
      sequence: 0,
      batchId: externalBatchId,
      partNumber: detail.partNumber,
      jobNumber: detail.jobNumber,
      partName: detail.partName,
      area: detail.area,
      partType: detail.partType,
      unit: detail.unit,
      status: TagStatus.printed,
      createdBy: detail.printedBy,
      createdAt: now,
      printedAt: now,
      note: 'Tag dicetak perangkat lain',
    );

    final batch = PrintBatch(
      batchId: externalBatchId,
      partNumber: detail.partNumber,
      jobNumber: detail.jobNumber,
      partName: detail.partName,
      area: detail.area,
      qty: 1,
      createdBy: detail.printedBy,
      createdAt: now,
      note: 'Tag dari perangkat lain',
    );

    final saved = await tagDao.insertBatch(batch, [tag]);
    return saved.first;
  }

  /// Operator mengajukan pembatalan.
  ///
  /// Dikirim langsung ke server. Bila jaringan mati, pengajuannya diantre di
  /// perangkat - pengajuan terjadi di lapangan, dan kehilangan pengajuan
  /// berarti tag hantu ikut terhitung saat STO.
  Future<StoTag> requestCancel(StoTag tag, String reason, AppUser user) async {
    final diajukan = tag.copyWith(
      status: TagStatus.pendingCancel,
      cancelReason: reason,
      cancelRequestedBy: user.nik,
      cancelRequestedAt: DateTime.now(),
    );

    try {
      await api.requestCancelTag(diajukan, reason);
      await _segarkanCache(diajukan);
      return diajukan;
    } on ApiException {
      // Jaringan/server bermasalah: simpan lewat jalur antrean supaya
      // pengajuannya tidak hilang, lalu terkirim saat jaringan kembali.
      return tagRepository.requestCancel(tag.tagNo, reason, user);
    }
  }

  /// Admin menyetujui pengajuan - tag benar-benar dibatalkan.
  ///
  /// TIDAK diantre: keputusan yang "berhasil" di layar tetapi belum sampai ke
  /// server justru yang membuat tag terlihat batal padahal masih sah. Bila
  /// server tak terjangkau, kegagalannya dilempar apa adanya supaya admin
  /// tahu keputusannya belum berlaku.
  Future<StoTag> approveCancel(
    StoTag tag,
    AppUser admin, {
    String? reason,
  }) async {
    TagRepository.pastikanAdmin(admin, 'menyetujui pengajuan pembatalan');

    final disetujui = tag.copyWith(
      status: TagStatus.cancelled,
      cancelledAt: DateTime.now(),
      cancelApprovedBy: admin.nik,
      cancelReason: reason ?? tag.cancelReason,
    );

    await api.cancelTag(disetujui, reason ?? tag.cancelReason ?? '-');
    await _segarkanCache(disetujui);
    return disetujui;
  }

  /// Admin menolak pengajuan - tag kembali sah.
  Future<StoTag> rejectCancel(StoTag tag, AppUser admin) async {
    TagRepository.pastikanAdmin(admin, 'menolak pengajuan pembatalan');

    final ditolak = tag.copyWith(
      status: TagStatus.printed,
      cancelApprovedBy: admin.nik,
    );

    await api.rejectCancelTag(ditolak);
    await _segarkanCache(ditolak);
    return ditolak;
  }

  /// Menyalin keadaan terakhir ke database perangkat, sebagai cache saja.
  ///
  /// Keputusannya sudah diterima server sebelum ini dipanggil, jadi kegagalan
  /// di sini tidak boleh membatalkan apa pun - paling banter layar riwayat
  /// menampilkan keadaan lama sampai penyegaran berikutnya.
  Future<void> _segarkanCache(StoTag tag) async {
    try {
      if (await tagDao.findByTagNo(tag.tagNo) != null) {
        await tagDao.timpaDariServer(tag);
        return;
      }

      await tagDao.insertBatch(
        PrintBatch(
          batchId: tag.batchId,
          partNumber: tag.partNumber,
          jobNumber: tag.jobNumber,
          partName: tag.partName,
          area: tag.area,
          qty: 1,
          createdBy: tag.createdBy,
          createdAt: tag.createdAt,
          note: 'Salinan dari server',
        ),
        [tag],
      );
    } catch (_) {
      // Cache gagal disegarkan - tidak berpengaruh pada keputusan.
    }
  }

  /// Antrean pengajuan yang menunggu keputusan admin.
  ///
  /// Sumbernya server: pengajuan datang dari handheld mana pun, jadi catatan
  /// perangkat yang sedang dipakai hanya memuat pengajuan yang dibuat dari
  /// situ - itulah sebabnya kotak masuk admin sempat terlihat kosong padahal
  /// di server ada belasan.
  Future<List<PengajuanBatal>> pendingRequests({AppUser? admin}) async {
    peringatanAntrean = null;

    if (admin == null || !admin.isAdmin) {
      // Bukan admin: hanya pengajuan yang dibuat dari perangkat ini, tanpa
      // keterangan cetak/hitung yang memang hanya dilihat pemutus.
      final lokal = await tagRepository.pendingCancelRequests();
      return [
        for (final tag in lokal)
          PengajuanBatal(tag: tag, keadaanCetak: PrintState.printed),
      ];
    }

    try {
      return await api.fetchCancelRequests(admin.nik);
    } on ApiException catch (e) {
      peringatanAntrean = 'Antrean tidak bisa dibaca - server: $e';
      return const [];
    }
  }

}
