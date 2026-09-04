import 'package:sqflite/sqflite.dart';

import '../models/sto_count.dart';
import '../models/sto_tag.dart';
import 'app_database.dart';

class CountRuleException implements Exception {
  CountRuleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Hasil hitung STO: satu baris per (tag, tim).
class CountDao {
  CountDao(this._db);

  final AppDatabase _db;

  Future<StoCount?> findByTagAndTeam(String tagNo, String team) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableCounts,
      where: 'tag_no = ? AND UPPER(team) = ?',
      whereArgs: [tagNo, team.trim().toUpperCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoCount.fromMap(rows.first);
  }

  /// Semua catatan untuk satu tag (bisa lebih dari satu bila beda tim).
  Future<List<StoCount>> byTag(String tagNo) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableCounts,
      where: 'tag_no = ?',
      whereArgs: [tagNo],
      orderBy: 'counted_at ASC',
    );
    return rows.map(StoCount.fromMap).toList();
  }

  Future<StoCount> save(StoCount count) async {
    final db = await _db.database;
    if (count.id == null) {
      final id = await db.insert(
        AppDatabase.tableCounts,
        count.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return count.copyWith(id: id);
    }
    await db.update(
      AppDatabase.tableCounts,
      count.toMap(),
      where: 'id = ?',
      whereArgs: [count.id],
    );
    return count;
  }

  /// Riwayat scan (hasil hitung) terbaru lebih dulu.
  Future<List<StoCount>> recent({int limit = 200, String? keyword}) async {
    final db = await _db.database;
    final key = keyword?.trim().toLowerCase() ?? '';
    final rows = await db.query(
      AppDatabase.tableCounts,
      where: key.isEmpty
          ? null
          : '(LOWER(tag_no) LIKE ? OR LOWER(part_number) LIKE ? '
              'OR LOWER(job_number) LIKE ? OR LOWER(team) LIKE ?)',
      whereArgs: key.isEmpty ? null : List.filled(4, '%$key%'),
      orderBy: 'COALESCE(updated_at, counted_at) DESC',
      limit: limit,
    );
    return rows.map(StoCount.fromMap).toList();
  }

  Future<List<StoCount>> pendingSync({int limit = 200}) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableCounts,
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.synced.name],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(StoCount.fromMap).toList();
  }

  Future<void> markSynced(Iterable<String> tagNos) async {
    if (tagNos.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final tagNo in tagNos) {
      batch.update(
        AppDatabase.tableCounts,
        {'sync_status': SyncStatus.synced.name},
        where: 'tag_no = ?',
        whereArgs: [tagNo],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Ringkasan untuk dashboard: jumlah tag terhitung & total qty hari ini.
  Future<Map<String, int>> todaySummary() async {
    final db = await _db.database;
    final now = DateTime.now();
    final prefix = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS jumlah, COALESCE(SUM(qty), 0) AS total
      FROM ${AppDatabase.tableCounts}
      WHERE substr(COALESCE(updated_at, counted_at), 1, 10) = ?
      ''',
      [prefix],
    );
    final pending = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableCounts} '
      'WHERE sync_status != ?',
      [SyncStatus.synced.name],
    );

    return {
      'scan': (rows.first['jumlah'] as num?)?.toInt() ?? 0,
      'qty': (rows.first['total'] as num?)?.toInt() ?? 0,
      'pending_sync': (pending.first['c'] as num?)?.toInt() ?? 0,
    };
  }
}
