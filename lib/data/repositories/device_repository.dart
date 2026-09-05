import '../../services/device/device_identity.dart';
import '../local/device_dao.dart';
import '../models/app_user.dart';
import '../models/sto_device.dart';
import '../remote/api_client.dart';
import '../remote/api_gateway.dart';
import '../remote/sto_api.dart';

class DeviceRuleException implements Exception {
  DeviceRuleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Pemasangan (pairing) NIK ke perangkat.
///
/// Aturan:
/// - operator hanya bisa login di perangkat yang NIK-nya sudah dipasangkan
///   admin, dan perangkat itu berstatus aktif;
/// - admin bebas login di perangkat mana pun (supaya bisa mendaftarkan
///   perangkat baru dan melepas pemasangan saat event selesai);
/// - satu perangkat boleh memuat beberapa NIK, mis. shift pagi & malam.
class DeviceRepository {
  DeviceRepository({
    required this.dao,
    required this.identityService,
    required this.api,
  });

  final DeviceDao dao;
  final DeviceIdentityService identityService;
  final ApiGateway api;

  /// Diisi bila pengambilan terakhir terpaksa memakai cache perangkat.
  String? peringatanSinkron;

  Future<DeviceIdentity> identity() => identityService.load();

  /// Baris perangkat ini; dibuat otomatis bila belum ada supaya admin tinggal
  /// mengisi nomor asetnya.
  Future<StoDevice> ensureRegistered({String registeredBy = 'SYSTEM'}) async {
    final id = await identity();
    final ada = await dao.findById(id.deviceId);
    if (ada != null) {
      if (ada.model != id.model) {
        await dao.save(ada.copyWith(model: id.model));
        return ada.copyWith(model: id.model);
      }
      return ada;
    }

    final baru = StoDevice(
      deviceId: id.deviceId,
      model: id.model,
      registeredAt: DateTime.now(),
      registeredBy: registeredBy,
    );
    await dao.save(baru);
    return baru;
  }

  Future<StoDevice?> current() async {
    final id = await identity();
    return dao.findById(id.deviceId);
  }

  /// Menyimpan keputusan server setelah login berhasil.
  ///
  /// Sejak pemasangan dipegang server (`login` menolak sendiri NIK yang bukan
  /// milik perangkat ini), baris lokal tinggal cache: isinya dipakai halaman
  /// Perangkat dan saat jaringan mati, bukan untuk memutuskan boleh/tidaknya
  /// login.
  Future<void> rekamLoginServer(AppUser user) async {
    final identitas = await identity();
    final device = await ensureRegistered(registeredBy: user.nik);
    final info = api.perangkatTerpasang;

    // Nama & id server hanya disalin bila perangkat yang dimaksud server
    // memang perangkat ini. Admin boleh login di HT mana pun, dan perangkat
    // yang terpasang padanya bisa HT lain - tanpa penjagaan ini nomor aset
    // perangkat ini akan tertimpa nomor aset milik HT tersebut.
    final sama = '${info?['android_id'] ?? ''}' == identitas.deviceId;
    final nama = sama ? '${info?['device_name'] ?? ''}'.trim() : '';
    final serverId = sama ? (info?['device_id'] as int?) : null;

    final niks = [
      ...device.niks.where((n) => n.toUpperCase() != user.nik.toUpperCase()),
      if (sama) user.nik.toUpperCase(),
    ];

    await dao.save(
      device.copyWith(
        assetName: nama.isEmpty ? null : nama,
        serverId: serverId,
        niks: niks,
        lastSeenAt: DateTime.now(),
      ),
    );
  }

  /// Penjaga login untuk mode simulasi/offline. Melempar [DeviceRuleException]
  /// dengan pesan yang bisa dibaca operator bila perangkatnya belum
  /// dipasangkan.
  ///
  /// TIDAK dipakai saat API aktif: di sana server yang memutuskan, dan catatan
  /// lokal yang tertinggal (mis. aplikasi baru dipasang ulang) tidak boleh
  /// menolak NIK yang sudah dipasangkan admin di server.
  Future<StoDevice> assertCanLogin(AppUser user) async {
    final device = await ensureRegistered(registeredBy: user.nik);

    if (user.isAdmin) {
      await dao.touch(device.deviceId, DateTime.now());
      return device;
    }

    if (!device.active) {
      throw DeviceRuleException(
        'Perangkat ${device.label} dinonaktifkan admin.',
      );
    }
    if (!device.terdaftar) {
      throw DeviceRuleException(
        'Perangkat ini belum diberi nomor aset dan belum dipasangkan. '
        'Minta admin mendaftarkannya lewat Setting > Perangkat.',
      );
    }
    if (!device.allows(user.nik)) {
      throw DeviceRuleException(
        'NIK ${user.nik} tidak dipasangkan pada perangkat ${device.label}. '
        'Minta admin memasangkannya lebih dulu.',
      );
    }

    await dao.touch(device.deviceId, DateTime.now());
    return device;
  }

