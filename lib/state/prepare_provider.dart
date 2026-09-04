import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../data/models/app_user.dart';
import '../data/models/part_item.dart';
import '../data/models/print_batch.dart';
import '../data/models/sto_tag.dart';
import '../data/repositories/part_repository.dart';
import '../data/repositories/sync_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../services/printer/printer_service.dart';
import 'printer_provider.dart';

/// Alur utama: cari part -> tentukan jumlah tag -> generate -> preview -> cetak.
class PrepareProvider extends ChangeNotifier {
  PrepareProvider({
    required PartRepository partRepository,
    required TagRepository tagRepository,
    required SyncRepository syncRepository,
  }) : _partRepo = partRepository,
       _tagRepo = tagRepository,
       _syncRepo = syncRepository;

  final PartRepository _partRepo;
  final TagRepository _tagRepo;
  final SyncRepository _syncRepo;

  /// Area yang boleh dilihat user (izin dari admin). Kosong = tanpa batas.
  List<String> _allowedAreas = const [];
  List<String> get allowedAreas => _allowedAreas;

  /// Dipanggil saat halaman pencarian dibuka: membatasi daftar part sesuai
  /// izin area yang diberikan admin ke user tersebut.
  void applyPermissions(AppUser user) {
    _allowedAreas = user.hasAreaLimit ? user.areas : const [];
  }

  // ------------------------------------------------------------- pencarian
  static const int pageSize = 30;

  String _keyword = '';
  List<PartItem> _results = const [];
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _offset = 0;
  PartCacheInfo _cacheInfo = const PartCacheInfo(count: 0);

  String get keyword => _keyword;
  List<PartItem> get results => _results;
  bool get searching => _searching;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  PartCacheInfo get cacheInfo => _cacheInfo;

  // -------------------------------------------------------------- formulir
  PartItem? _selectedPart;
  int _qty = AppConfig.defaultTagPerBatch;
  int _qtyPerTag = 0;
  String _areaOverride = '';
  String _note = '';

  PartItem? get selectedPart => _selectedPart;
  int get qty => _qty;
  int get qtyPerTag => _qtyPerTag;
  String get areaOverride => _areaOverride;
  String get note => _note;

  // ---------------------------------------------------------------- batch
  PrintBatch? _batch;
  List<StoTag> _tags = const [];
  bool _generating = false;
  bool _offlineSequence = false;
  String? _error;

  PrintBatch? get batch => _batch;
  List<StoTag> get tags => _tags;
  bool get generating => _generating;
  bool get offlineSequence => _offlineSequence;
  String? get error => _error;

  // -------------------------------------------------------------- cetak
  bool _printing = false;
  bool _autoPrinted = false;
  int _printingIndex = -1;
  String? _printError;
  PaperStatus _paperStatus = PaperStatus.unknown;

  bool get printing => _printing;

  /// Keadaan kertas saat pencetakan terakhir.
  PaperStatus get paperStatus => _paperStatus;

  /// true bila printer tidak bisa ditanya keadaan kertasnya. Ditampilkan di
  /// bar ringkasan; pemeriksaan hasil cetaknya sendiri kini selalu dilakukan
  /// lewat ceklis di akhir batch, karena printer handheld juga menahan
  /// antrean saat kertas habis - "byte terkirim" tidak pernah jadi bukti.
  bool get perluCekFisik => _paperStatus == PaperStatus.unknown;

  /// Halaman preview mencetak otomatis satu kali saat dibuka - supaya tidak
  /// ada nomor tag yang dibuat tapi tidak pernah keluar dari printer.
  bool get autoPrinted => _autoPrinted;
  void markAutoPrinted() => _autoPrinted = true;
  int get printingIndex => _printingIndex;
  String? get printError => _printError;

  int get printedCount =>
      _tags.where((t) => t.status == TagStatus.printed).length;
  int get cancelledCount =>
      _tags.where((t) => t.status == TagStatus.cancelled).length;
  int get pendingCount => _tags.where((t) => t.isPrintable).length;
  bool get allDone => _tags.isNotEmpty && pendingCount == 0;

  // ---------------------------------------------------------------- aksi
  /// Menyiapkan layar cari part.
  ///
  /// Hasil dari cache ditampilkan LEBIH DULU, penyegaran master berjalan di
  /// latar. Sebelumnya layar menunggu tarikan ribuan baris dari server selesai
  /// sebelum memperlihatkan apa pun - halaman terasa macet setiap kali dibuka,
  /// padahal partnya sudah ada di perangkat.
  Future<void> bootstrapSearch() async {
    _cacheInfo = await _partRepo.cacheInfo();
    if (_keyword.isEmpty) await search('');

    // Sengaja tidak di-await: kalau servernya lambat, yang tertunda hanya
    // kesegaran master - bukan layarnya.
    unawaited(_segarkanDiLatar());
  }

