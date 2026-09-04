import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sto_prep/core/config/app_config.dart';
import 'package:sto_prep/data/models/part_item.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/services/printer/label_builder.dart';
import 'package:sto_prep/services/printer/label_document.dart';
import 'package:sto_prep/services/sequence/tag_sequence_service.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('id'));

  group('Nomor tag', () {
    test('prefix harian memakai pola STOyyMMdd', () {
      final prefix = TagSequenceService.todayPrefix(DateTime(2026, 9, 2));
      expect(prefix, 'STO260902');
    });

    test('nomor tag diberi padding sesuai konfigurasi', () {
      final tagNo = TagSequenceService.formatTagNo('STO260902', 123);
      expect(tagNo, 'STO260902-000123');
      expect(tagNo.split('-').last.length, AppConfig.sequencePadding);
    });
  });

  group('Batas daftar part', () {
    test('pencarian ke server dibatasi, tidak menarik seluruh master', () {
      // Master berisi 6.508 baris. Menariknya sekaligus membuat handheld
      // tertahan lama, dan operator tetap tidak akan membaca semuanya.
      expect(AppConfig.partSearchLimit, lessThanOrEqualTo(100));
      expect(AppConfig.partSearchLimit, greaterThanOrEqualTo(20));
    });

    test('cache per perangkat juga dibatasi', () {
      expect(AppConfig.partCacheLimit, lessThan(6508));
      expect(AppConfig.partCacheLimit, greaterThanOrEqualTo(500));
    });
  });

  group('Jarak kertas antar tag', () {
    test('tag ditutup satu baris saja, sisanya diatur printer', () {
      final dokumen = LabelBuilder.build(
        StoTag.fromPart(
          part: const PartItem(
            partNumber: '5070A592',
            jobNumber: 'SLC68',
            partName: 'BRACKET NO.2 BODY MOUNTING RH',
            customer: 'MMKI',
            model: 'SL',
            area: 'IFPD',
            location: '-',
            partType: 'FP',
          ),
          tagNo: 'STO260903-58',
          sequence: 58,
          batchId: 'B1',
          createdBy: 'M.9276',
          createdAt: DateTime(2026, 9, 3, 20, 16),
        ),
        paper: PaperSize.mm58,
      );

      // Tag berakhir tepat di kotak isian agar hemat kertas;
      // sisa jarak maju diatur oleh printer lewat feedAfterTagDots.
      final lastElement = dokumen.elements.last;
      expect(lastElement, isA<LabelBoxGrid>());
    });

    test('tidak menambah jarak sendiri di akhir cetakan', () {
      // Printer handheld ini sudah maju sendiri saat aliran data berhenti.
      // Menambahkan jarak di atas itu membuat ekor tag kepanjangan sekaligus
      // memperlebar kepala kosong cetakan berikutnya - dua keluhan yang
      // muncul bersamaan di lapangan.
      expect(feedAfterTagDots, 0);
    });

    test('antar tag dalam satu batch tetap diberi jarak gunting', () {
      // Jarak ini diwujudkan sebagai baris kosong, bukan perintah maju per
      // titik - printer handheld mengabaikan `ESC J`. Karena itu nilainya
      // harus cukup besar untuk membulat ke MINIMAL satu baris; 28 titik
      // sempat membulat ke 1 baris dan di kertas masih terlihat menempel.
      final baris = (gapAntarTagDots / dotsPerLine).round();
      expect(baris, greaterThanOrEqualTo(2),
          reason: 'kurang dari 2 baris tidak terlihat sebagai jarak gunting');
      expect(baris, lessThanOrEqualTo(4), reason: 'jangan boros kertas');
    });
  });

  group('Status tag', () {
    final tag = StoTag.fromPart(
      part: const PartItem(
        partNumber: '53801-BZ010',
        jobNumber: 'JOB-2601',
        partName: 'PANEL SIDE OUTER RH YANG NAMANYA SANGAT PANJANG SEKALI',
        customer: 'ADM',
        model: 'AYLA',
        area: 'WAREHOUSE 1',
        location: 'RAK A-01',
        partType: 'WIP',
      ),
      tagNo: 'STO260902-000001',
      sequence: 1,
      batchId: 'BATCH-1',
      createdBy: '11223344',
      createdAt: DateTime(2026, 9, 2, 7, 45),
    );

    test('tag yang belum tercetak boleh dicetak, belum boleh diajukan batal',
        () {
      expect(tag.isPrintable, isTrue);
      expect(tag.canRequestCancel, isFalse);
      expect(tag.canBeCancelledByAdmin, isFalse);
    });

    test('tag yang sudah dicetak tidak boleh dicetak lagi', () {
      final printed = tag.copyWith(
        status: TagStatus.printed,
        printedAt: DateTime(2026, 9, 2, 7, 46),
      );
      expect(printed.isPrintable, isFalse);
      // Operator boleh mengajukan, admin boleh langsung membatalkan.
      expect(printed.canRequestCancel, isTrue);
      expect(printed.canBeCancelledByAdmin, isTrue);
    });

    test('tag yang dibatalkan tidak bisa dicetak maupun dibatalkan ulang', () {
      final cancelled = tag.copyWith(
        status: TagStatus.cancelled,
        cancelReason: 'Mispart',
      );
      expect(cancelled.isPrintable, isFalse);
      expect(cancelled.canRequestCancel, isFalse);
      expect(cancelled.canBeCancelledByAdmin, isFalse);
    });

    test('dokumen cetak memuat nomor tag dan QR berisi nomor yang sama', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );

      expect(doc.charPerLine, 32);

      final texts = doc.elements.whereType<LabelText>().map((e) => e.text);
      expect(texts, contains(tag.tagNo));

      final qr = doc.elements.whereType<LabelQr>().single;
      expect(qr.data, tag.tagNo);

      final keys = doc.elements.whereType<LabelKeyValue>().map((e) => e.key);
      expect(keys, containsAll(['PART NO', 'JOB NO', 'STATUS', 'DICETAK']));
      // Lokasi & qty sudah tidak dicetak lagi.
      expect(keys, isNot(contains('LOKASI')));
      expect(keys, isNot(contains('QTY')));
    });

    test('baris STATUS memuat FP/WIP dan DICETAK memuat NIK', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );
      final rows = {
        for (final e in doc.elements.whereType<LabelKeyValue>()) e.key: e.value,
      };
      expect(rows['STATUS'], 'WIP');
      expect(rows['DICETAK'], tag.createdBy);
    });

    test('kotak isian 2x2 pas di lebar kertas', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );
      final grid = doc.elements.whereType<LabelBoxGrid>().single;
      expect(
        grid.titles,
        ['Nama Hitung A', 'Nama Hitung B', 'Nama Catat A', 'Nama Catat B'],
      );

      final lines = LabelBuilder.renderBoxGrid(grid, doc.charPerLine);
      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line.length, doc.charPerLine);
      }
      expect(lines.first, startsWith('+'));
      expect(lines.any((l) => l.contains('Nama Hitung A')), isTrue);
      expect(lines.any((l) => l.contains('Nama Catat B')), isTrue);
    });

    test('footer IT Department dan catatan cetak 1x sudah dihapus', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );
      final texts = doc.elements.whereType<LabelText>().map((e) => e.text);
      expect(texts.any((t) => t.contains('IT Department')), isFalse);
      expect(texts.any((t) => t.contains('dicetak 1x')), isFalse);
    });

    test('judul memuat TAG STO dan waktu cetak', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
        printedAt: DateTime(2026, 9, 2, 10, 50),
      );
      final judul = doc.elements
          .whereType<LabelText>()
          .firstWhere((e) => e.text.startsWith('TAG STO'));
      expect(judul.text, 'TAG STO - 02/09/2026 10.50 AM');
      expect(judul.align, LabelAlign.center);
    });

    test('tag berakhir di kotak isian - tidak ada blok di bawahnya', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );

      final indexKotak =
          doc.elements.indexWhere((e) => e is LabelBoxGrid);
      expect(indexKotak, isNot(-1));

      // Setelah kotak hanya boleh ada feed (ruang sobek kertas).
      final sesudah = doc.elements.sublist(indexKotak + 1);
      expect(sesudah.every((e) => e is LabelFeed), isTrue);

      final keys = doc.elements.whereType<LabelKeyValue>().map((e) => e.key);
      expect(keys, isNot(contains('OPERATOR')));
      expect(keys, isNot(contains('CETAK')));
    });

    test('QR langsung menempel ke kotak isian tanpa feed di antaranya', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );
      final indexQr = doc.elements.indexWhere((e) => e is LabelQr);
      expect(doc.elements[indexQr + 1], isA<LabelBoxGrid>());
    });

    test('baris lanjutan sejajar dengan kolom nilai', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );

      final rows = doc.elements.whereType<LabelKeyValue>().toList();
      final lanjutan = rows.where((e) => e.continuation).toList();
      expect(lanjutan, isNotEmpty, reason: 'nama part contoh sengaja panjang');

      final line = LabelBuilder.renderKeyValue(lanjutan.first, 32);
      final indent =
          LabelBuilder.keyColumnWidth + LabelBuilder.keySeparatorWidth;
      expect(line.substring(0, indent).trim(), isEmpty);
      expect(line.contains(':'), isFalse);

      // Sejajar dengan baris "KEY : VALUE" biasa.
      final normal = LabelBuilder.renderKeyValue(
        const LabelKeyValue('NAMA', 'X'),
        32,
      );
      expect(normal.indexOf('X'), indent);
    });

    test('nama part panjang dipotong agar muat di kertas 58mm', () {
      final doc = LabelBuilder.build(
        tag,
        paper: PaperSize.mm58,
      );

      for (final element in doc.elements) {
        if (element is LabelKeyValue) {
          final line = LabelBuilder.renderKeyValue(element, doc.charPerLine);
          expect(line.length, lessThanOrEqualTo(doc.charPerLine));
        }
      }
    });
  });
}