  // ------------------------------------------------------------ pengelolaan
  Future<List<StoDevice>> list() => dao.all();

  /// Menarik daftar perangkat dari server lalu menuliskannya ke cache lokal.
  ///
  /// Server adalah sumber kebenaran untuk nama & ANDROID_ID; daftar NIK
  /// ([StoDevice.niks]) tetap catatan lokal karena belum ada endpoint yang
  /// mengembalikan siapa saja yang terpasang pada satu perangkat.
  ///
  /// Bila jaringan/endpoint bermasalah, isinya tidak dikosongkan - daftar
  /// terakhir tetap dipakai dan [peringatanSinkron] diisi supaya layar bisa
  /// mengatakan apa adanya bahwa yang tampil adalah data cache.
  Future<List<StoDevice>> sync(AppUser admin) async {
    peringatanSinkron = null;
    if (!admin.isAdmin) return dao.all();

    try {
      final rows = await api.fetchDevices(admin.nik);
      final ini = await identity();

      // Daftarnya milik server, ditampilkan apa adanya. Yang disimpan lokal
      // hanya baris perangkat INI - identitasnya harus tetap dikenali saat
      // jaringan mati, karena login memeriksa pemasangan lewat ANDROID_ID.
      final daftar = <StoDevice>[];
      for (final row in rows) {
        final androidId = '${row['android_id'] ?? ''}'.trim();
        if (androidId.isEmpty) continue;

        final perangkat = StoDevice(
          deviceId: androidId,
          assetName: '${row['name'] ?? ''}'.trim(),
          registeredAt: DateTime.now(),
          registeredBy: admin.nik,
          serverId: (row['id'] as num?)?.toInt(),
          totalUserServer: (row['total_user'] as num?)?.toInt() ?? 0,
        );
        daftar.add(perangkat);

        if (androidId == ini.deviceId) {
          final ada = await dao.findById(androidId);
          await dao.save(
            ada == null
                ? perangkat.copyWith(model: ini.model)
                : ada.copyWith(
                    assetName: perangkat.assetName.isEmpty
                        ? ada.assetName
                        : perangkat.assetName,
                    serverId: perangkat.serverId,
                    totalUserServer: perangkat.totalUserServer,
                  ),
          );
        }
      }

      return daftar;
    } on ApiException catch (e) {
      // Tanpa jaringan, daftar perangkat memang tidak bisa dipastikan -
      // menampilkan salinan lama justru membuat admin memutuskan pemasangan
      // berdasarkan keadaan yang mungkin sudah berubah.
      peringatanSinkron = 'Daftar perangkat tidak bisa dibaca - server: $e';
      return const [];
    }
  }

  Future<void> saveAssetName(
    StoDevice device,
    String assetName, {
    AppUser? admin,
  }) async {
    final nama = assetName.trim().toUpperCase();
    if (nama.isEmpty) {
      throw DeviceRuleException('Nomor aset wajib diisi, mis. 016-HSS-TBN.');
    }
    final semua = await dao.all();
    final bentrok = semua.any(
      (d) => d.deviceId != device.deviceId && d.assetName.toUpperCase() == nama,
    );
    if (bentrok) {
      throw DeviceRuleException('Nomor aset $nama sudah dipakai perangkat lain.');
    }

    // Nomor aset adalah `name` di server. Perangkat yang belum pernah
    // didaftarkan dibuat sekalian, supaya admin tidak perlu dua langkah.
    var tersimpan = device.copyWith(assetName: nama);
    if (admin != null && admin.isAdmin) {
      try {
        if (device.serverId == null) {
          final hasil = await api.createDevice(
            adminNik: admin.nik,
            name: nama,
            androidId: device.deviceId,
          );
          tersimpan = tersimpan.copyWith(
            serverId: (hasil['id'] as num?)?.toInt(),
          );
        } else {
          await api.updateDevice(
            adminNik: admin.nik,
            deviceId: device.serverId!,
            name: nama,
          );
        }
      } on ApiException catch (e) {
        throw DeviceRuleException('Gagal di server: $e');
      }
    }

    await dao.save(tersimpan);
  }

