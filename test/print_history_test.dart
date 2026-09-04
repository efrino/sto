import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/utils/formatters.dart';
import 'package:sto_prep/data/models/print_entry.dart';

void main() {
  group('Waktu ringkas di daftar', () {
    final sekarang = DateTime(2026, 9, 4, 9, 13);

    test('hari ini cukup jamnya saja', () {
      expect(
        Formatters.ringkas(DateTime(2026, 9, 4, 9, 9), sekarang: sekarang),
        '09:09',
      );
    });

    test('hari lain tetap memakai tanggal', () {
      // Tanggal lengkap di tiap baris hanya memenuhi kartu; yang dibutuhkan
      // hanya pembeda saat tag-nya bukan dari hari ini.
      expect(
        Formatters.ringkas(DateTime(2026, 9, 3, 18, 40), sekarang: sekarang),
        '03/09 18:40',
      );
    });
  });

  // Bentuk baris ini disalin apa adanya dari balasan
  // GET /api/sto/print-history di server 67.
  Map<String, dynamic> baris({
    String status = 'printed',
    String error = '',
    String printedAt = '2026-09-03 18:29:33',
    int canceled = 0,
    String cancelRequestedAt = '',
    String cancelRequestedBy = '',
    String cancelReason = '',
  }) =>
      {
        'id_tag': 'STO260903-54',
        'id_event': 5,
        'event_name': 'STO Internal HMMI IFPD',
        'area': 'IFPP',
        'print_status': status,
        'print_error': error,
        'printed_at': printedAt,
        'is_canceled': canceled,
        'cancel_reason': cancelReason,
        'cancel_requested_at': cancelRequestedAt,
        'cancel_requested_by': cancelRequestedBy,
        'cancel_approved_by': '',
        'created_by': 'A.10525',
        'created_at': '2026-09-03 18:29:33',
        'id_item': 6158,
        'part_number': '51531-BZ010',
        'job_number': '51531-BZ010',
        'material_description': 'PROTECTOR, FR BUMPER',
        'type': 'FP',
        'status_part': 'REGULER',
        'customer': 'ADM',
        'model': 'AYLA',
        'plant': 'SAP',
      };

  group('Riwayat cetak dari server', () {
    test('baris tercetak dipetakan lengkap', () {
      final entry = PrintEntry.fromServer(baris());

      expect(entry.tagNo, 'STO260903-54');
      expect(entry.state, PrintState.printed);
      expect(entry.area, 'IFPP');
      expect(entry.partNumber, '51531-BZ010');
      expect(entry.eventName, 'STO Internal HMMI IFPD');
      expect(entry.printedAt, DateTime(2026, 9, 3, 18, 29, 33));
      expect(entry.perluCetak, isFalse);
    });

    test('tag gagal cetak membawa alasannya dan masih perlu dicetak', () {
      final entry = PrintEntry.fromServer(
        baris(status: 'error', error: 'Kertas printer habis', printedAt: ''),
      );

      expect(entry.state, PrintState.error);
      expect(entry.errorMessage, 'Kertas printer habis');
      expect(entry.printedAt, isNull);
      expect(entry.perluCetak, isTrue);
    });

    test('draft perlu dicetak, tag batal tidak', () {
      expect(PrintEntry.fromServer(baris(status: 'draft')).perluCetak, isTrue);

      // Tag yang sudah dibatalkan tidak boleh ikut tercetak ulang - itu yang
      // membuat pembatalan admin ada artinya.
      final batal = PrintEntry.fromServer(
        baris(status: 'draft', canceled: 1),
      );
      expect(batal.canceled, isTrue);
      expect(batal.perluCetak, isFalse);
    });

    test('tag hasil cetak ulang memakai nomor yang sama, bukan nomor baru', () {
      final entry = PrintEntry.fromServer(baris(status: 'draft'));
      final tag = entry.toTag();

      expect(tag.tagNo, entry.tagNo);
      expect(tag.partNumber, '51531-BZ010');
      expect(tag.area, 'IFPP');
      expect(tag.eventId, '5');
    });

    test('status tak dikenal dianggap draft, bukan dianggap tercetak', () {
      // Salah tebak ke arah "tercetak" berarti tag hilang diam-diam;
      // ke arah draft paling banter membuat satu lembar tercetak dua kali.
      expect(PrintState.fromName('entah'), PrintState.draft);
      expect(PrintState.fromName(null), PrintState.draft);
      expect(PrintState.fromName('PRINTED'), PrintState.printed);
    });

    test('tag yang diajukan batal terbaca sebagai pengajuan menggantung', () {
      final entry = PrintEntry.fromServer(
        baris(
          cancelRequestedAt: '2026-09-04 07:30:38',
          cancelRequestedBy: 'A.10525',
          cancelReason: 'Salah part',
        ),
      );

      expect(entry.cancelDiajukan, isTrue);
      expect(entry.canceled, isFalse, reason: 'belum diputus admin');
      expect(entry.cancelRequestedBy, 'A.10525');
      expect(entry.cancelReason, 'Salah part');
    });

    test('pengajuan yang sudah disetujui bukan lagi pengajuan menggantung', () {
      final entry = PrintEntry.fromServer(
        baris(canceled: 1, cancelRequestedAt: '2026-09-04 07:30:38'),
      );

      expect(entry.canceled, isTrue);
      expect(entry.cancelDiajukan, isFalse);
    });

    test('draft yang diajukan batal tidak ikut dicetak ulang', () {
      // Mencetaknya sekarang berarti kertas terbuang bila admin ternyata
      // menyetujui pembatalannya.
      final entry = PrintEntry.fromServer(
        baris(
          status: 'draft',
          printedAt: '',
          cancelRequestedAt: '2026-09-04 07:30:38',
        ),
      );

      expect(entry.state, PrintState.draft);
      expect(entry.perluCetak, isFalse);
    });

    test('ringkasan menghitung yang menunggu = draft + gagal', () {
      const history = PrintHistory(
        summary: {
          'total': 12,
          'draft': 3,
          'printed': 5,
          'error': 1,
          'diajukan_batal': 2,
          'dibatalkan': 1,
        },
      );

      expect(history.total, 12);
      expect(history.printed, 5);
      expect(history.menunggu, 4);
      expect(history.diajukanBatal, 2);
      expect(history.canceled, 1);
    });
  });
}
