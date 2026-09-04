import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Database lokal (offline-first cache).
///
/// Tiga fungsi utama:
/// 1. `parts`   - cache master part/job supaya pencarian tetap jalan tanpa sinyal.
/// 2. `tags`    - sumber kebenaran status cetak (UNIQUE tag_no => tidak bisa dobel).
/// 3. `outbox`  - antrian kirim ke server ketika API sudah tersedia / online lagi.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String dbName = 'sto_prep.db';
  static const int dbVersion = 7;

  static const String tableParts = 'parts';
  static const String tableTags = 'tags';
  static const String tableBatches = 'batches';
  static const String tableOutbox = 'outbox';
  static const String tableCacheMeta = 'cache_meta';
  static const String tableUsers = 'users';
  static const String tableEvents = 'sto_events';
  static const String tableCounts = 'sto_counts';
  static const String tableDevices = 'devices';
  static const String tableTeams = 'teams';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), dbName);
    _db = await openDatabase(
      path,
      version: dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableParts (
        part_number   TEXT NOT NULL,
        job_number    TEXT NOT NULL,
        part_name     TEXT,
        customer      TEXT,
        model         TEXT,
        unit          TEXT,
        area          TEXT,
        location      TEXT,
        part_type     TEXT DEFAULT 'FP',
        std_pack      INTEGER DEFAULT 0,
        search_index  TEXT,
        updated_at    TEXT,
        PRIMARY KEY (part_number, job_number)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_parts_search ON $tableParts (search_index)',
    );

    await db.execute('''
      CREATE TABLE $tableTags (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        tag_no           TEXT NOT NULL UNIQUE,
        sequence         INTEGER NOT NULL,
        batch_id         TEXT NOT NULL,
        part_number      TEXT NOT NULL,
        job_number       TEXT NOT NULL,
        part_name        TEXT,
        customer         TEXT,
        model            TEXT,
        unit             TEXT,
        area             TEXT,
        location         TEXT,
        part_type        TEXT DEFAULT 'FP',
        event_id         TEXT,
        qty              INTEGER DEFAULT 0,
        status           TEXT NOT NULL DEFAULT 'draft',
        sync_status      TEXT NOT NULL DEFAULT 'pending',
        created_by       TEXT,
        created_at       TEXT,
        printed_at       TEXT,
        cancelled_at     TEXT,
        cancel_reason    TEXT,
        cancel_requested_by TEXT,
        cancel_requested_at TEXT,
        cancel_approved_by  TEXT,
        note             TEXT,
        offline_sequence INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_tags_batch ON $tableTags (batch_id)');
    await db.execute('CREATE INDEX idx_tags_status ON $tableTags (status)');
    await db.execute(
      'CREATE INDEX idx_tags_part ON $tableTags (part_number, job_number)',
    );

    await db.execute('''
      CREATE TABLE $tableBatches (
        batch_id    TEXT PRIMARY KEY,
        part_number TEXT,
        job_number  TEXT,
        part_name   TEXT,
        area        TEXT,
        qty         INTEGER,
        created_by  TEXT,
        created_at  TEXT,
        note        TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableOutbox (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        type       TEXT NOT NULL,
        ref_id     TEXT,
        payload    TEXT NOT NULL,
        attempts   INTEGER DEFAULT 0,
        last_error TEXT,
        created_at TEXT
      )
    ''');

    await _createUserAndEventTables(db);

    await _createCountTable(db);
    await _createDeviceTable(db);
    await _createTeamTable(db);

    await db.execute('''
      CREATE TABLE $tableCacheMeta (
        key        TEXT PRIMARY KEY,
        updated_at TEXT,
        info       TEXT
      )
    ''');
  }

  /// Tabel milik "server tiruan": daftar user beserta izinnya, dan periode STO.
  /// Saat API tersedia keduanya diisi dari server, strukturnya sengaja dibuat
  /// menyerupai payload API (lihat docs/API_CONTRACT.md).
  Future<void> _createUserAndEventTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableUsers (
        nik        TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        department TEXT,
        section    TEXT,
        role        TEXT NOT NULL DEFAULT 'operator',
        areas       TEXT,
        team        TEXT,
        permissions TEXT,
        active      INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableEvents (
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date   TEXT NOT NULL,
        areas      TEXT,
        status     TEXT NOT NULL DEFAULT 'open',
        created_by TEXT,
        created_at TEXT
      )
    ''');
  }

  /// Hasil hitung STO per tag per tim.
  ///
  /// UNIQUE(tag_no, team): satu tim hanya boleh punya satu angka untuk satu
  /// tag, tetapi tim lain tetap boleh menghitung tag yang sama.
  Future<void> _createCountTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCounts (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        tag_no      TEXT NOT NULL,
        nik         TEXT NOT NULL,
        team        TEXT NOT NULL,
        qty         INTEGER NOT NULL DEFAULT 0,
        part_number TEXT,
        job_number  TEXT,
        part_name   TEXT,
        area        TEXT,
        unit        TEXT,
        counted_at  TEXT,
        updated_at  TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        UNIQUE (tag_no, team)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_counts_tag ON $tableCounts (tag_no)',
    );
  }

  /// Perangkat perusahaan beserta NIK yang dipasangkan padanya.
  ///
  /// Kunci teknisnya ANDROID_ID (kolom device_id) - MAC address tidak dipakai
  /// karena Android tidak lagi mengizinkan aplikasi membacanya.
  Future<void> _createDeviceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDevices (
        device_id     TEXT PRIMARY KEY,
        asset_name    TEXT,
        model         TEXT,
        niks          TEXT,
        active        INTEGER NOT NULL DEFAULT 1,
        registered_at TEXT,
        registered_by TEXT,
        last_seen_at  TEXT,
        server_id     INTEGER,
        total_user_server INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Daftar tim (A, B, ...) yang dikelola admin dan dipakai sebagai pilihan
  /// pada data user maupun kunci hasil hitung.
  Future<void> _createTeamTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableTeams (
        name   TEXT PRIMARY KEY,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    for (final nama in const ['A', 'B']) {
      await db.insert(
        tableTeams,
        {'name': nama, 'active': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Menambah kolom hanya bila belum ada.
  ///
  /// Migrasi harus tahan dijalankan ulang: bila satu langkah gagal di tengah
  /// jalan, versi database tidak jadi naik sehingga langkah yang sudah sukses
  /// akan diulang pada pembukaan berikutnya. Tanpa penjagaan ini, ALTER TABLE
  /// kedua kalinya melempar "duplicate column" dan aplikasi gagal dibuka.
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final sudahAda = info.any((row) => row['name'] == column);
    if (sudahAda) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrasi selalu ALTER TABLE - tabel `tags` berisi bukti cetak yang
    // belum tersinkron, jangan pernah di-drop.
    if (oldVersion < 2) {
      // v2: kolom status part (FP/WIP) menggantikan lokasi pada layout tag.
      await _addColumnIfMissing(
        db,
        tableParts,
        'part_type',
        "TEXT DEFAULT 'FP'",
      );
      await _addColumnIfMissing(
        db,
        tableTags,
        'part_type',
        "TEXT DEFAULT 'FP'",
      );
    }

    if (oldVersion < 3) {
      // v3: peran & area user, periode STO, serta alur pengajuan pembatalan.
      await _createUserAndEventTables(db);
      for (final column in const [
        'event_id',
        'cancel_requested_by',
        'cancel_requested_at',
        'cancel_approved_by',
      ]) {
        await _addColumnIfMissing(db, tableTags, column, 'TEXT');
      }
    }

    if (oldVersion < 4) {
      // v4: hasil hitung per tim + kolom tim pada data user.
      await _createCountTable(db);
      await _addColumnIfMissing(db, tableUsers, 'team', 'TEXT');
    }

    if (oldVersion < 5) {
      // v5: pemasangan NIK ke perangkat (pengganti MAC address).
      await _createDeviceTable(db);
    }

    if (oldVersion < 6) {
      // v6: hak akses per menu + daftar tim yang dikelola admin.
      await _addColumnIfMissing(db, tableUsers, 'permissions', 'TEXT');
      await _createTeamTable(db);

      // Nilai lama "TIM A" diseragamkan menjadi "A" agar cocok dengan
      // pilihan tim yang baru.
      await db.execute(
        "UPDATE $tableUsers SET team = TRIM(SUBSTR(team, 5)) "
        "WHERE team LIKE 'TIM %'",
      );
      await db.execute(
        "UPDATE $tableCounts SET team = TRIM(SUBSTR(team, 5)) "
        "WHERE team LIKE 'TIM %'",
      );
    }

    if (oldVersion < 7) {
      await _migrasiV7(db);
    }
  }

  Future<void> _migrasiV7(Database db) async {
    // v7: identitas perangkat versi server (devices.id) ikut disimpan supaya
    // aplikasi tahu perangkat ini sudah didaftarkan admin lewat API atau belum.
    await _addColumnIfMissing(db, tableDevices, 'server_id', 'INTEGER');
    await _addColumnIfMissing(
      db,
      tableDevices,
      'total_user_server',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Hapus cache master part saja - data tag tetap aman.
  Future<void> clearPartCache() async {
    final db = await database;
    await db.delete(tableParts);
    await db.delete(tableCacheMeta, where: 'key = ?', whereArgs: ['parts']);
  }

  /// Reset total (dipakai di menu Setting -> Hapus data lokal).
  /// Reset total. Daftar user & event ikut dikosongkan lalu disemai ulang
  /// oleh repository saat aplikasi dijalankan, supaya perangkat tidak terkunci
  /// tanpa admin.
  Future<void> wipe() async {
    final db = await database;
    await db.delete(tableParts);
    await db.delete(tableTags);
    await db.delete(tableBatches);
    await db.delete(tableOutbox);
    await db.delete(tableCacheMeta);
    await db.delete(tableUsers);
    await db.delete(tableEvents);
    await db.delete(tableCounts);
    await db.delete(tableDevices);
    await db.delete(tableTeams);
  }
}
