import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import 'app_database.dart';

/// Daftar user beserta izinnya. Selama API belum ada, tabel ini berperan
/// sebagai "master user" yang dikelola admin lewat menu Setting.
class UserDao {
  UserDao(this._db);

  final AppDatabase _db;

  Future<List<AppUser>> all() async {
    final db = await _db.database;
    final rows = await db.query(AppDatabase.tableUsers, orderBy: 'name ASC');
    return rows.map(AppUser.fromMap).toList();
  }

  Future<AppUser?> findByNik(String nik) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableUsers,
      where: 'UPPER(nik) = ?',
      whereArgs: [nik.trim().toUpperCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  Future<void> save(AppUser user) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tableUsers,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String nik) async {
    final db = await _db.database;
    await db.delete(
      AppDatabase.tableUsers,
      where: 'nik = ?',
      whereArgs: [nik],
    );
  }

  Future<int> count() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableUsers}',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> adminCount({String? exceptNik}) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableUsers} '
      'WHERE role = ? AND active = 1 AND nik != ?',
      [UserRole.admin.name, exceptNik ?? ''],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> saveAll(List<AppUser> users) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final user in users) {
      batch.insert(
        AppDatabase.tableUsers,
        user.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
