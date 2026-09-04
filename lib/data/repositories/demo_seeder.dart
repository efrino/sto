import '../local/outbox_dao.dart';
import '../local/tag_dao.dart';
import '../models/app_user.dart';
import '../models/part_item.dart';
import '../models/print_batch.dart';
import '../models/sto_tag.dart';
import 'part_repository.dart';

/// Pengisi data contoh selama backend belum ada.
///
/// Membuat beberapa batch tag dengan bermacam kondisi (sudah cetak, masih
/// draft, dibatalkan, belum sinkron) supaya halaman Riwayat, filter status,
/// badge sinkronisasi, dan alur "lanjutkan cetak" bisa diuji tanpa server.
///
/// Nomornya sengaja berawalan `DEMO` supaya tidak pernah bentrok dengan nomor
/// asli dari server dan gampang dikenali saat dibersihkan.
class DemoSeeder {
  DemoSeeder({
    required this.partRepository,
    required this.tagDao,
    required this.outboxDao,
  });

  final PartRepository partRepository;
  final TagDao tagDao;
  final OutboxDao outboxDao;

  static const String prefix = 'DEMO';

  /// Mengisi data contoh. Mengembalikan jumlah tag yang dibuat.
  Future<int> seed(AppUser user) async {
    final parts = await _pickParts();
    if (parts.isEmpty) return 0;

    final now = DateTime.now();
    final dayPrefix = '$prefix'
        '${now.year.toString().substring(2)}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    var sequence = await tagDao.lastSequenceForPrefix(dayPrefix);

    // (jumlah tag, jumlah tercetak, jumlah dibatalkan, mundur berapa menit)
    const skenario = [
      _DemoBatch(tags: 3, printed: 3, cancelled: 0, minutesAgo: 180),
      _DemoBatch(tags: 2, printed: 0, cancelled: 0, minutesAgo: 90),
      _DemoBatch(tags: 3, printed: 1, cancelled: 2, minutesAgo: 45),
    ];

    var created = 0;
    for (var i = 0; i < skenario.length; i++) {
      final skema = skenario[i];
      final part = parts[i % parts.length];
      final createdAt = now.subtract(Duration(minutes: skema.minutesAgo));
      final batchId = '$dayPrefix-${(i + 1).toString().padLeft(2, '0')}';

      final tags = <StoTag>[];
      for (var t = 0; t < skema.tags; t++) {
        sequence++;
        final printed = t < skema.printed;
        final cancelled = !printed && t < skema.printed + skema.cancelled;

        tags.add(
          StoTag(
            tagNo: '$dayPrefix-${sequence.toString().padLeft(6, '0')}',
            sequence: sequence,
            batchId: batchId,
            partNumber: part.partNumber,
            jobNumber: part.jobNumber,
            partName: part.partName,
            customer: part.customer,
            model: part.model,
            unit: part.unit,
            area: part.area,
            location: part.location,
            partType: part.partType,
            status: printed
                ? TagStatus.printed
                : cancelled
                    ? TagStatus.cancelled
                    : TagStatus.draft,
            // Batch pertama dianggap sudah tersinkron, sisanya masih antre.
            syncStatus: i == 0 ? SyncStatus.synced : SyncStatus.pending,
            createdBy: user.nik,
            createdAt: createdAt,
            printedAt:
                printed ? createdAt.add(const Duration(minutes: 2)) : null,
            cancelledAt:
                cancelled ? createdAt.add(const Duration(minutes: 6)) : null,
            cancelReason: cancelled ? 'Mispart - part tidak sesuai' : null,
            note: 'DATA CONTOH',
          ),
        );
      }

      final batch = PrintBatch(
        batchId: batchId,
        partNumber: part.partNumber,
        jobNumber: part.jobNumber,
        partName: part.partName,
        area: part.area,
        qty: tags.length,
        createdBy: user.nik,
        createdAt: createdAt,
        note: 'DATA CONTOH',
      );

      await tagDao.insertBatch(batch, tags);
      created += tags.length;

      // Batch selain yang pertama ikut mengisi antrian outbox supaya tombol
      // Sinkron ada isinya saat diuji.
      if (i > 0) {
        for (final tag in tags.where((t) => t.status != TagStatus.draft)) {
          await outboxDao.enqueue(
            tag.status == TagStatus.printed
                ? OutboxType.tagPrinted
                : OutboxType.tagCancelled,
            tag.tagNo,
            {
              ...tag.toApiJson(),
              if (tag.status == TagStatus.cancelled)
                'reason': tag.cancelReason ?? '-',
            },
          );
        }
      }
    }

    return created;
  }

  Future<List<PartItem>> _pickParts() async {
    var parts = await partRepository.search('', limit: 30);
    if (parts.isEmpty) {
      // Cache masih kosong - tarik dulu master partnya (mode simulasi
      // dilayani MockStoApi, jadi selalu berhasil).
      await partRepository.refreshCache(force: true);
      parts = await partRepository.search('', limit: 30);
    }
    if (parts.isEmpty) return const [];

    // Ambil campuran FP dan WIP supaya kedua status ikut teruji.
    final fp = parts.where((p) => p.partType == 'FP').toList();
    final wip = parts.where((p) => p.partType == 'WIP').toList();
    return [
      if (fp.isNotEmpty) fp.first,
      if (wip.isNotEmpty) wip.first,
      if (fp.length > 1) fp[1] else parts.first,
    ];
  }
}

class _DemoBatch {
  const _DemoBatch({
    required this.tags,
    required this.printed,
    required this.cancelled,
    required this.minutesAgo,
  });

  final int tags;
  final int printed;
  final int cancelled;
  final int minutesAgo;
}
