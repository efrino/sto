import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../data/local/prefs_store.dart';
import '../data/remote/api_gateway.dart';
import '../data/models/sto_tag.dart';
import '../services/printer/label_builder.dart';
import '../services/printer/label_document.dart';
import '../services/printer/printer_service.dart';

/// Mengelola koneksi ke printer internal MPOS 332 dan preferensi kertas.
class PrinterProvider extends ChangeNotifier {
  PrinterProvider({
    required PrinterService service,
    required PrefsStore prefs,
    ApiGateway? api,
    PrinterService Function()? cadangan,
  })  : _service = service,
        _prefs = prefs,
        _api = api,
        _cadangan = cadangan;

  PrinterService _service;
  final PrefsStore _prefs;

  /// Sumber setelan printer bersama. Null di test/mode simulasi - setelannya
  /// lalu memakai cache lokal apa adanya.
  final ApiGateway? _api;

  /// Jalur printer pengganti bila jalur utama menolak - dipakai saat aplikasi
  /// memilih service pabrikan tapi susunan AIDL-nya ternyata berbeda.
  final PrinterService Function()? _cadangan;
  bool _sudahPindahCadangan = false;

  List<PrinterDevice> _devices = const [];
  PrinterDevice? _selected;
  PaperSize _paperSize = PaperSize.mm58;
  bool _autoConnect = true;
  bool _busy = false;
  String? _error;

  /// Jarak maju kertas (titik ESC/POS) setelah tag terakhir dalam batch.
  ///
  /// Kalibrasi dot-ke-mm ternyata berbeda antar printer klon - nilai bawaan
  /// [feedAfterTagDots] cuma titik awal. Operator menyetelnya sendiri lewat
  /// Setting > Printer, dan hasilnya disimpan per perangkat.
  int _feedDots = feedAfterTagDots;

  /// Jarak antar tag dalam satu batch. Terpisah dari [_feedDots] karena
  /// urusannya beda: yang ini murni jarak gunting antar lembar, sedangkan
  /// [_feedDots] hanya tambahan di atas jarak yang sudah dibuat printer
  /// sendiri saat cetakan berhenti.
  int _gapDots = gapAntarTagDots;


  /// true bila setelan yang dipakai berasal dari server. False berarti sedang
  /// memakai cache perangkat - layar menyebutkannya apa adanya.
  bool _setelanDariServer = false;
  bool get setelanDariServer => _setelanDariServer;

  PrinterService get service => _service;
  List<PrinterDevice> get devices => _devices;
  PrinterDevice? get selected => _selected;
  PaperSize get paperSize => _paperSize;
  bool get autoConnect => _autoConnect;
  int get feedDots => _feedDots;
  int get gapDots => _gapDots;
  bool get busy => _busy;
  String? get error => _error;
  PrinterState get state => _service.state;
  bool get isConnected => _service.state == PrinterState.connected;

  String get statusLabel {
    switch (_service.state) {
      case PrinterState.connected:
        return 'Tersambung: ${_selected?.name ?? '-'}';
      case PrinterState.connecting:
        return 'Menyambungkan...';
      case PrinterState.error:
        return 'Printer bermasalah';
      case PrinterState.disconnected:
      case PrinterState.unknown:
        return 'Printer belum tersambung';
    }
  }

