import '../local/app_database.dart';

/// Membersihkan data contoh begitu aplikasi memakai API sungguhan.
///
/// Data contoh dibuat supaya aplikasi bisa dicoba sebelum backend ada. Begitu
/// server dipakai, sisa-sisanya berbahaya: event contoh ikut terbaca sebagai
/// "event berjalan" berbarengan dengan event dari server, dan master part
/// contoh memakai kode area yang tidak dikenal server sehingga daftar part
/// operator tampak kosong atau salah.
///
/// Yang dibersihkan hanya yang jelas buatan lokal:
/// - seluruh master part (API belum punya endpoint master part, jadi apa pun
///   yang tersimpan di sini pasti data contoh),
/// - event yang id-nya bukan angka (server memberi id numerik),
/// - batch & tag contoh dari penyemai versi lama (batch_id berawalan DEMO).
///
/// Akun TIDAK ikut dihapus: di situlah hak akses menu disimpan, dan
/// menghapusnya bisa mengunci admin dari menu Setting.
class PembersihDataContoh {
  PembersihDataContoh(this._db);

  final AppDatabase _db;

  /// Mengembalikan jumlah baris yang dibuang per tabel.
  Future<Map<String, int>> bersihkan() async {
    final db = await _db.database;

    final part = await db.delete(AppDatabase.tableParts);
    await db.delete(
      AppDatabase.tableCacheMeta,
      where: 'key = ?',
      whereArgs: ['parts'],
    );

    final event = await db.delete(
      AppDatabase.tableEvents,
      // id server selalu angka; id lokal berbentuk "STO-202609".
      where: "id GLOB '*[^0-9]*'",
    );

    final tag = await db.delete(
      AppDatabase.tableTags,
      where: "batch_id LIKE 'DEMO%' OR offline_sequence = 1 OR tag_no LIKE 'DEMO%' OR tag_no LIKE 'L%'",
    );
    final batch = await db.delete(
      AppDatabase.tableBatches,
      where: "batch_id LIKE 'DEMO%'",
    );
    final count = await db.delete(
      AppDatabase.tableCounts,
      where: "tag_no LIKE 'DEMO%' OR tag_no LIKE 'L%'",
    );
    final outbox = await db.delete(
      AppDatabase.tableOutbox,
      where: "ref_id LIKE 'DEMO%' OR ref_id LIKE 'L%'",
    );
    final user = await db.delete(
      AppDatabase.tableUsers,
      where: "areas LIKE '%WAREHOUSE%' OR nik IN ('A.20431', '11223344')",
    );

    return {
      'part': part,
      'event': event,
      'tag': tag,
      'batch': batch,
      'count': count,
      'outbox': outbox,
      'user': user,
    };
  }
}
