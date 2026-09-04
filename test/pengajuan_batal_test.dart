import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/pengajuan_batal.dart';
import 'package:sto_prep/data/models/print_entry.dart';
import 'package:sto_prep/data/models/sto_tag.dart';

/// Jejak tag menentukan bobot keputusan pembatalan: membatalkan tag yang
/// belum tercetak hampir tanpa akibat, sedangkan tag yang sudah dihitung
/// berarti angka hasil hitung ikut hilang dari perhitungan STO.
void main() {
  final tag = StoTag(
    tagNo: 'STO260904-514',
    sequence: 1,
    batchId: 'SERVER',
    partNumber: '5070A592',
    jobNumber: 'SLC68',
    partName: 'BRACKET',
    area: 'IFPD',
    createdBy: 'M.9276',
    createdAt: DateTime(2026, 9, 4, 8),
  );

  Map<String, dynamic> baris({
    String printStatus = 'printed',
    String printedAt = '2026-09-04 08:16:17',
    String nikA = '',
    Object qtyA = 0,
    String updatedA = '',
    String nikB = '',
    Object qtyB = 0,
    String updatedB = '',
  }) =>
      {
        'print_status': printStatus,
        'printed_at': printedAt,
        'nik_a': nikA,
        'qty_a': qtyA,
        'updated_a': updatedA,
        'nik_b': nikB,
        'qty_b': qtyB,
        'updated_b': updatedB,
      };

  group('Jejak tag pada pengajuan pembatalan', () {
    test('belum tercetak', () {
      final p = PengajuanBatal.fromServer(
        baris(printStatus: 'draft', printedAt: ''),
        tag,
      );

      expect(p.sudahDicetak, isFalse);
      expect(p.sudahDihitung, isFalse);
      expect(p.berisiko, isFalse);
      expect(p.ringkasan, contains('Belum tercetak'));
    });

    test('gagal cetak dibedakan dari belum tercetak', () {
      final p = PengajuanBatal.fromServer(
        baris(printStatus: 'error', printedAt: ''),
        tag,
      );
      expect(p.ringkasan, contains('Gagal cetak'));
    });

    test('sudah dicetak tapi belum dihitung', () {
      final p = PengajuanBatal.fromServer(baris(), tag);

      expect(p.sudahDicetak, isTrue);
      expect(p.sudahDihitung, isFalse);
      expect(p.berisiko, isFalse);
      expect(p.ringkasan, contains('belum dihitung'));
      expect(p.dicetakPada, DateTime(2026, 9, 4, 8, 16, 17));
    });

    test('sudah dihitung satu tim - qty, tim, dan NIK ikut terbaca', () {
      final p = PengajuanBatal.fromServer(
        baris(nikA: 'A.10525', qtyA: 10, updatedA: '2026-09-04 08:46:36'),
        tag,
      );

      expect(p.sudahDihitung, isTrue);
      expect(p.berisiko, isTrue, reason: 'angka hasil hitung akan hilang');
      expect(p.hitungan, hasLength(1));
      expect(p.hitungan.single.tim, 'A');
      expect(p.hitungan.single.nik, 'A.10525');
      expect(p.hitungan.single.qty, 10);
      expect(p.totalQty, 10);
      expect(p.ringkasan, contains('10 pcs'));
    });

    test('dua tim dijumlahkan', () {
      final p = PengajuanBatal.fromServer(
        baris(
          nikA: 'A.10525',
          qtyA: 10,
          updatedA: '2026-09-04 08:46:36',
          nikB: 'M.9276',
          qtyB: 8,
          updatedB: '2026-09-04 09:10:00',
        ),
        tag,
      );

      expect(p.hitungan.map((h) => h.tim), ['A', 'B']);
      expect(p.totalQty, 18);
    });

    test('hasil hitung 0 tetap dianggap sudah dihitung', () {
      // Penandanya waktu, bukan qty: hitungan 0 itu sah dan justru penting
      // terlihat admin sebelum tag-nya dibatalkan.
      final p = PengajuanBatal.fromServer(
        baris(nikA: 'A.10525', qtyA: 0, updatedA: '2026-09-04 08:46:36'),
        tag,
      );

      expect(p.sudahDihitung, isTrue);
      expect(p.totalQty, 0);
    });

    test('status cetak tak dikenal dianggap draft', () {
      final p = PengajuanBatal.fromServer(baris(printStatus: ''), tag);
      expect(p.keadaanCetak, PrintState.draft);
    });
  });
}
