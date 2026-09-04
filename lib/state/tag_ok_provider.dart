import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/tag_ok.dart';
import '../data/remote/api_client.dart';
import '../data/remote/api_gateway.dart';

/// Alur Tag OK: siapkan lalu hitung.
///
/// Semuanya langsung ke server - tidak ada salinan lokal. Tag OK dipindai
/// bergantian oleh beberapa handheld, jadi keadaan yang tersimpan di satu
/// perangkat justru menyesatkan: tag yang di sini terlihat "siap dihitung"
/// bisa saja sudah dihitung orang lain semenit yang lalu.
class TagOkProvider extends ChangeNotifier {
  TagOkProvider(this._api);

  final ApiGateway _api;

  TagOk? _tag;
  List<TagOk> _riwayat = const [];
  bool _sibuk = false;
  bool _memuat = false;
  String? _pesan;
  String? _error;

  /// Tag yang sedang dibuka di layar; null berarti belum ada yang dipindai.
  TagOk? get tag => _tag;
  List<TagOk> get riwayat => _riwayat;
  bool get sibuk => _sibuk;
  bool get memuat => _memuat;
  String? get pesan => _pesan;
  String? get error => _error;

  void bersihkanPesan() {
    _pesan = null;
    _error = null;
  }

  /// Melepas tag yang sedang dibuka - dipanggil saat operator ingin memindai
  /// tag berikutnya.
  void lepas() {
    _tag = null;
    _error = null;
    notifyListeners();
  }

  /// Mengambil detail tag OK hasil pindai kamera.
  Future<TagOk?> cari(AppUser user, String idTagOk) async {
    _sibuk = true;
    _error = null;
    notifyListeners();
    try {
      _tag = await _api.fetchTagOk(user.nik, idTagOk.trim());
      return _tag;
    } on ApiException catch (e) {
      _tag = null;
      _error = '$e';
      return null;
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Menyiapkan tag: menandainya siap dihitung.
  Future<bool> siapkan(AppUser user, String idTagOk) async {
    _sibuk = true;
    _error = null;
    notifyListeners();
    try {
      _tag = await _api.openTagOk(user.nik, idTagOk.trim());
      _pesan = 'Tag OK $idTagOk siap dihitung.';
      return true;
    } on ApiException catch (e) {
      _error = '$e';
      return false;
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Mencatat hasil hitung fisik lalu menutup tag.
  Future<bool> hitung(AppUser user, String idTagOk, int qty) async {
    _sibuk = true;
    _error = null;
    notifyListeners();
    try {
      _tag = await _api.scanTagOk(user.nik, idTagOk.trim(), qty);
      _pesan = 'Tag OK $idTagOk tercatat $qty pcs.';
      return true;
    } on ApiException catch (e) {
      _error = '$e';
      return false;
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Mengajukan pembatalan tag OK.
  ///
  /// Semua pembatalan - termasuk yang diajukan admin - masuk daftar pengajuan
  /// lebih dulu, sama seperti tag STO, supaya jejak persetujuannya ada.
  Future<bool> ajukanBatal(AppUser user, String idTagOk, String alasan) =>
      _kirimBatal(user, idTagOk, alasan: alasan);

  /// Keputusan admin atas satu pengajuan.
  Future<bool> putuskanBatal(AppUser user, String idTagOk, bool setuju) =>
      _kirimBatal(user, idTagOk, keputusan: setuju ? 'setuju' : 'tolak');

  Future<bool> _kirimBatal(
    AppUser user,
    String idTagOk, {
    String alasan = '',
    String? keputusan,
  }) async {
    _sibuk = true;
    _error = null;
    notifyListeners();
    try {
      final hasil = await _api.cancelTagOk(
        nik: user.nik,
        idTagOk: idTagOk.trim(),
        alasan: alasan,
        keputusan: keputusan,
      );
      // Baris di daftar ikut diperbarui supaya layar riwayat tidak perlu
      // menarik ulang seluruh halaman hanya untuk satu baris.
      _riwayat = [
        for (final t in _riwayat) t.idTagOk == hasil.idTagOk ? hasil : t,
      ];
      if (_tag?.idTagOk == hasil.idTagOk) _tag = hasil;
      _pesan = keputusan == null
          ? 'Pengajuan batal $idTagOk terkirim.'
          : (keputusan == 'setuju'
              ? 'Tag OK $idTagOk dibatalkan.'
              : 'Pengajuan $idTagOk ditolak.');
      return true;
    } on ApiException catch (e) {
      _error = '$e';
      return false;
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Daftar tag OK terakhir; [terbuka] null berarti semua keadaan.
  Future<void> muatRiwayat(
    AppUser user, {
    bool? terbuka,
    String? keyword,
    int? batal,
    bool hanyaMilikSaya = false,
  }) async {
    _memuat = true;
    notifyListeners();
    try {
      _riwayat = await _api.fetchTagOkList(
        nik: user.nik,
        terbuka: terbuka,
        keyword: keyword,
        batal: batal,
        milik: hanyaMilikSaya ? user.nik : null,
      );
      _error = null;
    } on ApiException catch (e) {
      _error = '$e';
    } finally {
      _memuat = false;
      notifyListeners();
    }
  }
}
