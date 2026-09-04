import '../local/count_dao.dart';
import '../local/outbox_dao.dart';
import '../local/prefs_store.dart';
import '../local/tag_dao.dart';
import '../models/print_batch.dart';
import '../models/sto_tag.dart';
import '../remote/api_gateway.dart';

class SyncResult {
  const SyncResult({
    required this.sent,
    required this.failed,
    required this.remaining,
    this.lastError,
  });

  final int sent;
  final int failed;
  final int remaining;
  final String? lastError;

  bool get hasError => failed > 0;
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
      remaining: await outboxDao.count(),
      lastError: lastError,
    );
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
