import 'package:flutter/services.dart';

/// Menyalakan Bluetooth perangkat, atau mengantar ke setelannya.
class BluetoothSettings {
  const BluetoothSettings._();

  static const MethodChannel _channel = MethodChannel('sto_prep/device');

  /// Meminta sistem menyalakan Bluetooth lewat dialognya sendiri.
  ///
  /// Aplikasi biasa tidak boleh menyalakan radionya langsung sejak Android 13,
  /// tapi masih boleh MEMINTA - dan operator cukup menekan "Izinkan" tanpa
  /// keluar dari aplikasi. Hanya kalau permintaan itu pun tidak bisa
  /// dimunculkan, ia diantar ke halaman setelan.
  ///
  /// false berarti dialognya gagal muncul, bukan berarti operator menolak:
  /// keadaan radionya tetap harus diperiksa ulang setelah ini.
  static Future<bool> nyalakan() async {
    try {
      return await _channel.invokeMethod<bool>('nyalakanBluetooth') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> buka() async {
    try {
      return await _channel.invokeMethod<bool>('openBluetoothSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
