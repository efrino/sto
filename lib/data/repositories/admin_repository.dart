import '../../core/config/app_config.dart';
import '../local/event_dao.dart';
import '../local/part_dao.dart';
import '../local/user_dao.dart';
import '../models/app_user.dart';
import '../models/sto_event.dart';
import '../remote/api_client.dart';
import '../remote/api_gateway.dart';
import '../remote/sto_api.dart';

/// Dilempar saat aturan pengelolaan dilanggar (mis. menghapus admin terakhir).
class AdminRuleException implements Exception {
  AdminRuleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Pengelolaan user & event STO oleh admin.
///
/// Sekarang menulis ke database lokal (server tiruan). Saat API tersedia,
/// tiap method di sini tinggal memanggil endpoint yang setara - lihat
/// docs/API_CONTRACT.md bagian "Admin".
class AdminRepository {
  AdminRepository({
    required this.userDao,
    required this.eventDao,
    required this.partDao,
    required this.api,
  });

  final UserDao userDao;
  final EventDao eventDao;
  final PartDao partDao;
  final ApiGateway api;

  /// Diisi bila daftar event terakhir terpaksa diambil dari cache.
  String? peringatanSinkron;

  // ------------------------------------------------------------------ user
  Future<List<AppUser>> users() => userDao.all();

  /// Daftar akun dari server, lalu disalin ke cache perangkat.
  ///
  /// Server adalah sumber kebenaran - termasuk hak akses menu, yang kini
  /// tersimpan di kolom `users.permissions`. Cache hanya dipakai supaya
  /// halaman tetap terisi saat jaringan mati.
  Future<List<AppUser>> syncUsers(AppUser admin) async {
    peringatanSinkron = null;
    if (!admin.isAdmin) return userDao.all();

    try {
      final dariServer = await api.fetchUsers(admin.nik, limit: 500);
      await _tulisCacheUser(dariServer);
      return dariServer;
    } on ApiException catch (e) {
      peringatanSinkron = 'Daftar user tidak bisa dibaca - server: $e';
      return const [];
    }
  }

  /// Menyamakan cache akun perangkat dengan daftar server.
  ///
  /// Bukan sekadar hiasan offline: aturan lokal (NIK ganda, "admin terakhir")
  /// membaca tabel ini. Selama tidak pernah diisi, isinya hanya akun yang
  /// pernah login di perangkat ini - sehingga penjagaannya menilai keadaan
  /// yang jauh lebih sempit dari keadaan sebenarnya.
  Future<void> _tulisCacheUser(List<AppUser> dariServer) async {
    final adaDiServer = dariServer.map((u) => u.nik.toUpperCase()).toSet();
    for (final lama in await userDao.all()) {
      if (!adaDiServer.contains(lama.nik.toUpperCase())) {
        await userDao.delete(lama.nik);
      }
    }
    for (final user in dariServer) {
      await userDao.save(user);
    }
  }

  /// Akun yang terpasang pada satu perangkat (untuk halaman Perangkat).
  Future<List<AppUser>> usersOnDevice(AppUser admin, int deviceId) =>
      api.fetchUsers(admin.nik, deviceId: deviceId);

  Future<void> saveUser(
    AppUser user, {
    String? previousNik,
    AppUser? admin,
  }) async {
    final nik = user.nik.trim().toUpperCase();
    if (nik.length < 3) {
      throw AdminRuleException('NIK minimal 3 karakter.');
    }
    if (user.name.trim().isEmpty) {
      throw AdminRuleException('Nama wajib diisi.');
    }

    final isNew = previousNik == null;
    if (isNew && await userDao.findByNik(nik) != null) {
      throw AdminRuleException('NIK $nik sudah terdaftar.');
    }

    // Server menolak penggantian NIK: `sto_data.nik_a`/`nik_b` menyimpannya
    // sebagai teks biasa, jadi mengubahnya membuat riwayat scan lama yatim.
    if (!isNew && previousNik.toUpperCase() != nik) {
      throw AdminRuleException(
        'NIK tidak bisa diubah - riwayat scan menyimpannya sebagai teks, '
        'bukan referensi. Hapus akun $previousNik lalu daftarkan $nik '
        'sebagai akun baru.',
      );
    }

    // Jangan sampai perangkat kehilangan admin terakhir.
    final turunJabatan = !isNew && (!user.isAdmin || !user.active);
    if (turunJabatan) {
      final sebelumnya = await userDao.findByNik(previousNik);
      if (sebelumnya != null && sebelumnya.isAdmin && sebelumnya.active) {
        final adminLain = await userDao.adminCount(exceptNik: previousNik);
        if (adminLain == 0) {
          throw AdminRuleException(
            'Ini satu-satunya admin aktif. Tambahkan admin lain dulu sebelum '
            'mengubah perannya.',
          );
        }
      }
    }

    // Server adalah master daftar akun: kalau penyimpanan di sana gagal,
    // jangan sampai perangkat menyimpan user yang sebetulnya tidak ada.
    if (admin != null && admin.isAdmin) {
      try {
        if (isNew) {
          await api.registerUser(
            user.copyWith(nik: nik),
            createdBy: admin.nik,
          );
        } else {
          await api.updateUser(
            adminNik: admin.nik,
            targetNik: previousNik,
            role: user.role.name,
            team: user.team,
            areas: user.areas,
            permissions: user.permissions.map((p) => p.name).toList(),
          );
        }
      } on ApiException catch (e) {
        throw AdminRuleException('Gagal di server: $e');
      }
    }

    if (previousNik != null && previousNik.toUpperCase() != nik) {
      await userDao.delete(previousNik);
    }
    await userDao.save(user.copyWith(nik: nik));
  }

