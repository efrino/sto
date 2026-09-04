import '../../core/config/app_config.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/sto_tag.dart';
import 'label_document.dart';

/// Menyusun tata letak tag STO (58mm / 80mm).
///
/// Layout:
///   PT. MEKAR ARMADA JAYA
///   TAG STO - 02/09/2026 10.50 AM   <- judul + waktu cetak
///   ================================
///   STO260902-000123                <- besar, identitas unik
///   --------------------------------
///   PART NO  : 53801-BZ010
///   JOB NO   : JOB-2601
///   NAMA     : PANEL SIDE OUTER RH
///   CUST     : ADM / AYLA
///   AREA     : WAREHOUSE 1
///   STATUS   : FP                   <- FP / WIP
///   DICETAK  : A.10525              <- NIK yang mencetak
///   --------------------------------
///          [ QR: nomor tag ]
///   +--------------+--------------+
///   |Nama Hitung A |Nama Hitung B |
///   +--------------+--------------+
///   |Nama Catat A  |Nama Catat B  |
///   +--------------+--------------+
///
/// Tag berakhir tepat setelah kotak isian - tidak ada blok apa pun di bawahnya.
class LabelBuilder {
  LabelBuilder._();

  /// Lebar kolom judul pada baris "KEY : VALUE" (dipakai saat memenggal teks
  /// panjang maupun saat merender ke printer, supaya keduanya konsisten).
  static const int keyColumnWidth = 9;
  static const int keySeparatorWidth = 2; // ': '

  static LabelDocument build(
    StoTag tag, {
    required PaperSize paper,
    DateTime? printedAt,
  }) {
    final width = paper.charPerLine;
    // Tag yang dibatalkan tidak punya waktu cetak - jangan tampilkan jam
    // sekarang supaya preview di riwayat tidak menyesatkan.
    final stamp = printedAt ?? tag.printedAt;
    final judulWaktu = tag.status == TagStatus.cancelled && stamp == null
        ? '-'
        : Formatters.dateTimeAmPm(stamp ?? DateTime.now());

    return LabelDocument(
      charPerLine: width,
      dots: paper.dots,
      elements: [
        const LabelText(
          AppConfig.companyName,
          size: LabelTextSize.normal,
          align: LabelAlign.center,
          bold: true,
        ),
        LabelText('TAG STO - $judulWaktu', align: LabelAlign.center),
        const LabelDivider(char: '='),
        LabelText(
          tag.tagNo,
          // Huruf besar = lebar ganda pada ESC/POS (58mm hanya muat 16 karakter).
          // Nomor yang lebih panjang (mis. awalan offline) dicetak ukuran normal
          // supaya tidak terpotong / turun baris.
          size: tag.tagNo.length <= (width ~/ 2)
              ? LabelTextSize.large
              : LabelTextSize.normal,
          align: LabelAlign.center,
          bold: true,
        ),
        const LabelDivider(),
        LabelKeyValue('PART NO', tag.partNumber, bold: true),
        LabelKeyValue('JOB NO', tag.jobNumber),
        ..._wrapValue('NAMA', tag.partName, width),
        ..._wrapValue('CUST', '${tag.customer} / ${tag.model}', width),
        ..._wrapValue('AREA', tag.area, width),
        LabelKeyValue('STATUS', tag.partType, bold: true),
        LabelKeyValue('DICETAK', tag.createdBy, bold: true),
        // Catatan & penanda khusus ikut di blok atas, karena bagian bawah tag
        // harus berhenti tepat di kotak isian.
        if (tag.note != null && tag.note!.trim().isNotEmpty)
          ..._wrapValue('CATATAN', tag.note!.trim(), width),
        if (tag.status == TagStatus.cancelled)
          const LabelText(
            '*** TAG DIBATALKAN ***',
            align: LabelAlign.center,
            bold: true,
          ),
        if (tag.offlineSequence)
          const LabelText(
            '* nomor offline, menunggu sinkron',
            size: LabelTextSize.small,
          ),
        const LabelDivider(),
        LabelQr(tag.tagNo),
        // Kotak isian manual saat pelaksanaan STO - elemen terakhir pada tag.
        const LabelBoxGrid(
          titles: ['Nama Hitung A', 'Nama Hitung B', 'Nama Catat A', 'Nama Catat B'],
        ),
      ],
    );
  }

  /// Nilai panjang (nama part / catatan) dipecah agar tidak terpotong printer.
  static List<LabelElement> _wrapValue(String key, String value, int width) {
    final labelWidth = keyColumnWidth + keySeparatorWidth;
    final maxValue = (width - labelWidth).clamp(8, width);
    if (value.length <= maxValue) {
      return [LabelKeyValue(key, value)];
    }

    final words = value.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ('$current $word'.length <= maxValue) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);

    return [
      LabelKeyValue(key, lines.first),
      // Baris lanjutan sejajar dengan kolom nilai, tanpa judul & titik dua.
      for (final line in lines.skip(1))
        LabelKeyValue('', line, continuation: true),
    ];
  }

  /// Baris "KEY : VALUE" yang sudah dipadatkan sesuai lebar kertas.
  static String renderKeyValue(LabelKeyValue element, int width) {
    final prefix = element.continuation
        ? ' ' * (keyColumnWidth + keySeparatorWidth)
        : '${element.key.padRight(keyColumnWidth)}: ';
    final line = '$prefix${element.value}';
    return line.length <= width ? line : line.substring(0, width);
  }

  static String renderDivider(LabelDivider element, int width) =>
      element.char * width;

  /// Menggambar kotak isian sebagai baris-baris karakter, mis. untuk 32 kolom:
  ///
  ///   +---------------+--------------+
  ///   |Nama Hitung A  |Nama Hitung B |
  ///   |               |              |
  ///   +---------------+--------------+
  ///
  /// Hasilnya dipakai apa adanya baik di preview maupun di printer.
  static List<String> renderBoxGrid(LabelBoxGrid element, int width) {
    final columns = element.columns < 1 ? 1 : element.columns;
    final inner = width - (columns + 1);
    if (inner < columns * 4) return const [];

    final base = inner ~/ columns;
    final remainder = inner - (base * columns);
    final cellWidths = List<int>.generate(
      columns,
      (i) => base + (i < remainder ? 1 : 0),
    );

    final divider =
        '+${cellWidths.map((w) => '-' * w).join('+')}+';
    final blank = '|${cellWidths.map((w) => ' ' * w).join('|')}|';

    final lines = <String>[divider];
    for (var start = 0; start < element.titles.length; start += columns) {
      final rowTitles = <String>[];
      for (var col = 0; col < columns; col++) {
        final index = start + col;
        final title = index < element.titles.length ? element.titles[index] : '';
        final cellWidth = cellWidths[col];
        rowTitles.add(
          title.length > cellWidth
              ? title.substring(0, cellWidth)
              : title.padRight(cellWidth),
        );
      }
      lines.add('|${rowTitles.join('|')}|');
      for (var i = 0; i < element.rowHeight; i++) {
        lines.add(blank);
      }
      lines.add(divider);
    }
    return lines;
  }
}
