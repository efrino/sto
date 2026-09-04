import 'dart:developer' as developer;

import 'label_builder.dart';
import 'label_document.dart';
import 'printer_service.dart';

/// Printer simulasi: dipakai di emulator / saat perangkat MPOS belum ada.
/// Hasil cetak ditulis ke log supaya layout tetap bisa diperiksa.
class MockPrinterService implements PrinterService {
  PrinterState _state = PrinterState.disconnected;
  PrinterDevice? _device;

  static const PrinterDevice simulator = PrinterDevice(
    name: 'Simulasi Printer (MPOS 332)',
    address: '00:00:00:00:00:00',
    isBuiltIn: true,
  );

  @override
  PrinterState get state => _state;

  @override
  PrinterDevice? get currentDevice => _device;

  @override
  Future<void> ensurePermissions() async {}

  @override
  Future<bool> isAvailable() async => true;

  /// Dipakai halaman Setting untuk melatih alur kertas habis tanpa printer.
  PaperStatus statusKertas = PaperStatus.ok;

  @override
  Future<PaperStatus> paperStatus() async => statusKertas;

  @override
  Future<List<PrinterDevice>> discoverDevices() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [simulator];
  }

  @override
  Future<void> connect(PrinterDevice device) async {
    _state = PrinterState.connecting;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _device = device;
    _state = PrinterState.connected;
  }

  @override
  Future<void> disconnect() async {
    _device = null;
    _state = PrinterState.disconnected;
  }

  @override
  Future<void> printDocument(
    LabelDocument document, {
    bool feedAtEnd = true,
    int? feedDots,
    int? gapDots,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final buffer = StringBuffer('\n--- SIMULASI CETAK ---\n');
    for (final element in document.elements) {
      switch (element) {
        case LabelText():
          buffer.writeln(element.text);
          break;
        case LabelKeyValue():
          buffer.writeln(
            LabelBuilder.renderKeyValue(element, document.charPerLine),
          );
          break;
        case LabelDivider():
          buffer.writeln(LabelBuilder.renderDivider(element, document.charPerLine));
          break;
        case LabelQr():
          buffer.writeln('[QR] ${element.data}');
          break;
        case LabelBoxGrid():
          for (final line
              in LabelBuilder.renderBoxGrid(element, document.charPerLine)) {
            buffer.writeln(line);
          }
          break;
        case LabelFeed():
          buffer.writeln('');
          break;
      }
    }
    developer.log(buffer.toString(), name: 'MockPrinter');
  }

  @override
  Future<void> testFeed(int dots, {int gapDots = 0}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    developer.log(
      '--- UJI JARAK: antar tag $gapDots titik, akhir $dots titik ---',
      name: 'MockPrinter',
    );
  }
}