  Future<void> deleteUser(
    String nik, {
    AppUser? admin,
    bool force = false,
  }) async {
    final user = await userDao.findByNik(nik);
    if (user == null) return;
    if (user.isAdmin && await userDao.adminCount(exceptNik: nik) == 0) {
      throw AdminRuleException(
        'Admin terakhir tidak bisa dihapus. Tambahkan admin lain dulu.',
      );
    }

    if (admin != null && admin.isAdmin) {
      try {
        await api.deleteUser(
          adminNik: admin.nik,
          targetNik: nik,
          force: force,
        );
      } on ApiConfirmRequiredException catch (e) {
        // User pernah mencetak tag: server menahan sampai ditegaskan.
        throw AdminRuleException('$e');
      } on ApiException catch (e) {
        throw AdminRuleException('Gagal di server: $e');
      }
    }

    await userDao.delete(nik);
  }

  // ----------------------------------------------------------------- event
  Future<List<StoEvent>> events() => eventDao.all();

  /// Daftar event dari server, lalu disalin ke cache lokal.
  ///
  /// Cache tetap dipakai halaman Siapkan Tag untuk memeriksa event berjalan
  /// saat jaringan mati, jadi hasilnya sengaja ditulis ke database - bukan
  /// hanya ditampilkan.
  ///
  /// Terbuka untuk operator, bukan hanya admin: tag hanya boleh dibuat saat
  /// ada event berjalan, jadi justru operator yang paling butuh daftar ini.
  /// Yang tetap milik admin adalah perubahannya (buat/ubah/hapus event).
  Future<List<StoEvent>> syncEvents(AppUser pengakses) async {
    peringatanSinkron = null;

    try {
      final rows = await api.fetchEvents(pengakses.nik);
      final dariServer = rows.map(StoEvent.fromServer).toList();
      await _tulisCacheEvent(dariServer);
      return dariServer;
    } on ApiException catch (e) {
      // Tidak ada salinan lokal yang dipakai sebagai pengganti: daftar event
      // milik server, dan menampilkan daftar lama tanpa sadar justru membuat
      // tag dibuat pada periode yang sudah ditutup.
      peringatanSinkron = 'Daftar event tidak bisa dibaca - server: $e';
      return const [];
    }
  }

  /// Menyamakan cache event perangkat dengan daftar server.
  ///
  /// [activeEvent] - yang menentukan boleh/tidaknya tag dibuat - membaca
  /// tabel ini, bukan balasan server. Selama sinkronisasi tidak menuliskannya,
  /// event yang dibuka admin dari perangkat lain tidak pernah terlihat di sini
  /// dan halaman Siapkan Tag selalu berkata tidak ada event berjalan.
  Future<void> _tulisCacheEvent(List<StoEvent> dariServer) async {
    final adaDiServer = dariServer.map((e) => e.id).toSet();
    for (final lama in await eventDao.all()) {
      if (!adaDiServer.contains(lama.id)) {
        await eventDao.delete(lama.id);
      }
    }
    for (final event in dariServer) {
      await eventDao.save(event);
    }
  }

  Future<StoEvent?> activeEvent([DateTime? date]) =>
      eventDao.activeOn(date ?? DateTime.now());

