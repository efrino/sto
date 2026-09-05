import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/utils/formatters.dart';
import 'package:sto_prep/data/models/tag_ok.dart';
import 'package:sto_prep/data/remote/api_client.dart';

/// Kontrak POST /sto/tag-ok-prepare. Yang diuji di sini bagian yang memang
/// milik aplikasi: pembacaan tipe yang longgar dari server, dan penolakan
/// yang harus dibaca sebagai keterangan - bukan sebagai kegagalan jaringan.
void main() {
  group('Pembacaan tipe sesuai kontrak', () {
    final lengkap = TagOk.fromServer({
      'id_tag_ok': 'MAJWLD0509260100374',
      'area': 'WELD',
      'part_number': '61023-BZ420-00-26',
      'job_number': 'T177',
      'process': 'WELDING',
      'line': 'OUT',
      'customer': '',
      'project': '',
      'status': 'FP',
      'qty_kbn': '24',
      'shift': 1,
      'id_event': 3,
      'scan_open': 1,
      'opened_by': 'S.9390',
      'opened_at': '2026-09-05 18:40:00',
      'qty_scan': null,
      'scanned_by': '',
      'scanned_at': '',
      'scan_at': '2026-09-05 07:10:00',
      'scan_by': 'administrator',
      'is_canceled': 0,
      'cancel_reason': '',
      'canceled_by': '',
      'canceled_at': '',
    });

    test('qty_kbn tetap String, angkanya dibaca terpisah', () {
      // Kolomnya varchar di server - "24" dan 24 sama-sama mungkin datang.
      expect(lengkap.qtyKbn, '24');
      expect(lengkap.kanban, 24);
    });

    test('field kosong berupa "" tidak jadi tanggal atau angka palsu', () {
      expect(lengkap.scannedBy, isEmpty);
      expect(lengkap.scannedAt, isNull);
      expect(lengkap.qtyScan, isNull);
      expect(lengkap.canceledAt, isNull);
    });

    test('scan_at/scan_by produksi terpisah dari jejak hitung STO', () {
      // Keduanya gampang tertukar: yang satu kapan tag diterbitkan produksi,
      // yang satu kapan tag dihitung saat STO.
      expect(lengkap.scanBy, 'administrator');
      expect(lengkap.scanAt, isNotNull);
      expect(lengkap.scannedAt, isNull);
    });

    test('scan_open = 1 berarti langsung siap dihitung', () {
      expect(lengkap.terbuka, isTrue);
      expect(lengkap.keadaan, 'SIAP DIHITUNG');
      expect(lengkap.bisaDiproses, isTrue);
    });

    test('nilai numerik yang datang sebagai string tetap terbaca', () {
      final t = TagOk.fromServer({
        'id_tag_ok': 'X',
        'area': 'WELD',
        'shift': '2',
        'id_event': '7',
        'scan_open': '1',
        'qty_scan': '30',
        'is_canceled': '1',
      });

      expect(t.shift, 2);
      expect(t.eventId, 7);
      expect(t.terbuka, isTrue);
      expect(t.qtyScan, 30);
      expect(t.dibatalkan, isTrue);
    });
  });

  group('Penolakan server', () {
    test('409 dikenali sebagai konflik, bukan galat biasa', () {
      final e = ApiException(
        'Tag OK sudah disiapkan',
        statusCode: 409,
        body: const {'status': 'failed', 'data': {'id_tag_ok': 'X'}},
      );

      expect(e.konflik, isTrue);
      expect(e.body?['data'], isNotNull);
    });

    test('400 membawa seluruh kesalahan, bukan hanya yang pertama', () {
      final e = ApiException(
        'Input tidak valid',
        statusCode: 400,
        errors: const ['area wajib diisi', 'id_tag_ok wajib diisi'],
      );

      expect(e.konflik, isFalse);
      expect(e.errors, hasLength(2));
      // Operator memperbaiki sekali jalan bila keduanya terlihat.
      expect(e.toString(), contains('area wajib diisi'));
      expect(e.toString(), contains('id_tag_ok wajib diisi'));
    });
  });

  group('Aturan qty saat menghitung', () {
    test('qty 0 sah - barangnya memang nihil', () {
      // Nol bukan "belum diisi": tag yang isinya habis tetap harus tercatat,
      // dan selisihnya terhadap kanban justru yang dicari.
      final t = TagOk.fromServer({
        'id_tag_ok': 'X',
        'area': 'WELD',
        'qty_kbn': '24',
        'qty_scan': 0,
        'scanned_by': 'M.9276',
        'scanned_at': '2026-09-06 08:00:00',
      });

      expect(t.qtyScan, 0);
      expect(t.sudahDihitung, isTrue);
      expect(t.selisih, -24);
    });

    test('qty_scan null berarti belum dihitung, bukan nol', () {
      final t = TagOk.fromServer({'id_tag_ok': 'X', 'area': 'WELD'});

      expect(t.qtyScan, isNull);
      expect(t.sudahDihitung, isFalse);
      expect(t.selisih, isNull);
    });
  });

  group('Waktu yang dikirim ke server', () {
    test('scan_at memakai bentuk yang diterima API, tanpa zona', () {
      // ISO8601 dengan Z membuat jamnya melenceng tujuh jam di server WIB.
      final waktu = DateTime(2026, 9, 5, 18, 40, 5);

      expect(Formatters.serverDateTime(waktu), '2026-09-05 18:40:05');
    });
  });
}
