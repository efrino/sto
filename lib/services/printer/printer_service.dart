import 'label_document.dart';

/// Perangkat printer yang bisa dipilih operator.
class PrinterDevice {
  const PrinterDevice({
    required this.name,
    required this.address,
    this.isBuiltIn = false,
  });

  final String name;
  final String address;

  /// true bila terdeteksi sebagai printer internal perangkat
  /// (Blueprint MPOS 332 biasanya muncul sebagai "InnerPrinter").
  final bool isBuiltIn;

  @override
  bool operator ==(Object other) =>
      other is PrinterDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

enum PrinterState { unknown, disconnected, connecting, connected, error }

/// Keadaan kertas menurut printer.
///
/// [unknown] penting dibedakan dari [ok]: printer internal pada sebagian
/// handheld tidak menjawab permintaan status sama sekali. "Tidak tahu" tidak
/// boleh diperlakukan sebagai "aman", karena di situlah cetak senyap terjadi -
/// data bilang tercetak padahal kertasnya habis.
enum PaperStatus {
  ok('Kertas tersedia'),
  nearEnd('Kertas hampir habis'),
  out('Kertas habis'),
  unknown('Status kertas tidak diketahui');

  const PaperStatus(this.label);
  final String label;

  bool get bolehCetak => this != PaperStatus.out;
}

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Kontrak printer. Implementasi:
/// - [BluetoothPrinterService] : printer internal MPOS 332 (ESC/POS via SPP)
/// - [MockPrinterService]      : mode simulasi untuk pengembangan di emulator
///
/// Bila nanti Blueprint menyediakan SDK khusus (AIDL/JNI), cukup tambah
/// implementasi baru di sini tanpa mengubah halaman preview.
abstract class PrinterService {
  PrinterState get state;

  /// Meminta izin runtime yang dibutuhkan jalur printer ini.
  ///
  /// Dipanggil sejak splash, saat layar masih diam: kalau dialog izin baru
  /// muncul di tengah operator menekan Cetak, ia sudah telanjur mengira
  /// printernya rusak. Jalur yang tidak butuh izin membiarkannya kosong.
  Future<void> ensurePermissions() async {}

  PrinterDevice? get currentDevice;

  Future<bool> isAvailable();

  Future<List<PrinterDevice>> discoverDevices();

  Future<void> connect(PrinterDevice device);

  Future<void> disconnect();

  /// Mencetak satu lembar tag. Harus melempar [PrinterException] bila gagal,
  /// karena pemanggilnya baru menandai tag sebagai "sudah cetak" jika sukses.
  ///
  /// [feedAtEnd] disetel false untuk tag sebelum tag terakhir dalam satu batch.
  /// [feedDots] jarak maju TAMBAHAN setelah tag terakhir, [gapDots] jarak
  /// antar tag di tengah batch (keduanya titik ESC/POS; null = bawaan).
  ///
  /// Keduanya datang dari pengaturan admin, bukan konstanta tetap:
  /// kalibrasi dot-ke-mm berbeda antar printer klon, dan sebagian printer
  /// sudah memajukan kertasnya sendiri di akhir cetakan.
  Future<void> printDocument(
    LabelDocument document, {
    bool feedAtEnd = true,
    int? feedDots,
    int? gapDots,
  });

  /// Mencetak dua penanda pendek berjarak [gapDots], lalu memajukan kertas
  /// sejauh [dots] - dipakai Setting > Printer untuk menguji jarak antar tag
  /// dan jarak sobek sekaligus, tanpa mencetak tag utuh.
  Future<void> testFeed(int dots, {int gapDots = 0});

  /// Menanyakan keadaan kertas ke printer (ESC/POS real-time status).
  ///
  /// Dipanggil SEBELUM mencetak. Printer yang tidak menjawab mengembalikan
  /// [PaperStatus.unknown] - bukan error, tapi juga bukan jaminan aman.
  Future<PaperStatus> paperStatus();
}
