import 'package:sqflite/sqflite.dart';

import '../models/print_batch.dart';
import '../models/sto_tag.dart';
import 'app_database.dart';

/// Dilempar ketika ada percobaan mencetak tag yang sudah pernah dicetak
/// atau sudah dibatalkan. Aturan "1 tag = 1 kali cetak" dijaga di sini,
/// bukan hanya di UI.
class TagStateException implements Exception {
  TagStateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TagDao {
  TagDao(this._db);

  final AppDatabase _db;

  Future<List<StoTag>> insertBatch(PrintBatch batch, List<StoTag> tags) async {
    final db = await _db.database;
    final result = <StoTag>[];
    await db.transaction((txn) async {
      await txn.insert(
        AppDatabase.tableBatches,
        batch.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final tag in tags) {
        // Tag_no UNIQUE: kalau nomor bentrok (mis. sequence offline dobel),
        // insert akan gagal dan seluruh batch dibatalkan.
        final id = await txn.insert(
          AppDatabase.tableTags,
          tag.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        result.add(tag.copyWith(id: id));
      }
    });
    return result;
  }

  /// Tandai tag sebagai TERCETAK. Hanya berhasil bila statusnya masih draft,
  /// sehingga cetak ulang mustahil walau UI-nya di-bypass.
  Future<StoTag> markPrinted(StoTag tag, {DateTime? at}) async {
    final db = await _db.database;
    final printedAt = at ?? DateTime.now();
    final affected = await db.update(
      AppDatabase.tableTags,
      {
        'status': TagStatus.printed.name,
        'printed_at': printedAt.toIso8601String(),
        'sync_status': SyncStatus.pending.name,
      },
      where: 'tag_no = ? AND status = ?',
      whereArgs: [tag.tagNo, TagStatus.draft.name],
    );
    if (affected == 0) {
      final current = await findByTagNo(tag.tagNo);
      throw TagStateException(
        current == null
            ? 'Tag ${tag.tagNo} tidak ditemukan di database lokal.'
            : 'Tag ${tag.tagNo} tidak bisa dicetak lagi (status: ${current.status.label}).',
      );
    }
    return (await findByTagNo(tag.tagNo))!;
  }

  /// Operator mengajukan pembatalan tag yang SUDAH TERCETAK.
  /// Statusnya belum berubah jadi dibatalkan - menunggu persetujuan admin.
  Future<StoTag> requestCancel(
    String tagNo,
    String reason,
    String requestedBy, {
    DateTime? at,
  }) async {
    final db = await _db.database;
    final now = at ?? DateTime.now();
    final affected = await db.update(
      AppDatabase.tableTags,
      {
        'status': TagStatus.pendingCancel.name,
        'cancel_reason': reason,
        'cancel_requested_by': requestedBy,
        'cancel_requested_at': now.toIso8601String(),
        'sync_status': SyncStatus.pending.name,
      },
      where: 'tag_no = ? AND status = ?',
      whereArgs: [tagNo, TagStatus.printed.name],
    );
    if (affected == 0) {
      final current = await findByTagNo(tagNo);
      throw TagStateException(
        current == null
            ? 'Tag $tagNo tidak ditemukan di perangkat ini.'
            : 'Tag $tagNo tidak bisa diajukan batal (status: ${current.status.label}).',
      );
    }
    return (await findByTagNo(tagNo))!;
  }

  /// Admin menyetujui pembatalan (langsung dari tag tercetak juga boleh).
  Future<StoTag> approveCancel(
    String tagNo,
    String approvedBy, {
    String? reason,
    DateTime? at,
  }) async {
    final db = await _db.database;
    final now = at ?? DateTime.now();
    final affected = await db.update(
      AppDatabase.tableTags,
      {
        'status': TagStatus.cancelled.name,
        'cancelled_at': now.toIso8601String(),
        'cancel_approved_by': approvedBy,
        'cancel_reason': ?reason,
        'sync_status': SyncStatus.pending.name,
      },
      where: 'tag_no = ? AND status IN (?, ?)',
      whereArgs: [tagNo, TagStatus.printed.name, TagStatus.pendingCancel.name],
    );
    if (affected == 0) {
      final current = await findByTagNo(tagNo);
      throw TagStateException(
        current == null
            ? 'Tag $tagNo tidak ditemukan di perangkat ini.'
            : 'Tag $tagNo tidak bisa dibatalkan (status: ${current.status.label}).',
      );
    }
    return (await findByTagNo(tagNo))!;
  }

  /// Admin menolak pengajuan - tag kembali berstatus SUDAH CETAK.
  Future<StoTag> rejectCancel(String tagNo, String rejectedBy) async {
    final db = await _db.database;
    final affected = await db.update(
      AppDatabase.tableTags,
      {
        'status': TagStatus.printed.name,
        'cancel_reason': null,
        'cancel_requested_by': null,
        'cancel_requested_at': null,
        'cancel_approved_by': rejectedBy,
        'sync_status': SyncStatus.pending.name,
      },
      where: 'tag_no = ? AND status = ?',
      whereArgs: [tagNo, TagStatus.pendingCancel.name],
    );
    if (affected == 0) {
      throw TagStateException(
        'Pengajuan pembatalan tag $tagNo sudah tidak berlaku.',
      );
    }
    return (await findByTagNo(tagNo))!;
  }

  /// Daftar pengajuan pembatalan yang menunggu persetujuan admin.
  Future<List<StoTag>> pendingCancelRequests({int limit = 100}) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableTags,
      where: 'status = ?',
      whereArgs: [TagStatus.pendingCancel.name],
      orderBy: 'cancel_requested_at ASC',
      limit: limit,
    );
    return rows.map(StoTag.fromMap).toList();
  }

