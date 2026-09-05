import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/sto_device.dart';
import '../data/repositories/device_repository.dart';
import '../services/device/device_identity.dart';

/// Pengelolaan perangkat & pemasangan NIK (khusus admin).
class DeviceProvider extends ChangeNotifier {
  DeviceProvider(this._repo);

  final DeviceRepository _repo;

  DeviceIdentity? _identity;
  StoDevice? _current;
  List<StoDevice> _devices = const [];
  bool _loading = false;
  String? _message;
  AppUser? _admin;

  /// Terisi bila daftar terakhir datang dari cache, bukan server.
  String? get peringatanSinkron => _repo.peringatanSinkron;

  DeviceIdentity? get identity => _identity;
  StoDevice? get current => _current;
  List<StoDevice> get devices => _devices;
  bool get loading => _loading;
  String? get message => _message;

  /// [admin] diingat supaya aksi berikutnya (simpan nomor aset, hapus) bisa
  /// ikut menyentuh server tanpa halaman perlu mengirim ulang identitasnya.
  Future<void> load({String registeredBy = 'SYSTEM', AppUser? admin}) async {
    _loading = true;
    _admin = admin ?? _admin;
    notifyListeners();
    try {
      _identity = await _repo.identity();
      _current = await _repo.ensureRegistered(registeredBy: registeredBy);

      final pengakses = _admin;
      _devices = (pengakses != null && pengakses.isAdmin)
          ? await _repo.sync(pengakses)
          : await _repo.list();

      // Baris perangkat ini ikut diperbarui bila server sudah mengenalnya.
      _current = await _repo.current() ?? _current;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> setAssetName(StoDevice device, String assetName) => _jalankan(
        () => _repo.saveAssetName(device, assetName, admin: _admin),
        'Nomor aset disimpan.',
      );

  Future<bool> pair(StoDevice device, String nik) => _jalankan(
        () => _repo.pair(device, nik, admin: _admin),
        'NIK ${nik.trim().toUpperCase()} dipasangkan ke ${device.label}.',
      );

  Future<bool> unpair(StoDevice device, String nik) => _jalankan(
        () => _repo.unpair(device, nik, admin: _admin),
        'NIK ${nik.trim().toUpperCase()} dilepas dari ${device.label}.',
      );

  /// Dipakai saat event selesai.
  Future<bool> unpairAll(StoDevice device) => _jalankan(
        () => _repo.unpairAll(device, admin: _admin),
        'Semua NIK dilepas dari ${device.label}.',
      );

  Future<bool> setActive(StoDevice device, bool active) => _jalankan(
        () => _repo.setActive(device, active),
        active
            ? 'Perangkat ${device.label} diaktifkan.'
            : 'Perangkat ${device.label} dinonaktifkan.',
      );

  /// [force] dipakai saat server membalas `confirm` - perangkat masih
  /// dipakai user, dan admin tetap ingin menghapusnya.
  Future<bool> delete(StoDevice device, {bool force = false}) => _jalankan(
        () => _repo.delete(device, admin: _admin, force: force),
        'Perangkat ${device.label} dihapus dari daftar.',
      );

  /// Akun yang terpasang pada satu perangkat menurut server.
  Future<List<AppUser>> penggunaPerangkat(int serverId) async {
    final admin = _admin;
    if (admin == null) return const [];
    try {
      return await _repo.penggunaPerangkat(admin, serverId);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> renameServerDevice(int serverId, String nama) => _jalankan(
        () => _repo.renameServerDevice(_admin!, serverId, nama),
        'Nomor aset perangkat disimpan.',
      );

  Future<bool> deleteServerDevice(int serverId, {bool force = false}) =>
      _jalankan(
        () => _repo.deleteServerDevice(_admin!, serverId, force: force),
        'Perangkat dihapus dari server.',
      );

  /// Menautkan perangkat ini ke baris perangkat yang sudah terdaftar di
  /// server - dipakai saat ANDROID_ID berubah pada handheld yang sama.
  Future<bool> tautkanKePerangkatServer(int serverId) => _jalankan(
        () => _repo.tautkanKePerangkatServer(_admin!, serverId),
        'Perangkat ini ditautkan ke pendaftaran yang sudah ada.',
      );

  /// Peringatan bila satu NIK terpasang di lebih dari satu perangkat.
  Future<List<StoDevice>> otherDevicesWith(String nik, String deviceId) =>
      _repo.otherDevicesWith(nik, deviceId);

  Future<bool> _jalankan(Future<void> Function() aksi, String sukses) async {
    try {
      await aksi();
      _message = sukses;
      await load();
      return true;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearMessage() => _message = null;
}
