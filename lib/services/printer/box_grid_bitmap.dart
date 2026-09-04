import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'label_document.dart';

/// Menggambar kotak isian sebagai bitmap hitam-putih untuk dicetak.
///
/// Printer termal hanya punya karakter teks, sehingga tabel yang digambar
/// dengan `+ - |` keluar sebagai garis putus-putus. Dicetak sebagai gambar,
/// garisnya menyambung persis seperti yang terlihat di preview - jalur yang
/// sama sudah terbukti dipakai untuk QR code.
class BoxGridBitmap {
  BoxGridBitmap._();

  /// Tinggi baris judul di dalam kotak (dot).
  static const double _titleHeight = 30;

  /// Tinggi satu baris kosong untuk tulisan tangan (dot).
  static const double _writingLine = 26;

  static const double _borderWidth = 2;
  static const double _fontSize = 20;

  /// Mengembalikan PNG siap kirim ke `printImageBytes`,
  /// atau null bila menggambar gagal (pemanggil memakai jalur teks cadangan).
  static Future<Uint8List?> render(
    LabelBoxGrid grid, {
    required int widthDots,
  }) =>
      _gambar(grid, widthDots: widthDots, format: ui.ImageByteFormat.png);

  /// Kotak isian sebagai perintah raster ESC/POS `GS v 0`.
  ///
  /// Ini jalur utamanya. Alasannya nyata: `printImageBytes` milik plugin
  /// mengirim gambar lewat perintah yang tidak dikenali sebagian printer -
  /// perintahnya diterima tanpa error, tetapi tidak ada yang keluar di kertas
  /// sehingga kotak isian hilang diam-diam. Perintah raster di bawah ini
  /// dikirim lewat `writeBytes`, jalur yang sama dengan teks tag.
  static Future<Uint8List?> renderRaster(
    LabelBoxGrid grid, {
    required int widthDots,
  }) async {
    // Lebar dibulatkan ke kelipatan 8: satu byte raster = 8 titik.
    final lebar = (widthDots ~/ 8) * 8;
    if (lebar <= 0) return null;

    final rgba = await _gambar(
      grid,
      widthDots: lebar,
      format: ui.ImageByteFormat.rawRgba,
    );
    if (rgba == null) return null;

    final bytePerBaris = lebar ~/ 8;
    final tinggi = rgba.lengthInBytes ~/ (lebar * 4);
    if (tinggi <= 0) return null;

    final data = Uint8List(bytePerBaris * tinggi);
    for (var y = 0; y < tinggi; y++) {
      for (var x = 0; x < lebar; x++) {
        final i = (y * lebar + x) * 4;
        // Ambang 128 pada komponen merah sudah cukup - gambarnya memang
        // hitam-putih, tanpa warna antara.
        if (rgba[i] < 128) {
          data[y * bytePerBaris + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }

    return Uint8List.fromList([
      0x1B, 0x61, 0x00, // rata kiri: kotak memenuhi lebar kertas
      0x1D, 0x76, 0x30, 0x00,
      bytePerBaris & 0xFF, (bytePerBaris >> 8) & 0xFF,
      tinggi & 0xFF, (tinggi >> 8) & 0xFF,
      ...data,
    ]);
  }

  static Future<Uint8List?> _gambar(
    LabelBoxGrid grid, {
    required int widthDots,
    required ui.ImageByteFormat format,
  }) async {
    try {
      final columns = grid.columns < 1 ? 1 : grid.columns;
      final rows = (grid.titles.length / columns).ceil();
      if (rows == 0) return null;

      final width = widthDots.toDouble();
      final rowHeight = _titleHeight + (_writingLine * grid.rowHeight);
      final height = rowHeight * rows + _borderWidth;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        Rect.fromLTWH(0, 0, width, height),
      );

      // Latar putih: rasterizer printer menganggap piksel terang = tidak dicetak.
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = const Color(0xFFFFFFFF),
      );

      final border = Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _borderWidth;

      final cellWidth = (width - _borderWidth) / columns;
      final half = _borderWidth / 2;

      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < columns; col++) {
          final index = row * columns + col;
          final rect = Rect.fromLTWH(
            half + (cellWidth * col),
            half + (rowHeight * row),
            cellWidth,
            rowHeight,
          );
          canvas.drawRect(rect, border);

          final title = index < grid.titles.length ? grid.titles[index] : '';
          if (title.isEmpty) continue;

          final painter = TextPainter(
            text: TextSpan(
              text: title,
              style: const TextStyle(
                color: Color(0xFF000000),
                fontSize: _fontSize,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            maxLines: 1,
            ellipsis: '…',
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: cellWidth - 12);

          painter.paint(
            canvas,
            Offset(rect.left + 6, rect.top + 5),
          );
        }
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(width.round(), height.round());
      final data = await image.toByteData(format: format);
      picture.dispose();
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
