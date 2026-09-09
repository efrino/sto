import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/chat_message.dart';
import '../data/remote/api_client.dart';
import '../data/remote/api_gateway.dart';

/// Kotak pesan operator - admin.
///
/// Semuanya di server; perangkat tidak menyimpan salinan. Satu utas dibaca
/// beberapa admin sekaligus, jadi catatan lokal akan cepat berbeda dengan
/// yang sebenarnya.
///
/// Pesan baru dijemput dengan menanyakan server berkala selama layarnya
/// terbuka - bukan push. Handheld ini di jaringan pabrik tanpa akses keluar,
/// jadi push betulan (FCM) tidak bisa diandalkan sampai di perangkat.
class ChatProvider extends ChangeNotifier {
  ChatProvider(this._api);

  final ApiGateway _api;

  /// Jeda antar penyegaran saat layar percakapan terbuka.
  ///
  /// Dipersingkat dari 8 detik: yang dikirim hanya pesan setelah id terakhir,
  /// jadi denyut yang sepi hampir tidak berbiaya - sementara balasan yang
  /// datang 8 detik terlambat terasa seperti pesan yang tidak sampai.
  static const Duration jedaSegarkan = Duration(seconds: 4);

  /// Jeda penyegaran DAFTAR percakapan. Lebih jarang: satu permintaannya
  /// menyapu semua utas, dan yang berubah di sana cuma baris terakhir.
  static const Duration jedaDaftar = Duration(seconds: 10);

  List<ChatThread> _threads = const [];
  List<ChatMessage> _pesan = const [];
  String? _utasAktif;
  bool _memuat = false;
  bool _mengirim = false;
  String? _error;

  Timer? _denyut;
  Timer? _denyutDaftar;

  /// Id pesan terakhir yang sudah dibaca lawan bicara pada utas yang terbuka.
  int _dibacaSampai = 0;

  /// Nomor sementara untuk pesan yang belum dijawab server. Negatif supaya
  /// tidak mungkin bertabrakan dengan id sungguhan.
  int _nomorSementara = -1;

  List<ChatThread> get threads => _threads;
  List<ChatMessage> get pesan => _pesan;
  String? get utasAktif => _utasAktif;
  bool get memuat => _memuat;
  bool get mengirim => _mengirim;
  String? get error => _error;

  /// Jumlah pesan belum dibaca di seluruh percakapan - dipakai badge beranda.
  int get belumDibaca =>
      _threads.fold(0, (jumlah, t) => jumlah + t.belumDibaca);

  void bersihkanPesan() {
    _error = null;
  }

  @override
  void dispose() {
    _denyut?.cancel();
    _denyutDaftar?.cancel();
    super.dispose();
  }

  /// Keadaan pengiriman satu pesan, dilihat dari mata [nik].
  ///
  /// Pesan orang lain tidak punya centang - centang adalah kabar untuk
  /// pengirim, bukan penerima.
  KirimPesan keadaan(ChatMessage m, String nik) =>
      m.keadaanKirim(nik: nik, dibacaSampai: _dibacaSampai);

  /// Daftar percakapan. Dipanggil juga dari beranda hanya untuk badge-nya.
  Future<void> muatThreads(AppUser user) async {
    _memuat = true;
    notifyListeners();
    try {
      _threads = await _api.fetchChatThreads(user.nik);
      _error = null;
    } on ApiException catch (e) {
      _error = '$e';
    } finally {
      _memuat = false;
      notifyListeners();
    }
  }

  /// Membuka satu percakapan dan mulai menyegarkan berkala.
  Future<void> bukaUtas(AppUser user, String thread) async {
    _utasAktif = thread;
    _pesan = const [];
    _memuat = true;
    notifyListeners();

    try {
      final isi = await _api.fetchChatMessages(nik: user.nik, thread: thread);
      _pesan = isi.pesan;
      _dibacaSampai = isi.dibacaSampai;
      _error = null;
      await _tandaiDibaca(user);
    } on ApiException catch (e) {
      _error = '$e';
    } finally {
      _memuat = false;
      notifyListeners();
    }

    mulaiDenyut(user);
  }

  /// Menutup percakapan - denyutnya ikut berhenti supaya tidak ada permintaan
  /// yang terus berjalan setelah layarnya ditinggalkan.
  void tutupUtas() {
    _denyut?.cancel();
    _denyut = null;
    _utasAktif = null;
    _pesan = const [];
    _dibacaSampai = 0;
  }

  /// Menyegarkan DAFTAR percakapan berkala - dipakai layar daftar pesan.
  ///
  /// Tanpa ini, baris terakhir dan jumlah belum dibaca hanya berubah kalau
  /// daftarnya ditarik turun, dan pesan baru terasa tidak pernah datang.
  void mulaiDenyutDaftar(AppUser user) {
    _denyutDaftar?.cancel();
    _denyutDaftar = Timer.periodic(jedaDaftar, (_) => _segarkanDaftar(user));
  }

  void hentikanDenyutDaftar() {
    _denyutDaftar?.cancel();
    _denyutDaftar = null;
  }

