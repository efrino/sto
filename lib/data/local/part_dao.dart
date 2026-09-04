import 'package:sqflite/sqflite.dart';

import '../models/part_item.dart';
import 'app_database.dart';

/// Akses cache master part/job di sqflite.
class PartDao {
  PartDao(this._db);

  final AppDatabase _db;

  Future<void> replaceAll(List<PartItem> parts) async {
    final db = await _db.database;
    final batch = db.batch();
    batch.delete(AppDatabase.tableParts);
    for (final part in parts) {
      batch.insert(
        AppDatabase.tableParts,
        part.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await _touchMeta(count: parts.length);
  }

  Future<void> upsertAll(List<PartItem> parts) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final part in parts) {
      batch.insert(
        AppDatabase.tableParts,
        part.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Pencarian part. [areas] = daftar area yang boleh dilihat user
  /// (kosong berarti tanpa batas, mis. untuk admin) dan diterjemahkan menjadi
  /// `WHERE UPPER(area) IN ('AREA 1','AREA 2')`.
  Future<List<PartItem>> search(
    String keyword, {
    int limit = 50,
    int offset = 0,
    List<String> areas = const [],
  }) async {
    final db = await _db.database;
    final key = keyword.trim().toLowerCase();

    final where = <String>[];
    final args = <Object?>[];

    if (key.isNotEmpty) {
      where.add('search_index LIKE ?');
      args.add('%$key%');
    }
    if (areas.isNotEmpty) {
      final placeholders = List.filled(areas.length, '?').join(', ');
      where.add('UPPER(area) IN ($placeholders)');
      args.addAll(areas.map((a) => a.trim().toUpperCase()));
    }

    final rows = await db.query(
      AppDatabase.tableParts,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'part_number ASC, job_number ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(PartItem.fromMap).toList();
  }

  /// Daftar area yang ada di master part - dipakai admin saat mengatur izin
  /// user dan cakupan event.
  Future<List<String>> distinctAreas() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT area FROM ${AppDatabase.tableParts} '
      "WHERE area IS NOT NULL AND area != '' ORDER BY area ASC",
    );
    return rows
        .map((r) => '${r['area']}'.trim().toUpperCase())
        .where((a) => a.isNotEmpty)
        .toList();
  }

  Future<PartItem?> findByPartAndJob(String partNumber, String jobNumber) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableParts,
      where: 'part_number = ? AND job_number = ?',
      whereArgs: [partNumber, jobNumber],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PartItem.fromMap(rows.first);
  }

  Future<int> count() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableParts}',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<DateTime?> lastSyncedAt() async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableCacheMeta,
      where: 'key = ?',
      whereArgs: ['parts'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse('${rows.first['updated_at']}');
  }

  Future<bool> isStale(Duration ttl) async {
    final last = await lastSyncedAt();
    if (last == null) return true;
    return DateTime.now().difference(last) > ttl;
  }

  Future<void> _touchMeta({required int count}) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tableCacheMeta,
      {
        'key': 'parts',
        'updated_at': DateTime.now().toIso8601String(),
        'info': '$count part',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
