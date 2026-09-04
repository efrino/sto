/// Representasi netral dari satu lembar tag.
///
/// Dokumen yang sama dipakai dua kali:
/// - dirender ke layar sebagai PREVIEW (features/preview/widgets/label_paper.dart)
/// - dikirim ke printer sebagai perintah ESC/POS (bluetooth_printer_service.dart)
///
/// Dengan begitu apa yang dilihat operator = apa yang keluar dari printer.
enum LabelAlign { left, center, right }

enum LabelTextSize { small, normal, large, xlarge }

sealed class LabelElement {
  const LabelElement();
}

class LabelText extends LabelElement {
  const LabelText(
    this.text, {
    this.size = LabelTextSize.normal,
    this.align = LabelAlign.left,
    this.bold = false,
  });

  final String text;
  final LabelTextSize size;
  final LabelAlign align;
  final bool bold;
}

/// Baris "KEY : VALUE".
class LabelKeyValue extends LabelElement {
  const LabelKeyValue(
    this.key,
    this.value, {
    this.bold = false,
    this.continuation = false,
  });

  final String key;
  final String value;
  final bool bold;

  /// true = baris lanjutan dari nilai sebelumnya: kolom judul dan titik dua
  /// dikosongkan, tetapi nilainya tetap sejajar dengan baris di atasnya.
  final bool continuation;
}

class LabelDivider extends LabelElement {
  const LabelDivider({this.char = '-'});
  final String char;
}

class LabelQr extends LabelElement {
  /// Ukuran bitmap QR dalam piksel printer. Nilai kecil juga memperkecil
  /// quiet zone bawaan ZXing, sehingga jaraknya ke kotak isian tidak melebar.
  const LabelQr(this.data, {this.size = 180});
  final String data;
  final int size;
}

class LabelFeed extends LabelElement {
  const LabelFeed([this.lines = 1]);
  final int lines;
}

/// Kotak isian (tanda tangan / hitungan manual) yang disusun beberapa kolom.
///
/// Digambar memakai karakter ASCII supaya hasil di printer termal sama persis
/// dengan preview - printer ESC/POS tidak bisa menggambar kotak sungguhan
/// tanpa mode grafis.
class LabelBoxGrid extends LabelElement {
  const LabelBoxGrid({
    required this.titles,
    this.columns = 2,
    this.rowHeight = 3,
  });

  /// Judul tiap kotak, dibaca kiri ke kanan lalu turun ke baris berikutnya.
  final List<String> titles;
  final int columns;

  /// Jumlah baris kosong di dalam kotak (ruang tulis tangan).
  final int rowHeight;
}

class LabelDocument {
  const LabelDocument({
    required this.elements,
    required this.charPerLine,
    this.dots = 384,
  });

  final List<LabelElement> elements;
  final int charPerLine;

  /// Lebar area cetak dalam titik - dipakai untuk elemen yang dicetak
  /// sebagai gambar (kotak isian).
  final int dots;
}
