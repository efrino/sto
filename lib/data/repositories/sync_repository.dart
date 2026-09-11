import '../local/count_dao.dart';
import '../local/outbox_dao.dart';
import '../local/prefs_store.dart';
import '../local/tag_dao.dart';
import '../models/print_batch.dart';
import '../models/sto_tag.dart';
import '../remote/api_client.dart';
import '../remote/api_gateway.dart';

class SyncResult {
  const SyncResult({
    required this.sent,
    required this.failed,
    required this.remaining,
    this.rejected = 0,
    this.lastError,
    this.rejectionMessage,
  });

  final int sent;

  /// Gagal sementara - jaringan, server sibuk. Tetap di antrean, dicoba lagi.
  final int failed;

  /// Ditolak tetap oleh server (4xx). Dikeluarkan dari antrean; mengulanginya
  /// tidak akan pernah berhasil.
  final int rejected;

  final int remaining;
  final String? lastError;

  /// Alasan penolakan terakhir, sudah dalam kalimat dari server.
  final String? rejectionMessage;

  bool get hasError => failed > 0 || rejected > 0;
}

/// Mengirim isi outbox ke server. Aman dipanggil berkali-kali:
/// item hanya dihapus dari antrian setelah server membalas sukses,
/// dan endpoint di sisi server dirancang idempoten (lihat docs/API_CONTRACT.md).
class SyncRepository {
  SyncRepository({
    required this.api,
    required this.outboxDao,
    required this.tagDao,
    required this.countDao,
    required this.prefs,
  });

  final ApiGateway api;
  final OutboxDao outboxDao;
  final TagDao tagDao;
  final CountDao countDao;
  final PrefsStore prefs;

  Future<int> pendingCount() => outboxDao.count();

  Future<SyncResult> flush({int limit = 50}) async {
    final items = await outboxDao.pending(limit: limit);
    var sent = 0;
    var failed = 0;
    String? lastError;

    var rejected = 0;
    String? rejectionMessage;

    for (final item in items) {
      try {
        await _send(item);
        await outboxDao.remove(item.id);
        if (item.type == OutboxType.countSubmitted) {
          await countDao.markSynced([item.refId]);
        } else if (item.type != OutboxType.batchCreated) {
          await tagDao.markSynced([item.refId]);
        }
        sent++;
      } on ApiException catch (e) {
        if (_penolakanTetap(e)) {
          // Server sudah memutuskan: tag tidak ada, angka milik orang lain,
          // permintaan tidak sah. Mengulanginya tiap sinkron hanya membuat
          // lencana "belum sinkron" menyala selamanya - dan, kalau item
          // semacam ini menumpuk, menghalangi kiriman sah di belakangnya.
          //
          // Barisnya ditandai GAGAL supaya masih terlihat di riwayat,
          // lalu dikeluarkan dari antrean.
          rejected++;
          rejectionMessage = e.message;
          await outboxDao.remove(item.id);
          if (item.type == OutboxType.countSubmitted) {
            await countDao.markFailed(item.refId);
          } else if (item.type != OutboxType.batchCreated) {
            await tagDao.markFailed(item.refId);
          }
        } else {
          failed++;
          lastError = e.toString();
          await outboxDao.markFailed(item.id, e.toString());
        }
      } catch (e) {
        failed++;
        lastError = e.toString();
        await outboxDao.markFailed(item.id, e.toString());
      }
    }

    if (sent > 0) await prefs.setLastSyncAt(DateTime.now());

    return SyncResult(
      sent: sent,
      failed: failed,
      rejected: rejected,
      remaining: await outboxDao.count(),
      lastError: lastError,
      rejectionMessage: rejectionMessage,
    );
  }

  /// Penolakan yang tidak akan berubah walau dicoba lagi.
  ///
  /// 4xx adalah keputusan server atas isi permintaannya - bukan keadaan
  /// sesaat. Dua pengecualian: 408 (server kehabisan waktu menunggu) dan 429
  /// (terlalu sering) memang sesaat, dan dicoba lagi nanti.
  static bool _penolakanTetap(ApiException e) {
    final kode = e.statusCode;
    if (kode == null) return false;
    if (kode == 408 || kode == 429) return false;
    return kode >= 400 && kode < 500;
  }

  Future<void> _send(OutboxItem item) async {
    switch (item.type) {
      case OutboxType.batchCreated:
        final batch = PrintBatch.fromMap(
          Map<String, dynamic>.from(item.payload['batch'] as Map),
        );
        final tags = (item.payload['tags'] as List)
            .map((e) => StoTag.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        await api.createBatch(batch, tags);
        break;
      case OutboxType.tagPrinted:
        await api.confirmPrint(StoTag.fromMap(item.payload));
        break;
      case OutboxType.printFailed:
        await api.reportPrintFailed(
          StoTag.fromMap(item.payload),
          '${item.payload['message'] ?? 'Percobaan cetak gagal'}',
        );
        break;
      case OutboxType.tagCancelled:
        final tag = StoTag.fromMap(item.payload);
        await api.cancelTag(tag, '${item.payload['reason'] ?? '-'}');
        break;
      case OutboxType.cancelRequested:
        final tag = StoTag.fromMap(item.payload);
        await api.requestCancelTag(tag, '${item.payload['reason'] ?? '-'}');
        break;
      case OutboxType.cancelRejected:
        await api.rejectCancelTag(StoTag.fromMap(item.payload));
        break;
      case OutboxType.countSubmitted:
        await api.submitCount(item.payload);
        break;
    }
  }
}
