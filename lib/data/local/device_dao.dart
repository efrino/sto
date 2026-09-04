import 'package:sqflite/sqflite.dart';

import '../models/sto_device.dart';
import 'app_database.dart';

/// Daftar perangkat perusahaan beserta NIK yang dipasangkan padanya.
class DeviceDao {
  DeviceDao(this._db);

  final AppDatabase _db;

  Future<List<StoDevice>> all() async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableDevices,
      orderBy: 'asset_name ASC, registered_at ASC',
    );
    return rows.map(StoDevice.fromMap).toList();
  }

  Future<StoDevice?> findById(String deviceId) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableDevices,
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoDevice.fromMap(rows.first);
  }

  /// Perangkat lain yang sudah memasang NIK ini - dipakai untuk memberi tahu
  /// admin bahwa satu NIK terpasang di lebih dari satu perangkat.
  Future<List<StoDevice>> withNik(String nik, {String? exceptDeviceId}) async {
    final semua = await all();
    return semua
        .where((d) =>
            d.allows(nik) &&
            (exceptDeviceId == null || d.deviceId != exceptDeviceId))
        .toList();
  }

  Future<void> save(StoDevice device) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tableDevices,
      device.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String deviceId) async {
    final db = await _db.database;
    await db.delete(
      AppDatabase.tableDevices,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> touch(String deviceId, DateTime at) async {
    final db = await _db.database;
    await db.update(
      AppDatabase.tableDevices,
      {'last_seen_at': at.toIso8601String()},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }
}