  Future<void> _segarkanDaftar(AppUser user) async {
    if (_memuat) return;
    try {
      final baru = await _api.fetchChatThreads(user.nik);
      if (_daftarSama(baru, _threads)) return;
      _threads = baru;
      _error = null;
      notifyListeners();
    } on ApiException {
      // Didiamkan - daftar lama tetap terbaca.
    }
  }

  static bool _daftarSama(List<ChatThread> a, List<ChatThread> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].thread != b[i].thread ||
          a[i].lastId != b[i].lastId ||
          a[i].belumDibaca != b[i].belumDibaca) {
        return false;
      }
    }
    return true;
  }

  void mulaiDenyut(AppUser user) {
    _denyut?.cancel();
    _denyut = Timer.periodic(jedaSegarkan, (_) => _jemputBaru(user));
  }

  /// Hanya pesan yang lebih baru yang diminta - menarik ulang seluruh utas
  /// tiap 8 detik memberatkan server tanpa menambah apa pun.
  Future<void> _jemputBaru(AppUser user) async {
    final thread = _utasAktif;
    if (thread == null) return;

    try {
      // Pesan yang belum punya id server tidak boleh dipakai sebagai batas -
      // nomornya negatif, dan server akan mengirim ulang seluruh utas.
      final terakhir = _pesan.where((m) => m.id > 0).fold<int>(
            0,
            (batas, m) => m.id > batas ? m.id : batas,
          );

      final isi = await _api.fetchChatMessages(
        nik: user.nik,
        thread: thread,
        afterId: terakhir,
      );

      final batasBerubah = isi.dibacaSampai != _dibacaSampai;
      _dibacaSampai = isi.dibacaSampai;

      // Batas baca yang bergerak juga kabar: centang satu berubah jadi dua
      // walau tidak ada pesan baru sama sekali.
      if (isi.pesan.isEmpty) {
        if (batasBerubah) notifyListeners();
        return;
      }

      _pesan = [..._pesan, ...isi.pesan];
      await _tandaiDibaca(user);
      notifyListeners();
    } on ApiException {
      // Denyut yang gagal didiamkan: jaringan pabrik kadang putus sebentar,
      // dan memunculkan galat tiap 8 detik hanya membuat layar tidak terbaca.
    }
  }

  Future<void> kirim(AppUser user, String body) async {
    final thread = _utasAktif;
    final isi = body.trim();
    if (thread == null || isi.isEmpty) return;

    // Pesannya ditampilkan lebih dulu dengan tanda jam - di jaringan pabrik
    // satu permintaan bisa makan beberapa detik, dan layar yang diam selama
    // itu membuat orang menekan kirim berkali-kali.
    final sementara = ChatMessage(
      id: _nomorSementara--,
      thread: thread,
      fromNik: user.nik,
      body: isi,
      createdAt: DateTime.now(),
      broadcast: thread == ChatThread.broadcastKey,
      kirim: KirimPesan.mengirim,
    );

    _pesan = [..._pesan, sementara];
    _mengirim = true;
    _error = null;
    notifyListeners();

    try {
      final pesan = await _api.sendChat(
        nik: user.nik,
        thread: thread,
        body: isi,
      );
      // Yang sementara diganti balasan server - bukan ditambahkan, supaya
      // pesannya tidak tampil dua kali.
      _pesan = [
        for (final m in _pesan)
          if (m.id != sementara.id) m,
        pesan,
      ];
    } on ApiException catch (e) {
      // Penolakan penjagaan spam sudah berupa kalimat siap tampil dari server.
      _error = '$e';
      // Gelembungnya ditarik kembali: isinya dikembalikan ke kotak tulis oleh
      // layar, jadi meninggalkannya di daftar hanya membuat pesan yang tidak
      // pernah terkirim terlihat seolah ada.
      _pesan = [
        for (final m in _pesan)
          if (m.id != sementara.id) m,
      ];
    } finally {
      _mengirim = false;
      notifyListeners();
    }
  }

  Future<void> _tandaiDibaca(AppUser user) async {
    final thread = _utasAktif;
    if (thread == null || _pesan.isEmpty) return;

    try {
      await _api.markChatRead(
        nik: user.nik,
        thread: thread,
        lastId: _pesan.last.id,
      );
      _threads = [
        for (final t in _threads)
          t.thread == thread
              ? ChatThread(
                  thread: t.thread,
                  broadcast: t.broadcast,
                  lastId: t.lastId,
                  lastBody: t.lastBody,
                  lastFrom: t.lastFrom,
                  lastAt: t.lastAt,
                )
              : t,
      ];
    } on ApiException {
      // Penanda baca bukan hal yang perlu menghentikan pembacaan pesan.
    }
  }

  /// Membisukan user selama [menit]; 0 melepasnya (admin).
  Future<bool> bisukan(AppUser admin, String nikUser, int menit) async {
    try {
      await _api.muteChat(nik: admin.nik, nikUser: nikUser, menit: menit);
      _error = null;
      return true;
    } on ApiException catch (e) {
      _error = '$e';
      return false;
    } finally {
      notifyListeners();
    }
  }
}
