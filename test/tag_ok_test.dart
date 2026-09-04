import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/utils/scan_code.dart';
import 'package:sto_prep/data/models/tag_ok.dart';

/// Tag OK punya dua langkah: disiapkan (scan_open = 1) lalu dihitung
/// (scan_open = 0 + qty). Keadaan itu yang menentukan tombol mana yang boleh
/// ditekan operator.
void main() {
  Map<String, dynamic> baris({
    int scanOpen = 0,
    String openedBy = '',
    String openedAt = '',
    Object? qtyScan,
    String scannedBy = '',
    String scannedAt = '',
    String qtyKbn = '36',
  }) =>
      {
        'id_tag_ok': 'MAJ2708260202754',
        'area': 'IFPP',
        'part_number': 'P61163-BZ420-00',
        'job_number': '61163-BZ420',
        'qty_kbn': qtyKbn,
        'status': 'STP',
        'scan_open': scanOpen,
        'opened_by': openedBy,
        'opened_at': openedAt,
        'qty_scan': qtyScan,
        'scanned_by': scannedBy,
        'scanned_at': scannedAt,
      };

  group('Keadaan Tag OK', () {
    test('belum disiapkan', () {
      final t = TagOk.fromServer(baris());
      expect(t.terbuka, isFalse);
      expect(t.sudahDihitung, isFalse);
      expect(t.keadaan, 'BELUM DISIAPKAN');
    });

    test('sudah disiapkan, siap dihitung', () {
      final t = TagOk.fromServer(
        baris(scanOpen: 1, openedBy: 'M.9276', openedAt: '2026-09-04 10:00:00'),
      );
      expect(t.terbuka, isTrue);
      expect(t.sudahDihitung, isFalse);
      expect(t.keadaan, 'SIAP DIHITUNG');
      expect(t.openedBy, 'M.9276');
    });

    test('sudah dihitung menutup tag', () {
      final t = TagOk.fromServer(
        baris(
          qtyScan: 34,
          scannedBy: 'A.10525',
          scannedAt: '2026-09-04 10:30:00',
        ),
      );
      expect(t.sudahDihitung, isTrue);
      expect(t.terbuka, isFalse);
      expect(t.qtyScan, 34);
      expect(t.keadaan, 'SUDAH DIHITUNG');
    });
  });

  group('Selisih terhadap kanban', () {
    test('kurang dari kanban', () {
      final t = TagOk.fromServer(baris(qtyScan: 34, scannedAt: '2026-09-04 10:30:00'));
      expect(t.kanban, 36);
      expect(t.selisih, -2);
    });

    test('lebih dari kanban', () {
      final t = TagOk.fromServer(baris(qtyScan: 40, scannedAt: '2026-09-04 10:30:00'));
      expect(t.selisih, 4);
    });

    test('kanban tidak terbaca -> selisih tidak dihitung-hitung sendiri', () {
      // Lebih baik tidak menampilkan selisih daripada menampilkan angka yang
      // dikarang dari kanban kosong.
      final t = TagOk.fromServer(baris(qtyKbn: '', qtyScan: 40));
      expect(t.kanban, isNull);
      expect(t.selisih, isNull);
    });

    test('belum dihitung -> belum ada selisih', () {
      final t = TagOk.fromServer(baris(scanOpen: 1));
      expect(t.selisih, isNull);
    });
  });

  group('Pembatalan Tag OK', () {
    Map<String, dynamic> barisBatal(int nilai) => {
          ...baris(scanOpen: 1),
          'is_canceled': nilai,
          'cancel_reason': 'Mispart - part tidak sesuai',
          'canceled_by': 'M.9276',
          'canceled_at': '2026-09-04 08:10:00',
        };

    test('pengajuan menahan tag dari langkah berikutnya', () {
      final t = TagOk.fromServer(barisBatal(2));

      expect(t.menungguKeputusan, isTrue);
      expect(t.dibatalkan, isFalse);
      // Tag yang menunggu keputusan tidak boleh dihitung lebih dulu - kalau
      // pembatalannya disetujui, hitungannya jadi angka yang tidak sah.
      expect(t.bisaDiproses, isFalse);
      expect(t.keadaan, 'MENUNGGU KEPUTUSAN');
    });

    test('tag batal tidak bisa disiapkan maupun dihitung lagi', () {
      final t = TagOk.fromServer(barisBatal(1));

      expect(t.dibatalkan, isTrue);
      expect(t.bisaDiproses, isFalse);
      expect(t.keadaan, 'DIBATALKAN');
      expect(t.canceledBy, 'M.9276');
      expect(t.cancelReason, contains('Mispart'));
    });

    test('keadaan batal menang atas keadaan hitung', () {
      // Tag yang sudah dihitung lalu dibatalkan harus terbaca DIBATALKAN;
      // menampilkannya sebagai "sudah dihitung" menyembunyikan pembatalannya.
      final t = TagOk.fromServer({
        ...baris(qtyScan: 34, scannedBy: 'M.9276', scannedAt: '2026-09-04 08:00:00'),
        'is_canceled': 1,
      });

      expect(t.sudahDihitung, isTrue);
      expect(t.keadaan, 'DIBATALKAN');
    });

    test('tanpa kolom pembatalan (baris lama) tag tetap bisa diproses', () {
      final t = TagOk.fromServer(baris(scanOpen: 1));

      expect(t.batal, 0);
      expect(t.bisaDiproses, isTrue);
      expect(t.canceledAt, isNull);
    });
  });

  group('Pembacaan kode Tag OK', () {
    test('kode produksi dibaca apa adanya', () {
      // Tanpa tanda hubung, jadi pola tag STO tidak cocok - itu sebabnya
      // Tag OK punya pembaca sendiri.
      expect(ScanCode.extractTagOk('MAJ2708260202754'), 'MAJ2708260202754');
      expect(ScanCode.extractTagOk(' maj2708260202754 '), 'MAJ2708260202754');
    });

    test('hasil pindai terpotong ditolak', () {
      expect(ScanCode.extractTagOk('MAJ'), isNull);
      expect(ScanCode.extractTagOk(''), isNull);
      expect(ScanCode.extractTagOk(null), isNull);
    });
  });
}