  /// Membatalkan seluruh tag pada satu batch - hanya dipakai admin.
  Future<int> cancelBatch(
    String batchId,
    String reason,
    String approvedBy,
  ) async {
    final db = await _db.database;
    return db.update(
      AppDatabase.tableTags,
      {
        'status': TagStatus.cancelled.name,
        'cancelled_at': DateTime.now().toIso8601String(),
        'cancel_reason': reason,
        'cancel_approved_by': approvedBy,
        'sync_status': SyncStatus.pending.name,
      },
      where: 'batch_id = ? AND status != ?',
      whereArgs: [batchId, TagStatus.cancelled.name],
    );
  }

  Future<void> markSynced(Iterable<String> tagNos) async {
    if (tagNos.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final tagNo in tagNos) {
      batch.update(
        AppDatabase.tableTags,
        {'sync_status': SyncStatus.synced.name},
        where: 'tag_no = ?',
        whereArgs: [tagNo],
      );
    }
    await batch.commit(noResult: true);
  }


  /// Menimpa baris lokal dengan keadaan terakhir dari server.
  ///
  /// Murni cache: dipanggil SETELAH server menerima keputusan, jadi tidak ada
  /// penjaga status di sini - baris lokal memang harus mengikuti server, bukan
  /// sebaliknya.
  Future<void> timpaDariServer(StoTag tag) async {
    final db = await _db.database;
    await db.update(
      AppDatabase.tableTags,
      {
        'status': tag.status.name,
        'cancelled_at': tag.cancelledAt?.toIso8601String(),
        'cancel_reason': tag.cancelReason,
        'cancel_requested_by': tag.cancelRequestedBy,
        'cancel_requested_at': tag.cancelRequestedAt?.toIso8601String(),
        'cancel_approved_by': tag.cancelApprovedBy,
        // Datang DARI server - tidak perlu dikirim balik.
        'sync_status': SyncStatus.synced.name,
      },
      where: 'tag_no = ?',
      whereArgs: [tag.tagNo],
    );
  }

  Future<StoTag?> findByTagNo(String tagNo) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableTags,
      where: 'tag_no = ?',
      whereArgs: [tagNo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoTag.fromMap(rows.first);
  }