  Future<void> _segarkanDiLatar() async {
    await _partRepo.refreshIfStale(areas: _allowedAreas);
    _cacheInfo = await _partRepo.cacheInfo();
    // Hasil ikut dimuat ulang hanya bila layarnya memang masih kosong -
    // mengganti daftar yang sedang dibaca operator justru mengagetkan.
    if (_keyword.isEmpty && _results.isEmpty) await search('');
    notifyListeners();
  }

  Future<void> search(String keyword) async {
    _keyword = keyword;
    _searching = true;
    _offset = 0;
    _hasMore = false;
    notifyListeners();
    try {
      final items = await _partRepo.search(
        keyword,
        limit: pageSize,
        offset: 0,
        areas: _allowedAreas,
      );
      _results = items;
      _offset = items.length;
      _hasMore = items.length >= pageSize;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  /// Lazy load halaman berikutnya (infinite scroll).
  Future<void> loadMore() async {
    if (_searching || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final more = await _partRepo.search(
        _keyword,
        limit: pageSize,
        offset: _offset,
        areas: _allowedAreas,
      );
      if (more.isNotEmpty) {
        _results = [..._results, ...more];
        _offset += more.length;
      }
      _hasMore = more.length >= pageSize;
    } catch (e) {
      // Pertahankan data yang sudah ada
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refreshMaster() async {
    _searching = true;
    _offset = 0;
    _hasMore = false;
    notifyListeners();
    try {
      await _partRepo.refreshCache(force: true, areas: _allowedAreas);
      _cacheInfo = await _partRepo.cacheInfo();
      final items = await _partRepo.search(
        _keyword,
        limit: pageSize,
        offset: 0,
        areas: _allowedAreas,
      );
      _results = items;
      _offset = items.length;
      _hasMore = items.length >= pageSize;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  void selectPart(PartItem part) {
    _selectedPart = part;
    _areaOverride = part.area;
    _qty = AppConfig.defaultTagPerBatch;
    _qtyPerTag = 0;
    _note = '';
    _batch = null;
    _tags = const [];
    _error = null;
    notifyListeners();
  }

  void setQty(int value) {
    _qty = value.clamp(1, AppConfig.maxTagPerBatch);
    notifyListeners();
  }

  void setQtyPerTag(int value) {
    _qtyPerTag = value < 0 ? 0 : value;
    notifyListeners();
  }

  void setAreaOverride(String value) {
    _areaOverride = value;
  }

  void setNote(String value) {
    _note = value;
  }

  /// Membuat N tag unik (increment id) untuk part terpilih.
  /// [eventId] wajib: tag hanya boleh dibuat saat ada event STO yang aktif.
  Future<bool> generate(AppUser user, {required String eventId}) async {
    // Penjaga ketukan ganda. Tanpa ini satu ketukan tambahan membuat SATU
    // BATCH BARU di server: `print-tag` sudah terlanjur dipanggil per lembar,
    // jadi nomornya benar-benar terpakai dan tag kelebihan itu tertinggal
    // sebagai "belum tercetak" di riwayat - persis yang terjadi pada tag
    // 519 & 520.
    if (_generating) return false;

    final part = _selectedPart;
    if (part == null) {
      _error = 'Belum ada part yang dipilih.';
      notifyListeners();
      return false;
    }
    _generating = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _tagRepo.generate(
        part: part,
        qty: _qty,
        user: user,
        eventId: eventId,
        areaOverride: _areaOverride,
        note: _note,
        qtyPerTag: _qtyPerTag,
      );
      _batch = result.batch;
      _tags = result.tags;
      _offlineSequence = !result.fromServerSequence;
      _autoPrinted = false;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  /// Memuat kembali batch yang sudah ada (dipanggil dari halaman Riwayat
  /// saat operator melanjutkan cetak tag yang masih draft).
  Future<bool> loadBatch(String batchId) async {
    final tags = await _tagRepo.byBatch(batchId);
    if (tags.isEmpty) return false;
    _tags = tags;
    _batch = PrintBatch.fromTags(tags);
    _offlineSequence = tags.any((t) => t.offlineSequence);
    _printError = null;
    _autoPrinted = false;
    notifyListeners();
    return true;
  }

  /// Melaporkan tag yang lembarannya TIDAK keluar dari printer ke server.
  ///
  /// Keadaannya milik server, bukan perangkat ini: tag yang gagal tetap harus
  /// terlihat admin (untuk dibatalkan) dan tetap ada saat aplikasi dipasang
  /// ulang. Statusnya lokal tetap BELUM CETAK, jadi tag yang sama akan
  /// dicetak ulang begitu printer normal.
  Future<void> _laporkanGagal(Iterable<StoTag> tags, String pesan) async {
    for (final tag in tags) {
      await _tagRepo.markPrintFailed(tag, pesan);
    }
    await _dorongKeServer();
  }

  /// Mengirim antrean outbox sekarang juga - riwayat di server harus menyusul
  /// dalam hitungan detik, bukan menunggu operator menekan Sinkronkan.
  Future<void> _dorongKeServer() async {
    try {
      await _syncRepo.flush();
    } catch (_) {
      // Jaringan mati: antreannya tetap di outbox dan terkirim nanti.
    }
  }

  /// Cetak seluruh tag yang masih berstatus draft, satu per satu.
  /// Tag ditandai "sudah cetak" HANYA setelah printer melapor sukses.
  ///
  /// Sebelum tiap lembar, keadaan kertas ditanyakan ke printer. Ini menutup
  /// lubang "cetak senyap": tanpa pemeriksaan itu, `writeBytes` yang berhasil
  /// hanya berarti byte-nya masuk ke soket Bluetooth - kertas yang habis tetap
  /// menghasilkan tag berstatus SUDAH CETAK tanpa lembaran fisik.
  ///
  /// Printer yang tidak menjawab ([PaperStatus.unknown]) tidak ditanya
  /// berulang kali - percuma menunggu 700 ms per lembar - tetapi ditandai
  /// lewat [perluCekFisik]; hasil cetaknya diperiksa lewat ceklis di akhir
  /// batch.
  Future<void> printAll(PrinterProvider printer, AppUser user) async {
    if (_printing) return;
    _printing = true;
    _printError = null;
    _paperStatus = PaperStatus.unknown;
    notifyListeners();

    var tanyaKertas = true;

    for (var i = 0; i < _tags.length; i++) {
      final tag = _tags[i];
      if (!tag.isPrintable) continue;

      if (tanyaKertas) {
        _paperStatus = await printer.refreshPaperStatus();
        if (_paperStatus == PaperStatus.out) {
          final sisa = _tags.where((t) => t.isPrintable).toList();
          _printError =
              'Kertas printer habis. ${sisa.length} tag belum tercetak dan '
              'tetap berstatus BELUM CETAK - ganti kertas lalu tekan Cetak '
              'lagi.';
          await _laporkanGagal(sisa, 'Kertas printer habis');
          break;
        }
        // Printer bisu: berhenti bertanya, biar tidak menunggu tiap lembar.
        if (_paperStatus == PaperStatus.unknown) tanyaKertas = false;
      }

      _printingIndex = i;
      notifyListeners();
      try {
        final isLast = (i == _tags.length - 1) ||
            !_tags.skip(i + 1).any((t) => t.isPrintable);
        await printer.printTag(tag, isLastInBatch: isLast);
        final updated = await _tagRepo.markPrinted(tag);
        _tags = List<StoTag>.from(_tags)..[i] = updated;
      } catch (e) {
        _printError = e.toString();
        await _laporkanGagal([tag], e.toString());
        break;
      }
    }

    _printingIndex = -1;
    _printing = false;
    notifyListeners();
    await _dorongKeServer();
  }

  /// Cetak satu tag tertentu (mis. setelah gagal di tengah batch).
  Future<bool> printOne(
    PrinterProvider printer,
    AppUser user,
    StoTag tag,
  ) async {
    if (_printing) return false;
    final index = _tags.indexWhere((t) => t.tagNo == tag.tagNo);
    if (index < 0 || !_tags[index].isPrintable) return false;

    _printing = true;
    _printingIndex = index;
    _printError = null;
    notifyListeners();
    try {
      _paperStatus = await printer.refreshPaperStatus();
      if (_paperStatus == PaperStatus.out) {
        _printError =
            'Kertas printer habis - ganti kertas dulu, tag ini '
            'tetap berstatus BELUM CETAK.';
        await _laporkanGagal([_tags[index]], 'Kertas printer habis');
        return false;
      }
      await printer.printTag(_tags[index], isLastInBatch: true);
      final updated = await _tagRepo.markPrinted(_tags[index]);
      _tags = List<StoTag>.from(_tags)..[index] = updated;
      await _dorongKeServer();
      return true;
    } catch (e) {
      _printError = e.toString();
      await _laporkanGagal([_tags[index]], e.toString());
      return false;
    } finally {
      _printing = false;
      _printingIndex = -1;
      notifyListeners();
    }
  }

  /// Pembatalan seluruh batch - hanya admin (operator memakai jalur
  /// pengajuan lewat menu Scan Tag).
  Future<bool> cancelBatch(String reason, AppUser admin) async {
    final batchId = _batch?.batchId;
    if (batchId == null || !admin.isAdmin) return false;
    try {
      await _tagRepo.cancelBatch(batchId, reason, admin);
      _tags = await _tagRepo.byBatch(batchId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearPrintError() {
    _printError = null;
    notifyListeners();
  }

  /// Bersihkan sesi setelah selesai supaya tidak terbawa ke part berikutnya.
  void resetBatch() {
    _batch = null;
    _tags = const [];
    _printError = null;
    _printingIndex = -1;
    _autoPrinted = false;
    notifyListeners();
  }

  void resetAll() {
    resetBatch();
    _selectedPart = null;
    _qty = AppConfig.defaultTagPerBatch;
    _qtyPerTag = 0;
    _areaOverride = '';
    _note = '';
    _error = null;
    notifyListeners();
  }
}
