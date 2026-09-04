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

  /// Jeda antar penyegaran saat layar pesan terbuka.
  static const Duration jedaSegarkan = Duration(seconds: 8);

  List<ChatThread> _threads = const [];
  List<ChatMessage> _pesan = const [];
  String? _utasAktif;
  bool _memuat = false;
  bool _mengirim = false;
  String? _error;

  Timer? _denyut;

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
    super.dispose();
  }

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
      _pesan = await _api.fetchChatMessages(nik: user.nik, thread: thread);
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
      final baru = await _api.fetchChatMessages(
        nik: user.nik,
        thread: thread,
        afterId: _pesan.isEmpty ? 0 : _pesan.last.id,
      );
      if (baru.isEmpty) return;

      _pesan = [..._pesan, ...baru];
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

    _mengirim = true;
    _error = null;
    notifyListeners();

    try {
      final pesan = await _api.sendChat(
        nik: user.nik,
        thread: thread,
        body: isi,
      );
      _pesan = [..._pesan, pesan];
    } on ApiException catch (e) {
      // Penolakan penjagaan spam sudah berupa kalimat siap tampil dari server.
      _error = '$e';
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
