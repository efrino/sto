import 'package:sqflite/sqflite.dart';

import '../models/sto_event.dart';
import 'app_database.dart';

/// Periode STO. Tag hanya boleh dibuat ketika ada event berstatus BUKA yang
/// tanggalnya mencakup hari ini.
class EventDao {
  EventDao(this._db);

  final AppDatabase _db;

  Future<List<StoEvent>> all() async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableEvents,
      orderBy: 'start_date DESC',
    );
    return rows.map(StoEvent.fromMap).toList();
  }

  Future<StoEvent?> findById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableEvents,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoEvent.fromMap(rows.first);
  }

  /// Event aktif untuk tanggal tertentu. Bila ada beberapa yang cocok,
  /// diambil yang paling baru dimulai.
  Future<StoEvent?> activeOn(DateTime date) async {
    final events = await all();
    for (final event in events) {
      if (event.isActiveOn(date)) return event;
    }
    return null;
  }

  Future<void> save(StoEvent event) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tableEvents,
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete(
      AppDatabase.tableEvents,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> count() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableEvents}',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Jumlah tag yang sudah terikat ke event - dipakai untuk mencegah
  /// penghapusan event yang sudah punya jejak cetak.
  Future<int> tagCount(String eventId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableTags} WHERE event_id = ?',
      [eventId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }
}
