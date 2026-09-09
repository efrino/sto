import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';

import '../data/models/app_user.dart';
import '../data/models/sto_event.dart';
import '../data/remote/sto_api.dart';
import '../data/repositories/admin_repository.dart';

/// Data yang dikelola admin: event STO dan daftar user beserta izin areanya.
///
/// Semua tulisan lewat [AdminRepository] sehingga aturan (mis. admin terakhir
/// tidak boleh dihapus) berlaku sama di mana pun dipanggil.
class AdminProvider extends ChangeNotifier {
  AdminProvider(this._repo);

  final AdminRepository _repo;

  List<StoEvent> _events = const [];
  List<AppUser> _users = const [];
  List<String> _areas = const [];
  StoEvent? _activeEvent;
  bool _loading = false;
  String? _message;
  AppUser? _admin;

  /// Terisi bila daftar event terakhir datang dari cache, bukan server.
  String? get peringatanSinkron => _repo.peringatanSinkron;

  List<StoEvent> get events => _events;
  List<AppUser> get users => _users;
  List<String> get areas => _areas;

  /// Pilihan tim: enum `users.tim` di server (A dan B), bukan daftar yang
  /// dikelola admin.
  List<String> get teamOptions => AppConfig.timSto;
  StoEvent? get activeEvent => _activeEvent;
  bool get loading => _loading;
  String? get message => _message;

  /// Terisi bila server menahan permintaan sampai ditegaskan - dipakai
  /// aturan "hanya satu event berjalan". Layar menampilkannya sebagai
  /// pertanyaan, lalu memanggil ulang dengan force: true.
  String? get pesanPenegasan => _pesanPenegasan;
  String? _pesanPenegasan;

  bool get hasActiveEvent => _activeEvent != null;

  /// Event yang paling perlu diketahui hari ini - untuk kartu di beranda.
  ///
  /// [activeEvent] hanya berisi yang benar-benar berjalan, jadi memakainya
  /// sendirian membuat beranda berkata "belum ada event" pada dua keadaan
  /// yang sangat berbeda: memang belum ada apa-apa, atau eventnya ada tapi
  /// baru mulai lusa. Yang kedua justru perlu diberitahukan.
  ///
  /// Urutan yang dipilih: yang sedang berjalan, lalu yang paling dekat akan
  /// mulai, terakhir yang paling baru saja lewat.
  StoEvent? get eventDisorot {
    if (_activeEvent != null) return _activeEvent;
    if (_events.isEmpty) return null;

    final kini = DateTime.now();

    final akanDatang = _events
        .where((e) => e.isOpen && e.jadwalPada(kini) == JadwalEvent.akanDatang)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (akanDatang.isNotEmpty) return akanDatang.first;

    final lewat = _events
        .where((e) => e.jadwalPada(kini) == JadwalEvent.terlewat)
        .toList()
      ..sort((a, b) => b.endDate.compareTo(a.endDate));
    return lewat.isEmpty ? null : lewat.first;
  }

  Future<void> load({String seedCreatedBy = 'SYSTEM', AppUser? admin}) async {
    _loading = true;
    _admin = admin ?? _admin;
    notifyListeners();
    try {
      final pengakses = _admin;
      // Event ditarik dari server untuk siapa pun yang sudah login - operator
      // yang menyiapkan tag butuh event berjalan, dan server sudah menyaring
      // NIK yang tidak terdaftar.
      _events = pengakses == null
          ? await _repo.events()
          : await _repo.syncEvents(pengakses);

      // Seed lokal hanya dipakai bila server memang belum punya event -
      // kalau tidak, periode contoh akan muncul menyaingi periode asli.
      if (_events.isEmpty) {
        await _repo.ensureSeedEvent(seedCreatedBy);
        _events = await _repo.events();
      }
      _users = (pengakses != null && pengakses.isAdmin)
          ? await _repo.syncUsers(pengakses)
          : await _repo.users();
      _areas = await _repo.availableAreas();
      _activeEvent = await _repo.activeEvent();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Dipanggil sebelum menyiapkan tag - memastikan status event terbaru.
  ///
  /// Ditarik ulang dari server, bukan sekadar membaca cache: event dibuka dan
  /// ditutup admin dari perangkat lain, dan perangkat yang baru dipasang
  /// cache-nya masih kosong. Bila jaringan mati, [syncEvents] sendiri yang
  /// jatuh ke cache dan mengisi [peringatanSinkron].
  Future<StoEvent?> refreshActiveEvent({AppUser? pengakses}) async {
    if (pengakses != null) _admin = pengakses;

    final user = _admin;
    if (user != null) {
      _events = await _repo.syncEvents(user);
    }

    _activeEvent = await _repo.activeEvent();
    notifyListeners();
    return _activeEvent;
  }

  // ----------------------------------------------------------------- event
  Future<bool> saveEvent(StoEvent event, {bool force = false}) async {
    _pesanPenegasan = null;
    try {
      await _repo.saveEvent(event, admin: _admin, force: force);
      _message = 'Event "${event.name}" disimpan.';
      await load();
      return true;
    } on ApiConfirmRequiredException catch (e) {
      // Belum ada yang berubah di server - tunggu keputusan admin.
      _pesanPenegasan = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteEvent(String id) async {
    try {
      await _repo.deleteEvent(id, admin: _admin);
      _message = 'Event dihapus.';
      await load();
      return true;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ------------------------------------------------------------------ user
  Future<bool> saveUser(AppUser user, {String? previousNik}) async {
    try {
      await _repo.saveUser(user, previousNik: previousNik, admin: _admin);
      _message = 'User ${user.nik} disimpan.';
      await load();
      return true;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteUser(String nik) async {
    try {
      await _repo.deleteUser(nik, admin: _admin);
      _message = 'User $nik dihapus.';
      await load();
      return true;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearMessage() {
    _message = null;
    _pesanPenegasan = null;
  }
}
