import 'package:flutter/foundation.dart';

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

  SessionStatus get status => _status;
  AppUser? get user => _user;
  String? get error => _error;
  bool get isBusy => _status == SessionStatus.loading;

  Future<void> bootstrap() async {
    final cached = await _repository.restoreSession();
    _user = cached;
    _status = cached == null
        ? SessionStatus.unauthenticated
        : SessionStatus.authenticated;
    notifyListeners();
  }

  /// Menyegarkan identitas user yang sedang login dari server.
  ///
  /// Dipanggil saat kembali ke Home dan setelah admin menyunting akun, supaya
  /// perubahan izin/area langsung berlaku - menu ikut berubah tanpa login
  /// ulang.
  ///
  /// Kegagalan jaringan sengaja didiamkan: sesi yang ada tetap dipakai. Yang
  /// TIDAK didiamkan adalah penolakan server (mis. pemasangan perangkat
  /// dicabut) - user dikeluarkan, karena sejak itu ia memang tidak berhak.
  Future<void> refresh() async {
    if (_status != SessionStatus.authenticated) return;
    try {
      final segar = await _repository.refreshSession();
      if (segar == null) return;
      _user = segar;
      notifyListeners();
    } on ApiException catch (e) {
      if (!_tolakanServer(e)) return;
      await logout();
    } catch (_) {
      // Jaringan bermasalah - pakai sesi yang ada.
    }
  }

  /// Membedakan "server menolak" dari "jaringan tidak sampai". Hanya yang
  /// pertama boleh mengeluarkan user.
  bool _tolakanServer(ApiException e) {
    final pesan = e.toString().toLowerCase();
    return pesan.contains('tidak terdaftar') ||
        pesan.contains('tidak sesuai') ||
        pesan.contains('perangkat ini');
  }

  Future<bool> login(String nik, {String? password}) async {
    _status = SessionStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _user = await _repository.login(nik, password: password);
      _status = SessionStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _status = SessionStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    _user = null;
    _status = SessionStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
