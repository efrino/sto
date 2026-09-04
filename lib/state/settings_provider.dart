import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/prefs_store.dart';
import '../data/repositories/part_repository.dart';
import '../services/feedback/sound_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    required PrefsStore prefs,
    required PartRepository partRepository,
    required AppDatabase database,
    required SoundService sound,
  })  : _prefs = prefs,
        _partRepo = partRepository,
        _db = database,
        _sound = sound;

  final PrefsStore _prefs;
  final PartRepository _partRepo;
  final AppDatabase _db;
  final SoundService _sound;

  String _baseUrl = '';
  String _defaultArea = '';
  bool _soundEnabled = true;
  bool _printerSimulation = false;
  PartCacheInfo _cacheInfo = const PartCacheInfo(count: 0);
  DateTime? _lastSyncAt;
  bool _busy = false;
  String? _message;

  String get baseUrl => _baseUrl;
  String get defaultArea => _defaultArea;
  bool get soundEnabled => _soundEnabled;
  bool get printerSimulation => _printerSimulation;
  PartCacheInfo get cacheInfo => _cacheInfo;
  DateTime? get lastSyncAt => _lastSyncAt;
  bool get busy => _busy;
  String? get message => _message;

  Future<void> bootstrap() async {
    _baseUrl = await _prefs.baseUrl();
    _defaultArea = await _prefs.defaultArea();
    _soundEnabled = await _prefs.soundEnabled();
    _printerSimulation = await _prefs.printerSimulation();
    _lastSyncAt = await _prefs.lastSyncAt();
    _cacheInfo = await _partRepo.cacheInfo();
    _sound.enabled = _soundEnabled;
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    _baseUrl = value.trim();
    await _prefs.setBaseUrl(_baseUrl);
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
