import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config/app_config.dart';
import 'box_grid_bitmap.dart';
import 'label_builder.dart';
import 'label_document.dart';
import 'printer_service.dart';

/// Printer termal ESC/POS lewat Bluetooth SPP.
///
/// Blueprint MPOS 332: printer internal umumnya sudah ter-pairing dan muncul
/// pada daftar bonded device dengan nama "InnerPrinter" / "BluePrint" /
/// "MPOS". Nama-nama itu dipakai untuk menandai perangkat internal
/// ([PrinterDevice.isBuiltIn]) supaya bisa dipilih otomatis.
class BluetoothPrinterService implements PrinterService {
  BluetoothPrinterService();

  static const List<String> builtInHints = [
    'innerprinter',
    'inner printer',
    'blueprint',
    'senraise',
    'mpos',
    'printer',
    'pos',
  ];

  /// Alamat semu yang dipakai banyak handheld POS (MPOS 332, Senraise H10,
  /// Sunmi, Telpo) untuk printer internal yang sudah ter-pairing dari pabrik.
  /// Perangkat ini sering tidak punya nama (null) sehingga tidak bisa dikenali
  /// dari namanya saja.
  static const String builtInAddress = '00:11:22:33:44:55';

  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  PrinterState _state = PrinterState.unknown;
  PrinterDevice? _device;

  @override
  PrinterState get state => _state;

