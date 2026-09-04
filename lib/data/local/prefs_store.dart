import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../models/app_user.dart';

/// Cache ringan (SharedPreferences): sesi login, setting perangkat,
/// riwayat pencarian, dan counter nomor urut offline.
class PrefsStore {
  PrefsStore._();

  static final PrefsStore instance = PrefsStore._();

  static const _kUser = 'active_user';
  static const _kRecentSearch = 'recent_search';
  static const _kBaseUrl = 'base_url';
  static const _kUseMock = 'use_mock_api';
  static const _kPrinterAddress = 'printer_address';
  static const _kPrinterName = 'printer_name';
  static const _kPaperSize = 'paper_size';
  static const _kDefaultArea = 'default_area';
  static const _kAutoConnectPrinter = 'auto_connect_printer';
  static const _kPrinterSimulation = 'printer_simulation';
  static const _kSoundEnabled = 'sound_enabled';
  static const _kLocalSeqPrefix = 'local_seq_';
  static const _kLastSync = 'last_sync_at';
  static const _kLocalDeviceId = 'local_device_id';
  static const _kPaperFeedDots = 'paper_feed_dots';
  static const _kTagGapDots = 'tag_gap_dots';
  static const _kFeedMigrasi = 'paper_feed_migrasi_v2';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Membuang instance `SharedPreferences` yang tersimpan.
  ///
  /// [PrefsStore.instance] adalah singleton proses, sehingga nilainya tetap
  /// dari objek `SharedPreferences` pertama yang diambil - `getInstance()`
  /// berikutnya (mis. `setMockInitialValues` di test lain) tidak pernah
  /// terlihat tanpa ini. Hanya untuk test.
  @visibleForTesting
  void resetForTests() => _prefs = null;

