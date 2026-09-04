import 'package:flutter/services.dart';

/// Membuka layar setelan Bluetooth perangkat.
///
/// Sejak Android 13 aplikasi tidak boleh lagi menyalakan Bluetooth sendiri,
/// jadi yang bisa dilakukan hanyalah mengantar operator ke setelannya.
class BluetoothSettings {
  const BluetoothSettings._();

  static const MethodChannel _channel = MethodChannel('sto_prep/device');

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
