import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/navigation/app_navigator.dart';
import '../data/models/app_user.dart';
import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';

enum SessionStatus { unknown, loading, authenticated, unauthenticated }

class SessionProvider extends ChangeNotifier {
  SessionProvider(this._repository);

  final AuthRepository _repository;

  SessionStatus _status = SessionStatus.unknown;
  AppUser? _user;
  String? _error;
  String? _pesanKeluar;
  Timer? _pemeriksaBerkala;

  SessionStatus get status => _status;
  AppUser? get user => _user;
  String? get error => _error;
  String? get pesanKeluar => _pesanKeluar;
  bool get isBusy => _status == SessionStatus.loading;

  Future<void> bootstrap() async {
    final cached = await _repository.restoreSession();
    _user = cached;
    _status = cached == null
        ? SessionStatus.unauthenticated
        : SessionStatus.authenticated;
    if (_status == SessionStatus.authenticated) {
      _mulaiPemeriksaanBerkala();
    }
    notifyListeners();
  }

  void _mulaiPemeriksaanBerkala() {
    _pemeriksaBerkala?.cancel();
    // Periksa status sesi ke server setiap 15 detik untuk memastikan NIK tidak login di perangkat lain
    _pemeriksaBerkala = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_status == SessionStatus.authenticated) {
        refresh();
      }
    });
  }

  void _hentikanPemeriksaanBerkala() {
    _pemeriksaBerkala?.cancel();
    _pemeriksaBerkala = null;
  }

  /// Menyegarkan identitas user yang sedang login dari server.
  ///
  /// Dipanggil secara berkala, saat kembali ke Home, dan setelah admin menyunting akun,
  /// supaya perubahan izin/area langsung berlaku dan klaim perangkat lain segera terdeteksi.
  Future<void> refresh() async {
    if (_status != SessionStatus.authenticated) return;
    try {
      final segar = await _repository.refreshSession();
      if (segar == null) return;
      _user = segar;
      notifyListeners();
    } on ApiException catch (e) {
      if (!_tolakanServer(e)) return;
      _pesanKeluar = 'Sesi Anda telah berakhir. Silahkan login kembali.';
      await logout();
      AppNavigator.key.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (_) {
      // Jaringan bermasalah - pakai sesi yang ada.
    }
  }

  /// Membedakan "server menolak (pemasangan berpindah / 403)" dari "jaringan tidak sampai".
  bool _tolakanServer(ApiException e) {
    if (e.statusCode == 403) return true;
    final pesan = e.toString().toLowerCase();
    return pesan.contains('tidak terdaftar') ||
        pesan.contains('perangkat lain') ||
        pesan.contains('perangkat ini') ||
        pesan.contains('tidak sesuai') ||
        pesan.contains('akses ditolak');
  }

  /// Terisi sekali setelah login yang memindahkan pemasangan perangkat.
  String? catatanPindahPerangkat;

  Future<bool> login(String nik, {String? password}) async {
    _status = SessionStatus.loading;
    _error = null;
    _pesanKeluar = null;
    notifyListeners();
    try {
      _user = await _repository.login(nik, password: password);
      _status = SessionStatus.authenticated;
      _mulaiPemeriksaanBerkala();
      // Bukan galat: kabar bahwa pemasangan perangkat baru saja berpindah
      // ke perangkat ini. Layar login yang menampilkannya.
      catatanPindahPerangkat = _repository.catatanPindahPerangkat;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _status = SessionStatus.unauthenticated;
      _hentikanPemeriksaanBerkala();
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _hentikanPemeriksaanBerkala();
    await _repository.logout();
    _user = null;
    _status = SessionStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    if (_error == null && _pesanKeluar == null) return;
    _error = null;
    _pesanKeluar = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _hentikanPemeriksaanBerkala();
    super.dispose();
  }
}