  /// Memasangkan NIK ke perangkat ini - di server sekaligus di catatan lokal.
  ///
  /// Server menyimpannya sebagai `users.device_id`, jadi satu NIK hanya bisa
  /// menempel pada satu perangkat; memasangnya di sini otomatis melepasnya
  /// dari perangkat sebelumnya.
  Future<void> pair(StoDevice device, String nik, {AppUser? admin}) async {
    final target = nik.trim().toUpperCase();
    if (target.isEmpty) throw DeviceRuleException('NIK wajib diisi.');

    final serverId = device.serverId;
    if (admin != null && admin.isAdmin && serverId != null) {
      try {
        await api.updateUser(
          adminNik: admin.nik,
          targetNik: target,
          deviceId: serverId,
        );
      } on ApiException catch (e) {
        throw DeviceRuleException('Gagal di server: $e');
      }
    } else if (serverId == null) {
      throw DeviceRuleException(
        'Perangkat ini belum terdaftar di server. Isi nomor asetnya dulu '
        'supaya bisa didaftarkan, baru pasangkan NIK.',
      );
    }

    if (device.allows(target)) return;
    await dao.save(device.copyWith(niks: [...device.niks, target]));
  }

  Future<void> unpair(StoDevice device, String nik, {AppUser? admin}) async {
    final target = nik.trim().toUpperCase();

    // Pemasangan disimpan di `users.device_id`, dan melepasnya dilakukan
    // lewat user-update dengan device_id kosong - tidak ada endpoint khusus
    // untuk itu.
    if (admin != null && admin.isAdmin && device.serverId != null) {
      try {
        await api.updateUser(
          adminNik: admin.nik,
          targetNik: target,
          deviceId: 0, // 0 = lepaskan
        );
      } on ApiException catch (e) {
        throw DeviceRuleException('Gagal di server: $e');
      }
    }

    await dao.save(
      device.copyWith(
        niks: device.niks
            .where((n) => n.trim().toUpperCase() != target)
            .toList(),
      ),
    );
  }

  /// Dipakai saat event selesai: seluruh NIK dilepas dari perangkat ini,
  /// di server maupun di catatan perangkat.
  Future<void> unpairAll(StoDevice device, {AppUser? admin}) async {
    final serverId = device.serverId;

    // Tidak ada endpoint "lepas semua"; yang dilepas adalah NIK yang menurut
    // SERVER terpasang pada perangkat ini, satu per satu. Catatan lokal
    // `device.niks` tidak dipakai sebagai daftar kerja - isinya hanya NIK yang
    // kebetulan pernah dipasangkan dari perangkat ini, sehingga pemasangan
    // yang dibuat admin dari HT lain akan tertinggal terpasang.
    if (admin != null && admin.isAdmin && serverId != null) {
      final List<String> daftar;
      try {
        final dariServer = await api.fetchUsers(admin.nik, deviceId: serverId);
        daftar = dariServer.map((u) => u.nik).toList();
      } on ApiException catch (e) {
        throw DeviceRuleException('Daftar NIK perangkat tidak terbaca: $e');
      }

      for (final nik in daftar) {
        try {
          await api.updateUser(
            adminNik: admin.nik,
            targetNik: nik.trim().toUpperCase(),
            deviceId: 0,
          );
        } on ApiException catch (e) {
          throw DeviceRuleException('Gagal melepas $nik di server: $e');
        }
      }
    }

    await dao.save(device.copyWith(niks: const []));
  }

  Future<void> setActive(StoDevice device, bool active) =>
      dao.save(device.copyWith(active: active));

  /// Menghapus perangkat. Bila sudah terdaftar di server, dihapus juga di
  /// sana - server membalas `confirm` bila masih ada user yang terpasang,
  /// dan itu diteruskan apa adanya supaya admin yang memutuskan.
  Future<void> delete(
    StoDevice device, {
    AppUser? admin,
    bool force = false,
  }) async {
    final serverId = device.serverId;
    if (serverId != null && admin != null && admin.isAdmin) {
      try {
        await api.deleteDevice(
          adminNik: admin.nik,
          deviceId: serverId,
          force: force,
        );
      } on ApiConfirmRequiredException catch (e) {
        throw DeviceRuleException('$e');
      } on ApiException catch (e) {
        throw DeviceRuleException('Gagal di server: $e');
      }
    }
    await dao.delete(device.deviceId);
  }

