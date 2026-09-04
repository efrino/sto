import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import 'box_grid_bitmap.dart';
import 'label_builder.dart';
import 'label_document.dart';
import 'printer_service.dart';

/// Printer internal handheld lewat service pabrikan (SRPrinter).
///
/// Printernya duduk di `/dev/ttyS1` dan dibungkus service sistem
/// `recieptservice.com.recieptservice`; "InnerPrinter" yang muncul di daftar
/// Bluetooth hanyalah jembatan SPP buatan pabrikan. Lewat jalur asli ini:
///
/// - tidak perlu izin maupun pemasangan Bluetooth sama sekali,
/// - keadaan kertas datang dari driver, bukan tebakan `DLE EOT` yang sering
///   tidak dijawab jembatan SPP - itulah sumber antrean cetak yang tertahan
///   saat kertas habis.
///
/// Susunan AIDL pabrikan tidak bisa dibaca ulang dari APK-nya (sudah
/// di-obfuscate), jadi kelas ini memperlakukan setiap panggilan sebagai
/// "coba dulu": begitu ada yang gagal, [siap] menjadi false dan pemanggil
/// kembali memakai jalur Bluetooth yang sudah terbukti.
class VendorPrinterService implements PrinterService {
  VendorPrinterService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('sto_prep/printer_vendor');

  final MethodChannel _channel;

  static const PrinterDevice perangkat = PrinterDevice(
    name: 'Printer internal (service pabrikan)',
    address: 'vendor:recieptservice',
    isBuiltIn: true,
  );

  PrinterState _state = PrinterState.unknown;
  bool _gagalPermanen = false;

  @override
  PrinterState get state => _state;

  @override
  PrinterDevice? get currentDevice =>
      _state == PrinterState.connected ? perangkat : null;

  /// true bila service pabrikan terpasang dan belum pernah menolak perintah.
  Future<bool> get siap async => !_gagalPermanen && await isAvailable();

