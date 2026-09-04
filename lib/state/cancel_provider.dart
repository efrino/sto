import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/pengajuan_batal.dart';
import '../data/models/sto_tag.dart';
import '../data/repositories/cancel_repository.dart';
import '../data/repositories/sync_repository.dart';

/// Kotak menu "Batal Tag": operator mengajukan, admin memutuskan.
class CancelProvider extends ChangeNotifier {
  CancelProvider(this._repo, this._syncRepo);

  final CancelRepository _repo;
  final SyncRepository _syncRepo;

  /// Mengirim antrean sekarang juga.
  ///
  /// Tanpa ini keputusan admin hanya tersimpan di perangkat: status lokal
  /// berubah jadi DIBATALKAN sementara server masih menganggapnya menunggu
  /// keputusan - tag terlihat "tidak bisa dibatalkan" padahal perintahnya
  /// memang belum pernah sampai. Kegagalan jaringan didiamkan; datanya sudah
  /// aman di antrean.
  Future<void> _dorongKeServer() async {
    try {
      await _syncRepo.flush();
    } catch (_) {
      // Offline - terkirim pada kesempatan berikutnya.
    }
  }

  List<PengajuanBatal> _pending = const [];
  bool _loading = false;
  bool _busy = false;
  String? _message;

  List<PengajuanBatal> get pending => _pending;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get message => _message;

  /// Peringatan bila antrean terpaksa dibaca dari catatan perangkat ini.
  String? get peringatan => _repo.peringatanAntrean;

  /// [admin] menentukan sumber antrean: ada dan admin -> server, selain itu
  /// catatan perangkat.
  Future<void> load({AppUser? admin}) async {
    _admin = admin ?? _admin;
    _loading = true;
    notifyListeners();
    try {
      _pending = await _repo.pendingRequests(admin: _admin);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  AppUser? _admin;

  /// Mencari tag; tag milik perangkat lain ikut diambil detailnya.
  Future<StoTag?> resolve(String tagNo) async {
    _busy = true;
    notifyListeners();
    try {
      return await _repo.resolve(tagNo);
    } catch (e) {
      _message = e.toString();
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> requestCancel(StoTag tag, String reason, AppUser user) async {
    try {
      await _repo.requestCancel(tag, reason, user);
      _message = 'Pengajuan pembatalan ${tag.tagNo} dikirim ke admin.';
      await _dorongKeServer();
      await load();
      return true;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> approve(StoTag tag, AppUser admin, {String? reason}) async {
    if (!admin.isAdmin) {
      _message = 'Hanya admin yang boleh menyetujui pengajuan pembatalan.';
      notifyListeners();
      return false;
    }
    try {
      await _repo.approveCancel(tag, admin, reason: reason);
      _message = 'Tag ${tag.tagNo} dibatalkan.';
      await _dorongKeServer();
      await load();
      return true;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> reject(StoTag tag, AppUser admin) async {
    if (!admin.isAdmin) {
      _message = 'Hanya admin yang boleh menolak pengajuan pembatalan.';
      notifyListeners();
      return false;
    }
    try {
      await _repo.rejectCancel(tag, admin);
      _message = 'Pengajuan ${tag.tagNo} ditolak.';
      await _dorongKeServer();
      await load();
      return true;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearMessage() => _message = null;
}
