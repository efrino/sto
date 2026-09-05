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

  /// true bila tag yang sedang dibuka datang dari sumber produksi dan belum
  /// terdaftar pada STO - keterangannya perlu ikut dikirim saat disiapkan.
  bool _dariProduksi = false;
  bool get dariProduksi => _dariProduksi;

  /// Mengambil detail tag OK hasil pindai kamera.
  ///
  /// [bolehDariProduksi] dipakai menu Siapkan: tag produksi harian belum ada
  /// di tabel STO sampai seseorang menyiapkannya, jadi detailnya diambil dari
  /// sumbernya. Menu Hitung dan Batal sengaja tidak melakukan itu - tag yang
  /// belum disiapkan memang belum boleh dihitung.
  Future<TagOk?> cari(
    AppUser user,
    String idTagOk, {
    bool bolehDariProduksi = false,
  }) async {
    _sibuk = true;
    _error = null;
    _dariProduksi = false;
    notifyListeners();

    final kode = idTagOk.trim();
    try {
      _tag = await _api.fetchTagOk(user.nik, kode);
      return _tag;
    } on ApiException catch (e) {
      if (!bolehDariProduksi) {
        _tag = null;
        _error = '$e';
        return null;
      }

      // Belum terdaftar pada STO - coba sumber produksinya.
      try {
        _tag = await _api.fetchTagOkPrepare(user.nik, kode);
        _dariProduksi = true;
        return _tag;
      } on ApiException catch (e2) {
        _tag = null;
        _error = '$e2';
        return null;
      }
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Pilihan event yang harus ditentukan petugas - terisi bila server
  /// menolak dengan 409 karena ada beberapa event berjalan sekaligus.
  List<Map<String, dynamic>> _pilihanEvent = const [];
  List<Map<String, dynamic>> get pilihanEvent => _pilihanEvent;

  /// Tag yang menurut server sudah disiapkan lebih dulu - bukan galat,
  /// melainkan keterangan siapa yang mendahului.
  TagOk? _sudahDisiapkan;
  TagOk? get sudahDisiapkan => _sudahDisiapkan;

  /// Rincian kesalahan validasi dari server; ditampilkan seluruhnya, karena
  /// server mengirim semuanya sekaligus - menampilkan yang pertama saja
  /// membuat operator memperbaiki satu per satu.
  List<String> _rincianGalat = const [];
  List<String> get rincianGalat => _rincianGalat;

  void bersihkanKonflik() {
    _pilihanEvent = const [];
    _sudahDisiapkan = null;
    _rincianGalat = const [];
  }

  /// SIAPKAN sekali panggil: mendaftarkan tag sekaligus membuatnya siap
  /// dihitung. [idEvent] diisi setelah petugas memilih, bila server meminta.
  Future<bool> siapkanBaru(
    AppUser user,
    String idTagOk, {
    required String area,
    int? idEvent,
  }) async {
    _sibuk = true;
    _error = null;
    bersihkanKonflik();
    notifyListeners();

    try {
      _tag = await _api.prepareTagOk(
        nik: user.nik,
        idTagOk: idTagOk.trim(),
        area: area,
        idEvent: idEvent,
        scanAt: DateTime.now(),
      );
      _pesan = 'Tag OK $idTagOk siap dihitung.';
      return true;
    } on ApiException catch (e) {
      // Endpoint POST-nya belum ada di semua deployment. Selama itu, jalur
      // lama dipakai supaya operator tetap bisa bekerja - bukan menampilkan
      // "Unknown method" yang tidak bisa ia perbaiki sendiri.
      if (e.statusCode == 405 ||
          e.message.toLowerCase().contains('unknown method')) {
        final lama = await siapkan(user, idTagOk);
        if (lama) return true;
        return false;
      }

      _rincianGalat = e.errors;

      if (e.konflik) {
        final isi = e.body ?? const <String, dynamic>{};

        final events = isi['events'];
        if (events is List && events.isNotEmpty) {
          _pilihanEvent = [
            for (final x in events)
              if (x is Map) Map<String, dynamic>.from(x),
          ];
        }

        final data = isi['data'];
        if (data is Map) {
          _sudahDisiapkan = TagOk.fromServer(Map<String, dynamic>.from(data));
          _tag = _sudahDisiapkan;
        }
      }

      _error = e.message;
      return false;
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
      _tag = await _api.openTagOk(
        user.nik,
        idTagOk.trim(),
        // Keterangan hanya perlu dikirim untuk tag yang belum terdaftar;
        // yang sudah ada barisnya tidak boleh ditimpa dari perangkat.
        keterangan: _dariProduksi ? _tag : null,
      );
      _dariProduksi = false;
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