  Future<void> saveEvent(
    StoEvent event, {
    AppUser? admin,
    bool force = false,
  }) async {
    if (event.name.trim().isEmpty) {
      throw AdminRuleException('Nama event wajib diisi.');
    }
    if (event.endDate.isBefore(event.startDate)) {
      throw AdminRuleException(
        'Tanggal selesai tidak boleh mendahului tanggal mulai.',
      );
    }

    var tersimpan = event;
    if (admin != null && admin.isAdmin) {
      try {
        // API membolehkan lebih dari satu event berjalan dan hanya memberi
        // `warnings`; aturan "hanya satu yang berjalan" ditegakkan di sini.
        // Konsekuensinya nyata: print-tag menolak (409) selama ada lebih
        // dari satu event aktif.
        final lain = event.isOpen
            ? await _eventLainYangBerjalan(admin, kecuali: event.id)
            : const <StoEvent>[];

        if (lain.isNotEmpty && !force) {
          throw ApiConfirmRequiredException(
            'Masih ada event berjalan: '
            '${lain.map((e) => '#${e.id} ${e.name}').join('; ')}. '
            'Tutup dan jadikan "${event.name}" yang berjalan?',
          );
        }

        final idServer = int.tryParse(event.id);
        if (idServer == null) {
          final hasil = await api.createEvent(
            adminNik: admin.nik,
            name: event.name,
            start: event.startDate,
            end: event.endDate,
            berjalan: event.isOpen,
          );
          tersimpan = StoEvent.fromServer(hasil);
        } else {
          await api.updateEvent(
            adminNik: admin.nik,
            eventId: idServer,
            name: event.name,
            start: event.startDate,
            end: event.endDate,
            berjalan: event.isOpen,
          );
        }

        // Baru ditutup setelah event ini benar-benar tersimpan, supaya tidak
        // ada periode tanpa event berjalan sama sekali kalau simpannya gagal.
        for (final e in lain) {
          final id = int.tryParse(e.id);
          if (id == null) continue;
          await api.updateEvent(
            adminNik: admin.nik,
            eventId: id,
            berjalan: false,
          );
        }
      } on ApiConfirmRequiredException {
        rethrow; // layar yang meminta penegasan ke admin
      } on ApiException catch (e) {
        throw AdminRuleException('Gagal di server: $e');
      }
    }

    // Hanya satu event yang boleh berjalan - cache lokal ikut disamakan,
    // supaya pemeriksaan "event berjalan" saat offline tidak menemukan dua.
    if (tersimpan.isOpen) {
      for (final lain in await eventDao.all()) {
        if (lain.id != tersimpan.id && lain.isOpen) {
          await eventDao.save(lain.copyWith(status: StoEventStatus.closed));
        }
      }
    }

    await eventDao.save(tersimpan);
  }

  /// Event lain yang statusnya masih berjalan menurut server.
  Future<List<StoEvent>> _eventLainYangBerjalan(
    AppUser admin, {
    required String kecuali,
  }) async {
    final rows = await api.fetchEvents(admin.nik);
    return rows
        .map(StoEvent.fromServer)
        .where((e) => e.isOpen && e.id != kecuali)
        .toList();
  }

  Future<void> deleteEvent(String id, {AppUser? admin}) async {
    final terpakai = await eventDao.tagCount(id);
    if (terpakai > 0) {
      throw AdminRuleException(
        'Event ini sudah dipakai $terpakai tag di perangkat ini. Tutup saja '
        'eventnya, jangan dihapus, supaya jejak cetak tetap utuh.',
      );
    }

    final idServer = int.tryParse(id);
    if (idServer != null && admin != null && admin.isAdmin) {
      try {
        await api.deleteEvent(adminNik: admin.nik, eventId: idServer);
      } on ApiConfirmRequiredException catch (e) {
        // Server masih melihat tag yang menempel walau perangkat ini tidak.
        throw AdminRuleException('$e');
      } on ApiException catch (e) {
        throw AdminRuleException('Gagal di server: $e');
      }
    }

    await eventDao.delete(id);
  }

  /// Dulu membuat periode contoh untuk mode simulasi. Event sekarang datang
  /// dari server; periode contoh justru ikut terbaca sebagai event berjalan
  /// kedua - jadi tinggal titik masuk kosong bagi pemanggil lama.
  Future<void> ensureSeedEvent(String createdBy) async {}

  /// Pilihan area untuk form izin user & cakupan event.
  /// Pilihan area untuk izin user & cakupan event.
  ///
  /// Lima area STO ditaruh di depan sesuai urutan tetapnya; area lain yang
  /// sudah terlanjur tersimpan pada data user ikut ditampilkan di belakang
  /// supaya tidak hilang diam-diam saat admin menyimpan ulang.
  Future<List<String>> availableAreas() async {
    final dariUser = (await userDao.all()).expand((u) => u.areas);

    final tambahan = <String>{...dariUser}
      ..removeWhere(AppConfig.areaSto.contains);

    final lain = tambahan.toList()..sort();
    return [...AppConfig.areaSto, ...lain];
  }

}
