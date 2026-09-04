import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/prefs_store.dart';
import '../data/remote/api_gateway.dart';
import '../data/models/app_user.dart';
import '../data/repositories/demo_seeder.dart';
import '../data/repositories/part_repository.dart';
import '../services/feedback/sound_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    required PrefsStore prefs,
    required ApiGateway api,
    required PartRepository partRepository,
    required AppDatabase database,
    required SoundService sound,
    required DemoSeeder demoSeeder,
  })  : _prefs = prefs,
        _api = api,
        _partRepo = partRepository,
        _db = database,
        _sound = sound,
        _demoSeeder = demoSeeder;

  final PrefsStore _prefs;
  final ApiGateway _api;
  final PartRepository _partRepo;
  final AppDatabase _db;
  final SoundService _sound;
  final DemoSeeder _demoSeeder;

  String _baseUrl = '';
  bool _useMock = false;
  String _defaultArea = '';
  bool _soundEnabled = true;
  bool _printerSimulation = false;
  PartCacheInfo _cacheInfo = const PartCacheInfo(count: 0);
  DateTime? _lastSyncAt;
  bool _busy = false;
  String? _message;

  String get baseUrl => _baseUrl;
  bool get useMock => _useMock;
  String get defaultArea => _defaultArea;
  bool get soundEnabled => _soundEnabled;
  bool get printerSimulation => _printerSimulation;
  PartCacheInfo get cacheInfo => _cacheInfo;
  DateTime? get lastSyncAt => _lastSyncAt;
  bool get busy => _busy;
  String? get message => _message;

  Future<void> bootstrap() async {
    _baseUrl = await _prefs.baseUrl();
    _useMock = await _prefs.useMockApi();
    _defaultArea = await _prefs.defaultArea();
    _soundEnabled = await _prefs.soundEnabled();
    _printerSimulation = await _prefs.printerSimulation();
    _lastSyncAt = await _prefs.lastSyncAt();
    _cacheInfo = await _partRepo.cacheInfo();
    _api.setUseMock(_useMock);
    _sound.enabled = _soundEnabled;
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    _baseUrl = value.trim();
    await _prefs.setBaseUrl(_baseUrl);
    notifyListeners();
  }

  Future<void> setUseMock(bool value) async {
    _useMock = value;
    await _prefs.setUseMockApi(value);
    _api.setUseMock(value);
    notifyListeners();
  }

  Future<void> setDefaultArea(String value) async {
    _defaultArea = value.trim();
    await _prefs.setDefaultArea(_defaultArea);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    _sound.enabled = value;
    await _prefs.setSoundEnabled(value);
    notifyListeners();
  }

  Future<void> setPrinterSimulation(bool value) async {
    _printerSimulation = value;
    await _prefs.setPrinterSimulation(value);
    notifyListeners();
  }

  Future<void> refreshMasterCache() async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final count = await _partRepo.refreshCache(force: true);
      _cacheInfo = await _partRepo.cacheInfo();
      _lastSyncAt = await _prefs.lastSyncAt();
      _message = 'Master part diperbarui ($count data).';
    } catch (e) {
      _message = 'Gagal memperbarui master part: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Mengisi riwayat tag contoh (sudah cetak / draft / dibatalkan / belum
  /// sinkron) supaya alur bisa diuji sebelum API tersedia.
  Future<void> seedDemoData(AppUser user) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final count = await _demoSeeder.seed(user);
      _cacheInfo = await _partRepo.cacheInfo();
      _message = count > 0
          ? 'Data contoh dibuat: $count tag (awalan DEMO).'
          : 'Master part kosong - perbarui dulu, lalu coba lagi.';
    } catch (e) {
      _message = 'Gagal membuat data contoh: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> clearPartCache() async {
    await _db.clearPartCache();
    _cacheInfo = await _partRepo.cacheInfo();
    _message = 'Cache master part dihapus.';
    notifyListeners();
  }

  /// Hapus SEMUA data lokal termasuk riwayat tag.
  /// Dipakai hanya saat perangkat dipindah/di-reset - konfirmasi ganda di UI.
  Future<void> wipeLocalData() async {
    await _db.wipe();
    _cacheInfo = await _partRepo.cacheInfo();
    _message = 'Seluruh data lokal dihapus.';
    notifyListeners();
  }

  void clearMessage() => _message = null;
}