  /// Akun yang terpasang pada satu perangkat, langsung dari server.
  ///
  /// Daftar ini tidak disimpan lokal: pemasangan bisa diubah admin dari HT
  /// lain, jadi satu-satunya jawaban yang benar adalah jawaban server.
  Future<List<AppUser>> penggunaPerangkat(AppUser admin, int serverId) async {
    if (!admin.isAdmin) return const [];
    return api.fetchUsers(admin.nik, deviceId: serverId);
  }

  /// Mengubah nama (nomor aset) perangkat mana pun yang terdaftar di server.
  Future<void> renameServerDevice(
    AppUser admin,
    int serverId,
    String nama,
  ) async {
    final bersih = nama.trim().toUpperCase();
    if (bersih.isEmpty) {
      throw DeviceRuleException('Nomor aset wajib diisi, mis. 016-HSS-TBN.');
    }
    try {
      await api.updateDevice(
        adminNik: admin.nik,
        deviceId: serverId,
        name: bersih,
      );
    } on ApiException catch (e) {
      throw DeviceRuleException('Gagal di server: $e');
    }

    // Kalau yang diubah kebetulan perangkat ini, catatan lokalnya ikut.
    final lokal = await dao.all();
    for (final d in lokal.where((d) => d.serverId == serverId)) {
      await dao.save(d.copyWith(assetName: bersih));
    }
  }

  /// Menghapus perangkat dari server (dan dari catatan lokal bila ada).
  ///
  /// Server menahan dengan `confirm` selama masih ada user yang memakainya -
  /// itu diteruskan apa adanya supaya admin yang memutuskan.
  Future<void> deleteServerDevice(
    AppUser admin,
    int serverId, {
    bool force = false,
  }) async {
    try {
      await api.deleteDevice(
        adminNik: admin.nik,
        deviceId: serverId,
        force: force,
      );
    } on ApiConfirmRequiredException catch (e) {
      throw DeviceRuleException('$e');
    } on ApiException catch (e) {
      throw DeviceRuleException('Gagal di server: $e');
    }

    for (final d in (await dao.all()).where((d) => d.serverId == serverId)) {
      await dao.delete(d.deviceId);
    }
  }

  /// Menautkan perangkat INI ke baris perangkat yang SUDAH ada di server.
  ///
  /// Dipakai saat ANDROID_ID sebuah handheld berubah padahal perangkatnya
  /// sama - mis. APK ditandatangani kunci lain, atau perangkat di-factory
  /// reset. Tanpa ini admin terpaksa membuat baris baru, lalu memasangkan
  /// ulang seluruh NIK-nya satu per satu dan meninggalkan baris lama yang
  /// tidak akan pernah dipakai.
  ///
  /// Yang diubah hanya `devices.android_id` milik baris itu; `devices.id`
  /// tetap, dan karena pemasangan NIK menunjuk ke id tersebut
  /// (`users.device_id`), seluruh NIK yang sudah terpasang ikut terbawa.
  Future<void> tautkanKePerangkatServer(AppUser admin, int serverId) async {
    if (!admin.isAdmin) {
      throw DeviceRuleException('Hanya admin yang bisa menautkan perangkat.');
    }

    final identitas = await identity();
    if (identitas.deviceId.trim().isEmpty) {
      throw DeviceRuleException('Identitas perangkat ini belum terbaca.');
    }

    final Map<String, dynamic> hasil;
    try {
      hasil = await api.updateDevice(
        adminNik: admin.nik,
        deviceId: serverId,
        androidId: identitas.deviceId,
      );
    } on ApiException catch (e) {
      throw DeviceRuleException('Gagal di server: $e');
    }

    // Baris lokal milik ANDROID_ID lama - kalau ada - dibuang supaya tidak
    // tertinggal sebagai perangkat kedua di layar.
    for (final lama in await dao.all()) {
      if (lama.serverId == serverId && lama.deviceId != identitas.deviceId) {
        await dao.delete(lama.deviceId);
      }
    }

    final ini = await ensureRegistered(registeredBy: admin.nik);
    final nama = '${hasil['name'] ?? ''}'.trim();
    await dao.save(
      ini.copyWith(
        serverId: serverId,
        assetName: nama.isEmpty ? null : nama,
        lastSeenAt: DateTime.now(),
      ),
    );
  }

  /// Perangkat lain yang memakai NIK yang sama - ditampilkan sebagai peringatan.
  Future<List<StoDevice>> otherDevicesWith(String nik, String deviceId) =>
      dao.withNik(nik, exceptDeviceId: deviceId);
}
