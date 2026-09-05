import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/pengajuan_batal.dart';
import 'package:sto_prep/data/models/print_entry.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/state/cancel_provider.dart';

/// Kotak masuk pengajuan dipakai admin sambil berdiri di lapangan: yang baru
/// masuk itulah yang sedang ditunggu operatornya. Sebelumnya urutannya
/// mengikuti balasan server - pengajuan terlama di atas, dan admin harus
/// menggulir melewati puluhan pengajuan lama.
void main() {
  PengajuanBatal ajukan(String tagNo, String area, DateTime? waktu) {
    return PengajuanBatal(
      tag: StoTag(
        tagNo: tagNo,
        sequence: 1,
        batchId: 'B1',
        partNumber: 'P-$tagNo',
        jobNumber: 'J-$tagNo',
        partName: 'PART $tagNo',
        area: area,
        createdBy: 'E.9948',
        createdAt: DateTime(2026, 9, 1),
        cancelRequestedAt: waktu,
      ),
      keadaanCetak: PrintState.printed,
    );
  }

  final lama = ajukan('STO-515', 'IFPP', DateTime(2026, 9, 4, 7, 59));
  final tengah = ajukan('STO-516', 'PRESS', DateTime(2026, 9, 4, 8, 16));
  final baru = ajukan('STO-540', 'IFPP', DateTime(2026, 9, 5, 11, 2));
  final tanpaWaktu = ajukan('STO-999', 'IFPP', null);

  group('Urutan antrean pengajuan', () {
    test('terbaru di paling atas', () {
      final hasil = susunPengajuan([lama, baru, tengah], '');

      expect(
        hasil.map((p) => p.tag.tagNo),
        ['STO-540', 'STO-516', 'STO-515'],
      );
    });

    test('pengajuan tanpa waktu jatuh ke bawah, bukan dianggap terbaru', () {
      final hasil = susunPengajuan([tanpaWaktu, lama, baru], '');

      expect(hasil.first.tag.tagNo, 'STO-540');
      expect(hasil.last.tag.tagNo, 'STO-999');
    });

    test('daftar sumber tidak ikut berubah urutannya', () {
      final sumber = [lama, baru, tengah];
      susunPengajuan(sumber, '');

      expect(sumber.map((p) => p.tag.tagNo), ['STO-515', 'STO-540', 'STO-516']);
    });
  });

  group('Saringan area', () {
    test('hanya area yang dipilih yang tersisa, tetap terbaru di atas', () {
      final hasil = susunPengajuan([lama, tengah, baru], 'IFPP');

      expect(hasil.map((p) => p.tag.tagNo), ['STO-540', 'STO-515']);
    });

    test('saringan kosong berarti seluruh antrean', () {
      expect(susunPengajuan([lama, tengah, baru], ''), hasLength(3));
    });

    test('area dicocokkan tanpa peduli besar-kecil huruf dan spasi', () {
      expect(susunPengajuan([lama, tengah], ' ifpp '), hasLength(1));
    });
  });
}
