import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/services/printer/box_grid_bitmap.dart';
import 'package:sto_prep/services/printer/label_document.dart';

/// Kotak isian dicetak sebagai gambar (garis menyambung), bukan karakter
/// `+ - |` yang di kertas terlihat putus-putus.
void main() {
  const grid = LabelBoxGrid(
    titles: ['Nama Hitung A', 'Nama Hitung B', 'Nama Catat A', 'Nama Catat B'],
  );

  testWidgets('menghasilkan PNG selebar kertas 58mm', (tester) async {
    Uint8List? png;
    await tester.runAsync(() async {
      png = await BoxGridBitmap.render(grid, widthDots: 384);
    });

    expect(png, isNotNull, reason: 'gagal menggambar kotak isian');
    // Signature PNG.
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);

    // Lebar & tinggi tersimpan pada header IHDR (big endian, offset 16..23).
    final bytes = ByteData.sublistView(png!);
    expect(bytes.getUint32(16), 384);
    expect(bytes.getUint32(20), greaterThan(100));

    // Simpan sebagai rujukan visual tim (dibuka manual bila layout diubah).
    File('test/goldens/box_grid_print.png').writeAsBytesSync(png!);
  });

  testWidgets('raster ESC/POS berukuran sesuai kertas dan berisi titik hitam',
      (tester) async {
    Uint8List? raster;
    await tester.runAsync(() async {
      raster = await BoxGridBitmap.renderRaster(grid, widthDots: 384);
    });

    expect(raster, isNotNull, reason: 'gagal membuat raster kotak isian');

    // 3 byte perataan + 4 byte perintah GS v 0 + 4 byte ukuran = 11 byte awal.
    expect(raster!.sublist(0, 3), [0x1B, 0x61, 0x00]);
    expect(raster!.sublist(3, 7), [0x1D, 0x76, 0x30, 0x00]);

    final bytePerBaris = raster![7] | (raster![8] << 8);
    final tinggi = raster![9] | (raster![10] << 8);
    expect(bytePerBaris, 384 ~/ 8);
    expect(tinggi, greaterThan(100));
    expect(raster!.length, 11 + (bytePerBaris * tinggi));

    // Kalau ambang hitam-putihnya terbalik, seluruh isinya nol dan kertas
    // keluar kosong - persis kegagalan yang membuat kotak isian hilang.
    final adaTitik = raster!.sublist(11).any((b) => b != 0);
    expect(adaTitik, isTrue, reason: 'raster kosong, tidak ada yang tercetak');
  });

  testWidgets('lebar mengikuti ukuran kertas 80mm', (tester) async {
    Uint8List? png;
    await tester.runAsync(() async {
      png = await BoxGridBitmap.render(grid, widthDots: 576);
    });

    expect(png, isNotNull);
    expect(ByteData.sublistView(png!).getUint32(16), 576);
  });
}