  // ---------------------------------------------------------------- sesi
  Future<AppUser?> readUser() async {
    final raw = (await _p).getString(_kUser);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(AppUser user) async =>
      (await _p).setString(_kUser, jsonEncode(user.toJson()));

  Future<void> clearUser() async => (await _p).remove(_kUser);

  /// Menghapus jejak NIK lama bila pernah tersimpan di versi sebelumnya.
  Future<void> wipeLegacyNikHistory() async => (await _p).remove('nik_history');

  // ------------------------------------------------------ riwayat pencarian
  Future<List<String>> recentSearch() async =>
      (await _p).getStringList(_kRecentSearch) ?? const [];

  Future<void> pushRecentSearch(String keyword) async {
    final key = keyword.trim();
    if (key.isEmpty) return;
    final prefs = await _p;
    final list = prefs.getStringList(_kRecentSearch) ?? [];
    list.removeWhere((e) => e.toLowerCase() == key.toLowerCase());
    list.insert(0, key);
    await prefs.setStringList(
      _kRecentSearch,
      list.length > 8 ? list.sublist(0, 8) : list,
    );
  }

  Future<void> clearRecentSearch() async => (await _p).remove(_kRecentSearch);

  // ------------------------------------------------------------- setting
  Future<String> baseUrl() async =>
      (await _p).getString(_kBaseUrl) ?? AppConfig.defaultBaseUrl;

  Future<void> setBaseUrl(String value) async =>
      (await _p).setString(_kBaseUrl, value.trim());

  Future<bool> useMockApi() async =>
      (await _p).getBool(_kUseMock) ?? AppConfig.useMockApi;

  Future<void> setUseMockApi(bool value) async =>
      (await _p).setBool(_kUseMock, value);

  Future<String?> printerAddress() async => (await _p).getString(_kPrinterAddress);

  Future<String?> printerName() async => (await _p).getString(_kPrinterName);

  Future<void> setPrinter(String address, String name) async {
    final prefs = await _p;
    await prefs.setString(_kPrinterAddress, address);
    await prefs.setString(_kPrinterName, name);
  }

  Future<void> clearPrinter() async {
    final prefs = await _p;
    await prefs.remove(_kPrinterAddress);
    await prefs.remove(_kPrinterName);
  }

  Future<PaperSize> paperSize() async =>
      PaperSize.fromName((await _p).getString(_kPaperSize));

  Future<void> setPaperSize(PaperSize size) async =>
      (await _p).setString(_kPaperSize, size.name);

  Future<String> defaultArea() async =>
      (await _p).getString(_kDefaultArea) ?? '';

  Future<void> setDefaultArea(String value) async =>
      (await _p).setString(_kDefaultArea, value.trim());

  Future<bool> autoConnectPrinter() async =>
      (await _p).getBool(_kAutoConnectPrinter) ?? true;

  Future<void> setAutoConnectPrinter(bool value) async =>
      (await _p).setBool(_kAutoConnectPrinter, value);

  /// Jarak maju kertas setelah tag selesai (titik ESC/POS), diatur operator
  /// dari Setting > Printer. Null = belum pernah diatur, pemanggil memakai
  /// nilai bawaan [feedAfterTagDots].
  ///
  /// Disimpan per perangkat sengaja - kalibrasi dot-ke-mm printer klon
  /// seperti ini ternyata tidak seragam, jadi tebakan bawaan bisa jauh
  /// meleset dan operator sendiri yang paling tahu berapa yang pas di
  /// printernya.
  Future<int?> paperFeedDots() async => (await _p).getInt(_kPaperFeedDots);

  Future<void> setPaperFeedDots(int dots) async =>
      (await _p).setInt(_kPaperFeedDots, dots);

  /// Jarak antar tag dalam satu batch (titik ESC/POS). Null = belum diatur,
  /// pemanggil memakai [gapAntarTagDots].
  Future<int?> tagGapDots() async => (await _p).getInt(_kTagGapDots);

  Future<void> setTagGapDots(int dots) async =>
      (await _p).setInt(_kTagGapDots, dots);

  /// Membuang setelan "jarak akhir" peninggalan percobaan lama.
  ///
  /// Dulu angka itu berarti "maju sekian titik lewat ESC J" - perintah yang
  /// ternyata diabaikan printer. Sekarang artinya "baris kosong TAMBAHAN di
  /// atas jarak yang sudah dibuat printer sendiri", dan bawaannya 0. Nilai
  /// lama yang tersimpan akan menahan bawaan itu tanpa disadari operator,
  /// jadi dibersihkan sekali.
  Future<void> bersihkanSetelanJarakLama() async {
    final p = await _p;
    if (p.getBool(_kFeedMigrasi) ?? false) return;
    await p.remove(_kPaperFeedDots);
    await p.setBool(_kFeedMigrasi, true);
  }


  /// Mode simulasi printer (untuk emulator / HP biasa tanpa printer internal).
  Future<bool> printerSimulation({bool fallback = false}) async =>
      (await _p).getBool(_kPrinterSimulation) ?? fallback;

  Future<void> setPrinterSimulation(bool value) async =>
      (await _p).setBool(_kPrinterSimulation, value);

  Future<bool> soundEnabled() async => (await _p).getBool(_kSoundEnabled) ?? true;

  Future<void> setSoundEnabled(bool value) async =>
      (await _p).setBool(_kSoundEnabled, value);

  Future<DateTime?> lastSyncAt() async {
    final raw = (await _p).getString(_kLastSync);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncAt(DateTime value) async =>
      (await _p).setString(_kLastSync, value.toIso8601String());

  /// Id perangkat cadangan bila ANDROID_ID tidak terbaca. Dibuat sekali lalu
  /// disimpan, sehingga tetap sama selama data aplikasi tidak dihapus.
  Future<String> localDeviceId() async {
    final prefs = await _p;
    final tersimpan = prefs.getString(_kLocalDeviceId);
    if (tersimpan != null && tersimpan.isNotEmpty) return tersimpan;

    final baru = 'LOCAL-'
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    await prefs.setString(_kLocalDeviceId, baru);
    return baru;
  }

  // --------------------------------------------- counter sequence offline
  Future<int> localSequence(String prefix) async =>
      (await _p).getInt('$_kLocalSeqPrefix$prefix') ?? 0;

  Future<void> setLocalSequence(String prefix, int value) async =>
      (await _p).setInt('$_kLocalSeqPrefix$prefix', value);
}
