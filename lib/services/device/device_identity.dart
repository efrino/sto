import 'package:flutter/services.dart';

import '../../data/local/prefs_store.dart';

/// Identitas perangkat yang dipakai untuk pemasangan (pairing) NIK.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.model,
    required this.deviceName,
    required this.androidVersion,
  });

  /// ANDROID_ID - kunci teknis pemasangan.
  final String deviceId;

  /// Merek + model, mis. "SENRAISE H10".
  final String model;

  /// Nama perangkat menurut sistem (bukan nomor aset perusahaan).
  final String deviceName;

  final String androidVersion;

  String get shortId =>
      deviceId.length <= 8 ? deviceId : deviceId.substring(0, 8);
}

/// Pembaca identitas perangkat.
///
/// MAC address sengaja tidak dipakai: sejak Android 6 (Wi-Fi/Bluetooth) dan
/// Android 10 (nomor seri), aplikasi biasa selalu menerima 02:00:00:00:00:00.
/// ANDROID_ID adalah pengganti yang stabil dan bisa dibaca tanpa izin khusus.
class DeviceIdentityService {
  DeviceIdentityService(this._prefs);

  static const MethodChannel _channel = MethodChannel('sto_prep/device');

  final PrefsStore _prefs;
  DeviceIdentity? _cache;

  DeviceIdentity? get cached => _cache;

  Future<DeviceIdentity> load() async {
    if (_cache != null) return _cache!;

    String deviceId = '';
    String model = '-';
    String deviceName = '-';
    String android = '-';

    try {
      final hasil = await _channel.invokeMapMethod<String, String>(
        'getIdentity',
      );
      deviceId = hasil?['device_id'] ?? '';
      model = hasil?['model'] ?? '-';
      deviceName = hasil?['device_name'] ?? '-';
      android = hasil?['android'] ?? '-';
    } catch (_) {
      // Emulator/desktop/test: kanal native tidak tersedia.
    }

    // Cadangan bila ANDROID_ID kosong (jarang, mis. profil kerja tertentu):
    // pakai id buatan aplikasi yang disimpan di perangkat.
    if (deviceId.trim().isEmpty) {
      deviceId = await _prefs.localDeviceId();
    }

    _cache = DeviceIdentity(
      deviceId: deviceId,
      model: model,
      deviceName: deviceName,
      androidVersion: android,
    );
    return _cache!;
  }
}
