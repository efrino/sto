import 'dart:convert';

import 'app_database.dart';

/// Jenis pekerjaan yang menunggu dikirim ke server.
enum OutboxType {
  tagPrinted,

  /// Percobaan cetak gagal (kertas habis, printer menolak). Keadaannya
  /// dicatat di server supaya tag yang lembarannya tidak keluar tetap
  /// terlihat admin, bukan hanya di perangkat yang mencetaknya.
  printFailed,
  /// Operator mengajukan pembatalan - menunggu persetujuan admin.
  cancelRequested,
  /// Admin menyetujui pembatalan.
  tagCancelled,
  /// Admin menolak pengajuan (tag kembali berstatus tercetak).
  cancelRejected,
  batchCreated,

  /// Hasil hitung STO dari halaman scan.
  countSubmitted,
}

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.type,
    required this.refId,
    required this.payload,
    required this.attempts,
    this.lastError,
    required this.createdAt,
  });

  final int id;
  final OutboxType type;
  final String refId;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;

  factory OutboxItem.fromMap(Map<String, dynamic> map) => OutboxItem(
        id: (map['id'] as num).toInt(),
        type: OutboxType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => OutboxType.tagPrinted,
        ),
        refId: map['ref_id'] as String? ?? '',
        payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        lastError: map['last_error'] as String?,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      );
}

/// Antrian sinkronisasi. Semua aksi (cetak / batal) dicatat di sini dulu,
/// jadi aplikasi tetap dipakai walau server mati atau API belum jadi.
class OutboxDao {
  OutboxDao(this._db);

  final AppDatabase _db;

  Future<int> enqueue(
    OutboxType type,
    String refId,
    Map<String, dynamic> payload,
  ) async {
    final db = await _db.database;
    return db.insert(AppDatabase.tableOutbox, {
      'type': type.name,
      'ref_id': refId,
      'payload': jsonEncode(payload),
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<OutboxItem>> pending({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableOutbox,
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(OutboxItem.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableOutbox}',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> remove(int id) async {
    final db = await _db.database;
    await db.delete(AppDatabase.tableOutbox, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(int id, String error) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE ${AppDatabase.tableOutbox} SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }
}