  Future<List<StoTag>> byBatch(String batchId) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableTags,
      where: 'batch_id = ?',
      whereArgs: [batchId],
      orderBy: 'sequence ASC',
    );
    return rows.map(StoTag.fromMap).toList();
  }

  Future<List<StoTag>> recent({
    int limit = 100,
    TagStatus? status,
    String? keyword,
  }) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      final key = '%${keyword.trim().toLowerCase()}%';
      where.add(
        '(LOWER(tag_no) LIKE ? OR LOWER(part_number) LIKE ? OR LOWER(job_number) LIKE ?)',
      );
      args.addAll([key, key, key]);
    }
    final rows = await db.query(
      AppDatabase.tableTags,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(StoTag.fromMap).toList();
  }

  Future<List<StoTag>> pendingSync({int limit = 200}) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableTags,
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.synced.name],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(StoTag.fromMap).toList();
  }

  /// Ringkasan untuk dashboard: total tag hari ini, tercetak, dibatalkan, draft.
  Future<Map<String, int>> todaySummary() async {
    final db = await _db.database;
    final today = DateTime.now();
    final prefix =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final rows = await db.rawQuery(
      '''
      SELECT status, COUNT(*) AS c
      FROM ${AppDatabase.tableTags}
      WHERE substr(created_at, 1, 10) = ?
      GROUP BY status
      ''',
      [prefix],
    );
    final result = <String, int>{
      'total': 0,
      TagStatus.draft.name: 0,
      TagStatus.printed.name: 0,
      TagStatus.pendingCancel.name: 0,
      TagStatus.cancelled.name: 0,
    };
    for (final row in rows) {
      final status = row['status'] as String? ?? TagStatus.draft.name;
      final count = (row['c'] as num?)?.toInt() ?? 0;
      result[status] = count;
      result['total'] = (result['total'] ?? 0) + count;
    }
    final pending = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableTags} WHERE sync_status != ?',
      [SyncStatus.synced.name],
    );
    result['pending_sync'] = (pending.first['c'] as num?)?.toInt() ?? 0;
    return result;
  }

  /// Aktivitas hari ini pada perangkat ini: berapa tag yang benar-benar
  /// tercetak dan berapa yang masuk proses pembatalan (diajukan atau sudah
  /// dibatalkan). Dipakai kartu ringkasan di halaman utama.
  Future<Map<String, int>> todayActivity() async {
    final db = await _db.database;
    final now = DateTime.now();
    final hari = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final cetak = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableTags} '
      'WHERE substr(printed_at, 1, 10) = ?',
      [hari],
    );
    final batal = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableTags} '
      'WHERE substr(cancelled_at, 1, 10) = ? '
      'OR substr(cancel_requested_at, 1, 10) = ?',
      [hari, hari],
    );

    return {
      'printed': (cetak.first['c'] as num?)?.toInt() ?? 0,
      'cancel': (batal.first['c'] as num?)?.toInt() ?? 0,
    };
  }

  /// Nomor urut lokal terakhir untuk prefix tertentu (fallback offline).
  Future<int> lastSequenceForPrefix(String prefix) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT MAX(sequence) AS s FROM ${AppDatabase.tableTags} WHERE tag_no LIKE ?',
      ['$prefix%'],
    );
    return (rows.first['s'] as num?)?.toInt() ?? 0;
  }

  Future<List<PrintBatch>> recentBatches({int limit = 30}) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT b.*,
             SUM(CASE WHEN t.status = 'printed'   THEN 1 ELSE 0 END) AS printed_count,
             SUM(CASE WHEN t.status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count
      FROM ${AppDatabase.tableBatches} b
      LEFT JOIN ${AppDatabase.tableTags} t ON t.batch_id = b.batch_id
      GROUP BY b.batch_id
      ORDER BY b.created_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(PrintBatch.fromMap).toList();
  }
}
