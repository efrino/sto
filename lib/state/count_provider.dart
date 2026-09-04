import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/sto_count.dart';
import '../data/repositories/count_repository.dart';
import '../data/repositories/sync_repository.dart';
import '../data/repositories/tag_repository.dart';

/// Alur hitung STO (halaman Scan Tag) + riwayat scan.
class CountProvider extends ChangeNotifier {
  CountProvider({
    required CountRepository countRepository,
    required SyncRepository syncRepository,
    required TagRepository tagRepository,
  })  : _repo = countRepository,
        _syncRepo = syncRepository,
        _tagRepo = tagRepository;

  final CountRepository _repo;
  final SyncRepository _syncRepo;
  final TagRepository _tagRepo;

  List<StoCount> _history = const [];
  Map<String, int> _summary = const {};
  String _keyword = '';
  bool _loading = false;
  bool _syncing = false;
  int _pendingSync = 0;
  String? _message;

  List<StoCount> get history => _history;
  /// Gabungan angka hari ini: jumlah scan, total qty, tag tercetak, dan tag
  /// yang masuk proses pembatalan. Kartu ringkasan menampilkan hanya angka
  /// yang sesuai hak akses user.
  Map<String, int> get summary => _summary;
  String get keyword => _keyword;
  bool get loading => _loading;
  bool get syncing => _syncing;
  int get pendingSync => _pendingSync;
  String? get message => _message;

  /// Terisi bila riwayat terpaksa dibaca dari catatan perangkat ini.
  String? get peringatan => _peringatan;
  String? _peringatan;

  /// Pemilik riwayat yang sedang ditampilkan.
  AppUser? _user;

  /// [user] menentukan riwayat siapa yang dibaca - server menyaring per NIK.
  Future<void> load({AppUser? user}) async {
    _user = user ?? _user;
    _loading = true;
    notifyListeners();
    try {
      _history = await _repo.history(keyword: _keyword, user: _user);
      _peringatan = _repo.peringatanRiwayat;
      final scan = await _repo.todaySummary(user: _user);
      final tag = await _tagRepo.todayActivity();
      _summary = {...scan, ...tag};
      _pendingSync = await _syncRepo.pendingCount();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setKeyword(String keyword) async {
    _keyword = keyword;
    // Pencariannya dilakukan server (parameter `q`), jadi seluruh riwayat
    // NIK ini ikut tercari - bukan hanya 100 baris yang kebetulan terambil.
    await load();
  }

  /// Detail tag hasil scan: dari database lokal, atau dari server bila tagnya
  /// dicetak perangkat lain.
  Future<ScannedTag?> lookup(String tagNo, {AppUser? user}) =>
      _repo.lookup(tagNo, nik: (user ?? _user)?.nik);

  /// Catatan hitung tim user untuk tag tersebut (null bila belum ada).
  Future<StoCount?> myTeamCount(String tagNo, AppUser user) =>
      _repo.myTeamCount(tagNo, user);

  /// Catatan tim lain - ditampilkan sebagai informasi, tidak bisa diubah.
  Future<List<StoCount>> otherTeamCounts(String tagNo, AppUser user) async {
    final semua = await _repo.countsForTag(tagNo);
    return semua
        .where((c) => c.team.toUpperCase() != user.team.toUpperCase())
        .toList();
  }

  /// Menyimpan hasil hitung, lalu mengantre POST { nik, tag_no, tim, qty }.
  Future<StoCount?> submit({
    required ScannedTag tag,
    required AppUser user,
    required int qty,
  }) async {
    try {
      final saved = await _repo.submit(tag: tag, user: user, qty: qty);
      _message = 'Qty ${saved.qty} ${saved.unit} untuk ${saved.tagNo} '
          'tersimpan (${saved.team}).';

      // Langsung didorong ke server, bukan menunggu operator menekan
      // Sinkronkan. Antrean lokal tinggal jaring pengaman saat jaringan mati -
      // sisanya akan ikut terkirim pada dorongan berikutnya.
      await _dorongKeServer();

      await load();
      return saved;
    } catch (e) {
      _message = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Mengirim antrean sekarang juga; kegagalan jaringan didiamkan karena
  /// datanya sudah aman di antrean.
  Future<void> _dorongKeServer() async {
    try {
      await _syncRepo.flush();
    } catch (_) {
      // Offline - tetap di antrean, terkirim pada kesempatan berikutnya.
    }
  }

  Future<SyncResult> sync() async {
    _syncing = true;
    notifyListeners();
    try {
      final result = await _syncRepo.flush();
      _message = result.hasError
          ? 'Terkirim ${result.sent}, gagal ${result.failed}.'
          : 'Sinkronisasi selesai: ${result.sent} data terkirim.';
      await load();
      return result;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  void clearMessage() => _message = null;
}