  @override
  PrinterDevice? get currentDevice => _device;

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _printer.isOn ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Izin runtime yang diminta sebelum memakai printer.
  ///
  /// Selain BLUETOOTH_CONNECT/SCAN, **ACCESS_FINE_LOCATION wajib** ikut diminta:
  /// blue_thermal_printer menolak memanggil getBondedDevices bila ketiganya
  /// belum granted (lihat BlueThermalPrinterPlugin.getBondedDevices), sehingga
  /// daftar printer terlihat kosong walau printer internal sudah ter-pairing.
  ///
  /// Tidak melempar error di sini - biarkan panggilan aslinya yang gagal supaya
  /// pesan yang muncul sesuai kondisi nyata (mis. Bluetooth mati).
  @override
  Future<void> ensurePermissions() async {
    if (!Platform.isAndroid) return;
    try {
      final hasil = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ].request();

      // Android 12+ menolak getBondedDevices tanpa BLUETOOTH_CONNECT, dan
      // penolakannya tidak berupa error - daftarnya sekadar kosong. Jadi
      // keadaan izin dicatat, supaya layar bisa mengatakan sebab yang benar
      // alih-alih "printer tidak ditemukan".
      izinDitolak = hasil[Permission.bluetoothConnect]?.isGranted == false;
    } catch (_) {
      // Perangkat lama tidak mengenal izin baru - abaikan.
    }
  }

  /// true bila izin Bluetooth ditolak pada permintaan terakhir.
  bool izinDitolak = false;

  /// Bluetooth yang mati adalah sebab kegagalan yang paling sering di
  /// lapangan, dan pluginnya hanya melempar `java.io.IOException` tanpa
  /// keterangan. Diperiksa lebih dulu supaya operator tahu apa yang harus
  /// dilakukan.
  Future<void> _pastikanBluetoothHidup() async {
    if (!Platform.isAndroid) return;
    bool hidup;
    try {
      hidup = await _printer.isOn ?? false;
    } catch (_) {
      return; // tidak bisa ditanya - biarkan panggilan aslinya yang gagal
    }
    if (!hidup) {
      throw PrinterException(
        'Bluetooth perangkat sedang mati. Nyalakan Bluetooth lalu coba lagi - '
        'printer internal tersambung lewat Bluetooth.',
      );
    }
  }

  @override
  Future<List<PrinterDevice>> discoverDevices() async {
    await ensurePermissions();
    await _pastikanBluetoothHidup();
    try {
      // Catatan penting: blue_thermal_printer 1.2.3 punya bug - bila izin
      // BLUETOOTH_SCAN/CONNECT/ACCESS_FINE_LOCATION belum granted, plugin
      // meminta izin dengan requestCode 1 tetapi callback-nya hanya menangani
      // 1451, sehingga Future getBondedDevices TIDAK PERNAH selesai (UI
      // menggantung tanpa error). Izin sudah diminta lebih dulu di
      // ensurePermissions(); timeout ini jaring pengaman terakhir.
      final devices = await _printer.getBondedDevices().timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw PrinterException(
          'Printer tidak terbaca karena izin belum lengkap. Buka Setelan > '
          'Aplikasi > STO > Izin: aktifkan "Perangkat di sekitar" dan '
          'Lokasi (pilih "Lokasi tepat"), lalu coba lagi.',
        ),
      );
      final mapped = devices
          .map((d) {
            final address = d.address ?? '';
            final builtIn = _looksBuiltIn(d.name) || address == builtInAddress;
            final name = (d.name == null || d.name!.trim().isEmpty)
                ? (builtIn ? 'Printer Internal' : 'Tanpa nama')
                : d.name!;
            return PrinterDevice(
              name: name,
              address: address,
              isBuiltIn: builtIn,
            );
          })
          .where((d) => d.address.isNotEmpty)
          .toList();
      // Printer internal handheld ini kadang tidak muncul di daftar bonded
      // (namanya null dan pairing-nya dari pabrik). Alamatnya tetap sama, jadi
      // entrinya disediakan sendiri supaya operator tidak kehilangan printer
      // hanya karena daftar Bluetooth-nya tidak lengkap.
      if (!mapped.any((d) => d.address == builtInAddress)) {
        mapped.add(
          const PrinterDevice(
            name: 'Printer Internal',
            address: builtInAddress,
            isBuiltIn: true,
          ),
        );
      }

      // Printer internal ditaruh paling atas.
      mapped.sort((a, b) {
        if (a.isBuiltIn == b.isBuiltIn) return a.name.compareTo(b.name);
        return a.isBuiltIn ? -1 : 1;
      });
      return mapped;
    } on PrinterException {
      rethrow;
    } catch (e) {
      final message = '$e'.toLowerCase();
      if (message.contains('permission')) {
        throw PrinterException(
          'Izin Bluetooth/Lokasi belum diberikan. Buka Setelan > Aplikasi > '
          'STO > Izin, lalu aktifkan Perangkat di sekitar dan Lokasi.',
        );
      }
      throw PrinterException(
        'Gagal membaca daftar printer. Pastikan Bluetooth perangkat aktif. ($e)',
      );
    }
  }

  static bool _looksBuiltIn(String? name) {
    if (name == null) return false;
    final lower = name.toLowerCase();
    return builtInHints.any(lower.contains);
  }

  @override
  Future<void> connect(PrinterDevice device) async {
    await ensurePermissions();
    await _pastikanBluetoothHidup();
    _state = PrinterState.connecting;
    try {
      if (await _printer.isConnected ?? false) {
        await _printer.disconnect();
      }
      await _printer.connect(
        BluetoothDevice(device.name, device.address),
      );
      _device = device;
      _state = PrinterState.connected;
    } catch (e) {
      _state = PrinterState.error;
      throw PrinterException('Gagal menyambung ke ${device.name}: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _printer.disconnect();
    } catch (_) {
      // abaikan - koneksi mungkin memang sudah putus
    }
    _state = PrinterState.disconnected;
    _device = null;
  }

  Future<bool> get isConnected async {
    try {
      return await _printer.isConnected ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Menanyakan keadaan kertas dengan perintah real-time ESC/POS
  /// `DLE EOT 4` (0x10 0x04 0x04).
  ///
  /// Berbeda dari perintah cetak biasa, perintah ini dijawab printer lewat
  /// jalur balik SPP; jawabannya satu byte:
  /// - bit 2/3 menyala (0x0C) -> kertas hampir habis (roll near-end sensor),
  /// - bit 5/6 menyala (0x60) -> kertas habis,
  /// - selain itu kertas dianggap ada.
  ///
  /// Printer internal sebagian handheld tidak menjawab sama sekali. Karena itu
  /// hasilnya [PaperStatus.unknown] setelah 700 ms tanpa balasan - sengaja
  /// tidak dianggap "aman", supaya lapisan di atasnya bisa memilih jalur yang
  /// lebih hati-hati.
  @override
  Future<PaperStatus> paperStatus() async {
    if (!await isConnected) return PaperStatus.unknown;

    try {
      final jawaban = Completer<int?>();
      final langganan = _printer.onRead().listen((data) {
        if (jawaban.isCompleted) return;
        final bytes = data.codeUnits;
        jawaban.complete(bytes.isEmpty ? null : bytes.first);
      });

      await _printer.writeBytes(Uint8List.fromList([0x10, 0x04, 0x04]));

      final status = await jawaban.future
          .timeout(const Duration(milliseconds: 700), onTimeout: () => null);
      await langganan.cancel();

      if (status == null) return PaperStatus.unknown;
      if ((status & 0x60) != 0) return PaperStatus.out;
      if ((status & 0x0C) != 0) return PaperStatus.nearEnd;
      return PaperStatus.ok;
    } catch (_) {
      // Printer yang tidak mendukung writeBytes / jalur balik: jangan
      // menghalangi pencetakan, cukup mengaku tidak tahu.
      return PaperStatus.unknown;
    }
  }

  @override
  Future<void> printDocument(
    LabelDocument document, {
    bool feedAtEnd = true,
    int? feedDots,
    int? gapDots,
  }) async {
    if (!await isConnected) {
      final device = _device;
      if (device == null) {
        throw PrinterException(
          'Printer belum tersambung. Buka Setting > Printer.',
        );
      }
      await connect(device);
    }

    try {
      for (final element in document.elements) {
        switch (element) {
          case LabelText():
            await _writeLine(
              element.text,
              align: element.align,
              bold: element.bold,
              size: element.size,
            );
            break;
          case LabelKeyValue():
            await _writeLine(
              LabelBuilder.renderKeyValue(element, document.charPerLine),
              bold: element.bold,
            );
            break;
          case LabelDivider():
            await _writeLine(
              LabelBuilder.renderDivider(element, document.charPerLine),
            );
            break;
          case LabelQr():
            await _resetMode();
            await _printer.printQRcode(
              element.data,
              element.size,
              element.size,
              1,
            );
            break;
          case LabelBoxGrid():
            await _printBoxGrid(element, document);
            break;
          case LabelFeed():
            for (var i = 0; i < element.lines; i++) {
              await _printer.printNewLine();
            }
            break;
        }
      }
      await _resetMode();
      if (feedAtEnd) {
        await _majuSeperlunya(feedDots ?? feedAfterTagDots);
      } else {
        await _majuSeperlunya(gapDots ?? gapAntarTagDots);
      }
      // Beri jeda supaya buffer printer selesai sebelum tag berikutnya.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      _state = PrinterState.error;
      throw PrinterException('Gagal mencetak: $e');
    }
  }

  /// Kotak isian dicetak sebagai gambar supaya garisnya menyambung seperti di
  /// preview.
  ///
  /// Urutannya: perintah raster ESC/POS mentah -> `printImageBytes` -> teks.
  /// Raster didahulukan karena `printImageBytes` pada printer ini diterima
  /// tanpa error tetapi TIDAK menghasilkan apa pun di kertas - kotak isiannya
  /// hilang diam-diam, dan itu baru ketahuan setelah tag di tangan operator.
  Future<void> _printBoxGrid(LabelBoxGrid grid, LabelDocument document) async {
    final raster = await BoxGridBitmap.renderRaster(
      grid,
      widthDots: document.dots,
    );
    if (raster != null) {
      try {
        await _resetMode();
        await _printer.writeBytes(raster);
        return;
      } catch (_) {
        // lanjut ke jalur gambar plugin
      }
    }

    final png = await BoxGridBitmap.render(grid, widthDots: document.dots);
    if (png != null) {
      try {
        await _resetMode();
        await _printer.printImageBytes(png);
        return;
      } catch (_) {
        // lanjut ke jalur teks
      }
    }
    for (final line
        in LabelBuilder.renderBoxGrid(grid, document.charPerLine)) {
      await _writeLine(line);
    }
  }

  /// Memajukan kertas sejauh [dots], dibulatkan ke baris kosong terdekat.
  ///
  /// Sengaja TIDAK memakai `ESC J n` ("maju n titik"): printer handheld ini
  /// menerimanya tanpa error tetapi tidak menjalankannya - terbukti dari
  /// cetakan uji, mengubah nilainya dari 90 ke 32 lalu ke 0 tidak mengubah
  /// apa pun di kertas, dan jarak antar tag tetap nol. Baris kosong (LF)
  /// pasti dijalankan, karena badan tag sendiri dicetak baris demi baris.
  ///
  /// Nol berarti tidak mengirim apa pun - printer yang sudah maju sendiri di
  /// akhir cetakan tidak perlu ditambahi.
  Future<void> _majuSeperlunya(int dots) async {
    final baris = (dots / dotsPerLine).round();
    for (var i = 0; i < baris; i++) {
      await _printer.printNewLine();
    }
  }

  @override
  Future<void> testFeed(int dots, {int gapDots = 0}) async {
    if (!await isConnected) {
      final device = _device;
      if (device == null) {
        throw PrinterException(
          'Printer belum tersambung. Buka Setting > Printer.',
        );
      }
      await connect(device);
    }
    try {
      // Dua penanda dengan jarak antar tag di antaranya, lalu jarak akhir -
      // sekali cetak, kedua jarak langsung kelihatan dan bisa diukur.
      await _writeLine('---- TAG 1 ----', align: LabelAlign.center);
      await _resetMode();
      await _majuSeperlunya(gapDots);
      await _writeLine('---- TAG 2 ----', align: LabelAlign.center);
      await _resetMode();
      await _majuSeperlunya(dots);
    } catch (e) {
      _state = PrinterState.error;
      throw PrinterException('Gagal menguji jarak: $e');
    }
  }

  /// Menulis satu baris memakai perintah ESC/POS mentah.
  ///
  /// Kenapa tidak memakai `printCustom` bawaan plugin: pada ukuran 0 plugin
  /// mengirim `ESC ! 0x03` yang mengaktifkan FONT B (huruf kecil, ~42 kolom),
  /// sedangkan ukuran 1 memakai FONT A (~32 kolom). Campuran dua font membuat
  /// kolom "KEY : VALUE" dan kotak isian tidak sejajar di kertas. Di sini
  /// semua baris dikunci ke FONT A, tebal cukup memakai bit emphasized.
  Future<void> _writeLine(
    String text, {
    LabelAlign align = LabelAlign.left,
    bool bold = false,
    LabelTextSize size = LabelTextSize.normal,
  }) async {
    try {
      await _writeAlign(align);
      await _writeMode(_escMode(size, bold));
      await _printer.writeBytes(_encode('$text\n'));
    } catch (_) {
      // Printer/plugin yang tidak mendukung writeBytes tetap bisa mencetak
      // lewat jalur bawaan plugin.
      await _printer.printCustom(text, bold ? 1 : 0, _escAlign(align));
    }
  }

  /// Mengembalikan printer ke mode normal. Kegagalan di sini tidak boleh
  /// membatalkan pencetakan (printer yang tidak mendukung writeBytes tetap
  /// bisa mencetak lewat jalur cadangan printCustom).
  Future<void> _resetMode() async {
    try {
      await _writeMode(0x00);
    } catch (_) {
      // abaikan
    }
  }

  Future<void> _writeMode(int mode) =>
      _printer.writeBytes(Uint8List.fromList([0x1B, 0x21, mode]));

  Future<void> _writeAlign(LabelAlign align) => _printer.writeBytes(
        Uint8List.fromList([0x1B, 0x61, _escAlign(align)]),
      );

  /// ESC ! n - bit3 (0x08) tebal, bit4 (0x10) tinggi ganda,
  /// bit5 (0x20) lebar ganda, bit0 (0x01) font B.
  int _escMode(LabelTextSize size, bool bold) {
    var mode = bold ? 0x08 : 0x00;
    switch (size) {
      case LabelTextSize.small:
        mode |= 0x01; // font B - hanya untuk keterangan kecil
        break;
      case LabelTextSize.normal:
        break;
      case LabelTextSize.large:
        mode |= 0x30; // lebar + tinggi ganda
        break;
      case LabelTextSize.xlarge:
        mode |= 0x38; // lebar + tinggi ganda + tebal
        break;
    }
    return mode;
  }

  /// Printer termal memakai code page 1 byte - karakter di luar ASCII
  /// diganti '?' supaya tidak menghasilkan simbol acak.
  Uint8List _encode(String text) {
    final buffer = <int>[];
    for (final unit in text.codeUnits) {
      // Sisakan newline + rentang ASCII cetak; sisanya jadi '?'.
      final printable = unit == 0x0A || (unit >= 0x20 && unit <= 0x7E);
      buffer.add(printable ? unit : 0x3F);
    }
    return Uint8List.fromList(buffer);
  }

  /// 0 = kiri, 1 = tengah, 2 = kanan.
  int _escAlign(LabelAlign align) {
    switch (align) {
      case LabelAlign.left:
        return 0;
      case LabelAlign.center:
        return 1;
      case LabelAlign.right:
        return 2;
    }
  }
}
