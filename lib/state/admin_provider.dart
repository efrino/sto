import 'dart:async';

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

  // ------------------------------------------------------ denyut event
  /// Jeda penyegaran keadaan event.
  ///
  /// Event dibuka/ditutup dan pencetakannya dinyalakan/dimatikan oleh admin
  /// dari perangkat lain. Tanpa denyut ini, handheld operator baru tahu saat
  /// ia kebetulan berpindah layar - sementara riwayat dan pesan sudah
  /// menyegarkan diri sendiri. Sepuluh detik sejalan dengan yang lain.
  static const Duration jedaEvent = Duration(seconds: 10);
  Timer? _denyutEvent;

  void mulaiDenyutEvent(AppUser user) {
    _denyutEvent?.cancel();
    _denyutEvent = Timer.periodic(jedaEvent, (_) => _segarkanEventDiam(user));
  }

  void hentikanDenyutEvent() {
    _denyutEvent?.cancel();
    _denyutEvent = null;
  }

  @override
  void dispose() {
    _denyutEvent?.cancel();
    super.dispose();
  }

  /// Menarik ulang event tanpa tanda memuat, dan hanya membangun ulang layar
  /// bila ada yang benar-benar berubah.
  Future<void> _segarkanEventDiam(AppUser user) async {
    if (_loading) return;
    try {
      final baru = await _repo.syncEvents(user);

      // syncEvents mengembalikan daftar kosong saat server tidak terjangkau
      // (dan mengisi peringatanSinkron). Itu BUKAN "tidak ada event" - kalau
      // ditelan apa adanya, pita di beranda berteriak "belum ada event"
      // setiap kali Wi-Fi pabrik tersendat sebentar.
      if (baru.isEmpty && _repo.peringatanSinkron != null) return;

      final aktifBaru = await _repo.activeEvent();
      if (_eventSama(baru, _events) && _eventSama1(aktifBaru, _activeEvent)) {
        return;
      }

      _events = baru;
      _activeEvent = aktifBaru;
      notifyListeners();
    } catch (_) {
      // Diam saja - keadaan yang lama tetap ditampilkan.
    }
  }

  static bool _eventSama1(StoEvent? a, StoEvent? b) {
    if (a == null || b == null) return a == b;
    return a.id == b.id &&
        a.status == b.status &&
        a.bolehCetak == b.bolehCetak &&
        a.totalTim == b.totalTim &&
        a.startDate == b.startDate &&
        a.endDate == b.endDate &&
        a.name == b.name;
  }

  static bool _eventSama(List<StoEvent> a, List<StoEvent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eventSama1(a[i], b[i])) return false;
    }
    return true;
  }

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