  /// Dipakai halaman Setting saat berpindah antara printer nyata dan simulasi.
  void swapService(PrinterService service) {
    _service = service;
    _selected = service.currentDevice;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    _paperSize = await _prefs.paperSize();
    _autoConnect = await _prefs.autoConnectPrinter();
    await _prefs.bersihkanSetelanJarakLama();
    _feedDots = await _prefs.paperFeedDots() ?? feedAfterTagDots;
    _gapDots = await _prefs.tagGapDots() ?? gapAntarTagDots;

    // Nilai lokal di atas hanya bekal awal supaya printer tetap bisa dipakai
    // saat jaringan mati; begitu server menjawab, angkanyalah yang berlaku.
    await muatSetelanServer();
    var address = await _prefs.printerAddress();
    var name = await _prefs.printerName();

    // Sisa percobaan jalur service pabrikan: alamatnya tidak berarti apa-apa
    // bagi jalur Bluetooth, jadi dibuang supaya printer internal dicari ulang.
    if (address != null && address.startsWith('vendor:')) {
      await _prefs.clearPrinter();
      address = null;
      name = null;
    }

    if (address != null && name != null) {
      _selected = PrinterDevice(name: name, address: address);
      if (_autoConnect) {
        await connect(_selected!, silent: true);
      }
    } else if (_autoConnect) {
      // Belum pernah memilih printer: coba temukan printer internal sendiri
      // (sekaligus memunculkan permintaan izin Bluetooth sejak awal).
      try {
        await ensureReady();
      } catch (_) {
        // Diamkan - status printer tetap tampil di dashboard.
      }
    }
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _devices = await _service.discoverDevices();
      // Pilih otomatis printer internal; kalau tidak ada yang dikenali,
      // pakai perangkat ter-pairing pertama (pola yang dipakai app STO lama).
      _selected ??= _devices.where((d) => d.isBuiltIn).firstOrNull ??
          _devices.firstOrNull;
    } catch (e) {
      _error = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> connect(PrinterDevice device, {bool silent = false}) async {
    _busy = true;
    if (!silent) _error = null;
    notifyListeners();
    try {
      await _service.connect(device);
      _selected = device;
      await _prefs.setPrinter(device.address, device.name);
      return true;
    } catch (e) {
      if (!silent) _error = e.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Menyiapkan printer tanpa campur tangan operator: pakai printer tersimpan,
  /// kalau belum ada cari printer internal yang sudah ter-pairing dari pabrik.
  /// Dipanggil sebelum mencetak supaya operator tidak perlu buka menu Setting.
  Future<bool> ensureReady() async {
    if (isConnected) return true;

    if (_selected == null) {
      await refreshDevices();
    }
    final device = _selected;
    if (device == null) return false;

    return connect(device);
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    notifyListeners();
  }

  Future<void> forgetPrinter() async {
    await disconnect();
    await _prefs.clearPrinter();
    _selected = null;
    notifyListeners();
  }

  Future<void> setPaperSize(PaperSize size) async {
    _paperSize = size;
    await _prefs.setPaperSize(size);
    notifyListeners();
  }

  Future<void> setAutoConnect(bool value) async {
    _autoConnect = value;
    await _prefs.setAutoConnectPrinter(value);
    notifyListeners();
  }

  /// Menarik setelan printer dari server lalu menyimpannya sebagai cache.
  ///
  /// Kegagalannya sengaja didiamkan: printer harus tetap bisa dipakai saat
  /// jaringan mati, memakai angka yang terakhir diketahui.
  Future<void> muatSetelanServer() async {
    final api = _api;
    if (api == null) return;

    // NIK wajib: server menolak permintaan tanpa itu. Saat aplikasi baru
    // dibuka, layar Setting belum sempat mengisi [_nikPembaca] - jadi
    // diambil dari sesi tersimpan. Tanpa ini setelan hanya tersinkron kalau
    // seseorang kebetulan membuka Setting > Printer, dan dua handheld bisa
    // mencetak dengan jarak yang berbeda-beda tanpa ada yang sadar.
    final nik = await nikUntukSetelan();
    if (nik.isEmpty) return;

    try {
      final setelan = await api.fetchPrinterSetting(nik);
      if (setelan.isEmpty) return;

      final gap = int.tryParse(setelan['gap_antar_tag_dots'] ?? '');
      final feed = int.tryParse(setelan['feed_akhir_dots'] ?? '');

      if (gap != null) {
        _gapDots = gap.clamp(0, 255);
        await _prefs.setTagGapDots(_gapDots);
      }
      if (feed != null) {
        _feedDots = feed.clamp(0, 255);
        await _prefs.setPaperFeedDots(_feedDots);
      }
      _setelanDariServer = true;
      notifyListeners();
    } catch (_) {
      // Offline: pakai cache lokal, jangan ganggu operator dengan pesan.
    }
  }

  /// NIK yang dipakai saat menanyakan setelan ke server. Diisi layar Setting
  /// dan halaman yang tahu siapa yang sedang login.
  String? _nikPembaca;
  set nikPembaca(String? nik) => _nikPembaca = nik;

  /// NIK untuk permintaan setelan, dengan sesi tersimpan sebagai cadangan.
  ///
  /// Dipisah supaya bisa diuji: saat aplikasi baru dibuka, layar Setting belum
  /// sempat mengisi [_nikPembaca], dan permintaan tanpa NIK ditolak server -
  /// akibatnya setelan tidak pernah tersinkron dan dua handheld mencetak
  /// dengan jarak berbeda tanpa ada yang sadar.
  Future<String> nikUntukSetelan() async {
    final dari = _nikPembaca?.trim() ?? '';
    if (dari.isNotEmpty) return dari;
    return (await _prefs.readUser())?.nik.trim() ?? '';
  }

  /// Menyimpan setelan ke server (hanya admin yang diterima server).
  ///
  /// Melempar [ApiException] apa adanya supaya layar bisa menyebutkan
  /// alasannya - termasuk saat server menolak karena bukan admin.
  Future<void> simpanSetelanServer(String adminNik) async {
    final api = _api;
    if (api == null) return;

    await api.savePrinterSetting(adminNik, {
      'gap_antar_tag_dots': _gapDots,
      'feed_akhir_dots': _feedDots,
    });
    _setelanDariServer = true;
    notifyListeners();
  }

  Future<void> setFeedDots(int dots) async {
    _feedDots = dots.clamp(0, 255);
    await _prefs.setPaperFeedDots(_feedDots);
    notifyListeners();
  }

  Future<void> setGapDots(int dots) async {
    _gapDots = dots.clamp(0, 255);
    await _prefs.setTagGapDots(_gapDots);
    notifyListeners();
  }

  /// Mengirim penanda pendek + jarak maju [dots] tanpa mencetak tag utuh -
  /// dipakai Setting > Printer untuk menguji jarak sobek berkali-kali tanpa
  /// memboroskan kertas.
  Future<void> testFeed(int dots, {int gapDots = 0}) async {
    if (_selected == null) {
      throw PrinterException('Pilih printer dulu di menu Setting > Printer.');
    }
    await _service.testFeed(dots, gapDots: gapDots);
  }

  LabelDocument buildDocument(StoTag tag) =>
      LabelBuilder.build(tag, paper: _paperSize);

  PaperStatus _paperStatus = PaperStatus.unknown;

  /// Keadaan kertas terakhir yang diketahui - ditampilkan di preview.
  PaperStatus get paperStatus => _paperStatus;

  /// Menanyakan keadaan kertas ke printer. Hasilnya diingat supaya bisa
  /// ditampilkan tanpa bertanya ulang.
  Future<PaperStatus> refreshPaperStatus() async {
    _paperStatus = await _service.paperStatus();
    notifyListeners();
    return _paperStatus;
  }

  /// Mencetak satu tag. Melempar [PrinterException] bila gagal supaya
  /// pemanggil TIDAK menandai tag sebagai sudah dicetak.
  Future<void> printTag(StoTag tag, {bool isLastInBatch = true}) async {
    if (_selected == null) {
      throw PrinterException('Pilih printer dulu di menu Setting > Printer.');
    }
    final dokumen = buildDocument(tag);
    try {
      await _service.printDocument(
        dokumen,
        feedAtEnd: isLastInBatch,
        feedDots: _feedDots,
        gapDots: _gapDots,
      );
    } on PrinterException {
      // Jalur pabrikan menolak. Sekali saja pindah ke jalur cadangan lalu
      // ulangi - kalau tetap gagal, kesalahannya dilempar apa adanya supaya
      // tag tidak pernah ditandai sudah dicetak.
      if (!await _pindahCadangan()) rethrow;
      await _service.printDocument(
        dokumen,
        feedAtEnd: isLastInBatch,
        feedDots: _feedDots,
        gapDots: _gapDots,
      );
    }
  }

  /// Berpindah ke jalur printer cadangan. Mengembalikan false bila tidak ada
  /// cadangan atau sudah pernah pindah.
  Future<bool> _pindahCadangan() async {
    final buat = _cadangan;
    if (buat == null || _sudahPindahCadangan) return false;
    _sudahPindahCadangan = true;

    _service = buat();
    _selected = null;
    _devices = const [];
    notifyListeners();
    return ensureReady();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