  @override
  Future<bool> isAvailable() async {
    if (_gagalPermanen) return false;
    try {
      return await _channel.invokeMethod<bool>('tersedia') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<PrinterDevice>> discoverDevices() async =>
      await isAvailable() ? const [perangkat] : const [];

  @override
  Future<void> connect(PrinterDevice device) async {
    _state = PrinterState.connecting;
    final ok = await _panggil<bool>('sambung') ?? false;
    _state = ok ? PrinterState.connected : PrinterState.error;
    if (!ok) {
      throw PrinterException(
        'Service printer pabrikan menolak permintaan sambung.',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    await _panggil<bool>('putus');
    _state = PrinterState.disconnected;
  }

  @override
  Future<PaperStatus> paperStatus() async {
    final kode = await _panggil<int>('status');
    if (kode == null) return PaperStatus.unknown;

    // Kode status pabrikan: 0 = siap. Nilai lain menandakan gangguan; yang
    // paling sering di lapangan adalah kertas habis, dan itu ditangani sama
    // seperti kertas habis - pencetakan dihentikan sebelum tag ditandai.
    return kode == 0 ? PaperStatus.ok : PaperStatus.out;
  }

  @override
  Future<void> printDocument(
    LabelDocument document, {
    bool feedAtEnd = true,
    int? feedDots,
    int? gapDots,
  }) async {
    if (_state != PrinterState.connected) {
      await connect(perangkat);
    }

    for (final element in document.elements) {
      switch (element) {
        case LabelBoxGrid():
          // Kotak isian dikirim sebagai raster ESC/POS lewat jalur mentah -
          // sama seperti jalur Bluetooth. Jalur "cetak gambar" milik pabrikan
          // sengaja tidak dipakai: perintah gambar yang tidak dikenali
          // diterima tanpa error tetapi tidak menghasilkan apa pun di kertas.
          final raster = await BoxGridBitmap.renderRaster(
            element,
            widthDots: document.dots,
          );
          if (raster != null) {
            await _wajib('cetakRaw', {'data': raster});
          }
        case LabelText():
          await _teks(
            element.text,
            align: element.align,
            bold: element.bold,
            size: element.size,
          );
        case LabelKeyValue():
          await _teks(
            LabelBuilder.renderKeyValue(element, document.charPerLine),
            bold: element.bold,
          );
        case LabelDivider():
          await _teks(
            LabelBuilder.renderDivider(element, document.charPerLine),
          );
        case LabelQr():
          await _wajib('cetakRaw', {'data': _qr(element)});
        case LabelFeed():
          await _wajib('majuBaris', {'baris': element.lines});
      }
    }
    await _maju(
      feedAtEnd ? (feedDots ?? feedAfterTagDots) : (gapDots ?? gapAntarTagDots),
    );
  }

  /// Memajukan kertas sejauh [dots], dibulatkan ke baris kosong terdekat.
  ///
  /// Sama seperti jalur Bluetooth: `ESC J` tidak dipakai karena printer ini
  /// mengabaikannya. Yang dipakai adalah maju-baris, perintah yang pasti
  /// dijalankan.
  Future<void> _maju(int dots) async {
    final baris = (dots / dotsPerLine).round();
    if (baris <= 0) return;
    await _wajib('majuBaris', {'baris': baris});
  }

  @override
  Future<void> testFeed(int dots, {int gapDots = 0}) async {
    if (_state != PrinterState.connected) {
      await connect(perangkat);
    }
    await _teks('---- TAG 1 ----', align: LabelAlign.center);
    await _maju(gapDots);
    await _teks('---- TAG 2 ----', align: LabelAlign.center);
    await _maju(dots);
  }

  /// Satu baris teks beserta mode ESC/POS-nya - bentuknya sama persis dengan
  /// jalur Bluetooth, jadi tata letak tag tidak ditulis dua kali.
  Future<void> _teks(
    String teks, {
    LabelAlign align = LabelAlign.left,
    bool bold = false,
    LabelTextSize size = LabelTextSize.normal,
  }) async {
    var mode = bold ? 0x08 : 0x00;
    switch (size) {
      case LabelTextSize.small:
        mode |= 0x01;
      case LabelTextSize.normal:
        break;
      case LabelTextSize.large:
        mode |= 0x10;
      case LabelTextSize.xlarge:
        mode |= 0x30;
    }

    final perataan = switch (align) {
      LabelAlign.left => 0,
      LabelAlign.center => 1,
      LabelAlign.right => 2,
    };

    final data = <int>[
      0x1B, 0x61, perataan,
      0x1B, 0x21, mode,
      ...teks.codeUnits,
      0x0A,
      0x1B, 0x21, 0x00,
    ];
    await _wajib('cetakRaw', {'data': Uint8List.fromList(data)});
  }

  /// QR lewat perintah GS ( k (model 2) - jalur pabrikan menerima ESC/POS
  /// mentah, jadi tidak perlu bergantung pada helper plugin Bluetooth.
  Uint8List _qr(LabelQr qr) {
    final data = qr.data.codeUnits;
    final panjang = data.length + 3;
    return Uint8List.fromList([
      0x1B, 0x61, 0x01,
      0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, qr.size,
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31,
      0x1D, 0x28, 0x6B, panjang & 0xFF, (panjang >> 8) & 0xFF, 0x31, 0x50, 0x30,
      ...data,
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30,
      0x1B, 0x61, 0x00,
    ]);
  }

  Future<T?> _panggil<T>(String metode, [Map<String, dynamic>? argumen]) async {
    if (_gagalPermanen) return null;
    try {
      return await _channel.invokeMethod<T>(metode, argumen);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      _gagalPermanen = true;
      return null;
    }
  }

  /// Perintah yang hasilnya menentukan sah/tidaknya satu lembar tag.
  ///
  /// Kegagalannya dilempar - pemanggil TIDAK boleh menandai tag sebagai sudah
  /// dicetak hanya karena perintahnya terkirim.
  Future<void> _wajib(String metode, Map<String, dynamic> argumen) async {
    final ok = await _panggil<bool>(metode, argumen) ?? false;
    if (ok) return;

    _gagalPermanen = true;
    _state = PrinterState.error;
    throw PrinterException(
      'Printer internal menolak perintah "$metode". Aplikasi kembali memakai '
      'jalur Bluetooth (InnerPrinter).',
    );
  }
}
