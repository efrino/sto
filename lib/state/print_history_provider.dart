import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/print_entry.dart';
import '../data/remote/api_client.dart';
import '../data/remote/api_gateway.dart';
import '../services/printer/printer_service.dart';
import 'printer_provider.dart';

/// Riwayat cetak tag - seluruhnya dari server.
///
/// Tidak ada salinan lokalnya: tag dibuat di server sejak `print-tag`, dan
/// keadaan cetaknya (draft / tercetak / gagal) juga milik server. Perangkat
/// hanya menampilkan, supaya angka yang dilihat operator sama dengan yang
/// dilihat admin - termasuk tag yang dicetak dari HT lain.
class PrintHistoryProvider extends ChangeNotifier {
  PrintHistoryProvider({required ApiGateway api}) : _api = api;

  final ApiGateway _api;

  PrintHistory _history = const PrintHistory();
  bool _loading = false;
  bool _mencetak = false;
  String? _error;
  String? _message;

  PrintHistory get history => _history;
  List<PrintEntry> get entries => _history.entries;
  bool get loading => _loading;
  bool get mencetak => _mencetak;
  String? get error => _error;
  String? get message => _message;

  /// Tag yang lembarannya belum keluar - draft maupun yang gagal.
  List<PrintEntry> get menunggu =>
      entries.where((e) => e.perluCetak).toList(growable: false);

  void clearMessage() {
    _message = null;
    _error = null;
  }

  /// Kata kunci pencarian terakhir - dikirim ke server, bukan disaring lokal.
  String get keyword => _keyword;
  String _keyword = '';

  Future<void> setKeyword(AppUser user, String keyword) async {
    _keyword = keyword;
    await load(user);
  }

  Future<void> load(
    AppUser user, {
    List<PrintState> statuses = const [],
    int limit = 100,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _history = await _api.fetchPrintHistory(
        nik: user.nik,
        statuses: statuses,
        keyword: _keyword,
        limit: limit,
      );
    } on ApiException catch (e) {
      // Riwayat sengaja TIDAK dikosongkan diam-diam - layar menampilkan
      // sebabnya supaya operator tahu angkanya sedang tidak terbaca.
      _error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Mencetak ulang tag yang tertinggal (draft/gagal), lalu melaporkan
  /// hasilnya ke server.
  ///
  /// Dipanggil begitu printer normal kembali. Berhenti pada kegagalan
  /// pertama: kalau kertasnya habis lagi, mencoba lembar berikutnya hanya
  /// menambah tag yang ditandai gagal tanpa satu pun keluar.
  Future<int> cetakUlang(PrinterProvider printer, AppUser user) async {
    if (_mencetak) return 0;

    final antre = menunggu;
    if (antre.isEmpty) return 0;

    _mencetak = true;
    _error = null;
    notifyListeners();

    var berhasil = 0;
    try {
      for (final entry in antre) {
        final tag = entry.toTag();
        try {
          await printer.printTag(tag);
          await _api.confirmPrint(tag);
          berhasil++;
        } catch (e) {
          _error = '$e';
          try {
            await _api.reportPrintFailed(tag, '$e');
          } on ApiException {
            // Server tak terjangkau: keadaan gagalnya tetap tersimpan dari
            // percobaan sebelumnya, jadi tag ini tidak hilang.
          }
          break;
        }
      }
    } finally {
      _mencetak = false;
      _message = berhasil == 0
          ? null
          : '$berhasil tag yang tertinggal berhasil dicetak ulang.';
      notifyListeners();
    }

    await load(user);
    return berhasil;
  }

  /// Admin membatalkan tag yang tetap tertinggal.
  ///
  /// Hanya untuk tag yang lembarannya belum keluar - tag yang sudah tercetak
  /// tetap lewat alur pengajuan pembatalan biasa, karena lembarannya sudah
  /// beredar di lapangan dan perlu dicari dulu.
  Future<bool> batalkan(PrintEntry entry, AppUser admin, String alasan) async {
    if (!admin.isAdmin) {
      _error = 'Hanya admin yang boleh membatalkan tag.';
      notifyListeners();
      return false;
    }
    if (!entry.perluCetak) {
      _error = 'Tag ${entry.tagNo} sudah tercetak - ajukan pembatalan biasa.';
      notifyListeners();
      return false;
    }

    try {
      await _api.cancelTag(entry.toTag(), alasan);
      _message = 'Tag ${entry.tagNo} dibatalkan.';
    } on ApiException catch (e) {
      _error = '$e';
      notifyListeners();
      return false;
    }

    await load(admin);
    return true;
  }

  /// Cetak ulang otomatis saat printer sudah normal lagi.
  ///
  /// Sengaja diam bila printer belum siap atau kertasnya habis - operator
  /// tidak perlu diberondong pesan kesalahan hanya karena membuka halaman.
  Future<int> cetakUlangOtomatis(PrinterProvider printer, AppUser user) async {
    if (menunggu.isEmpty) return 0;
    if (!printer.isConnected) return 0;
    if (printer.paperStatus == PaperStatus.out) return 0;

    return cetakUlang(printer, user);
  }
}
