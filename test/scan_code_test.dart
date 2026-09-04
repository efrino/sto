import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/utils/scan_code.dart';

void main() {
  group('Pembacaan hasil scan', () {
    test('QR tag dibaca apa adanya', () {
      expect(ScanCode.extractTagNo('STO260902-000123'), 'STO260902-000123');
    });

    test('spasi dan huruf kecil dinormalkan', () {
      expect(ScanCode.extractTagNo('  sto260902-000123 \n'),
          'STO260902-000123');
    });

    test('nomor offline dan demo ikut terbaca', () {
      expect(ScanCode.extractTagNo('LSTO260902-000004'), 'LSTO260902-000004');
      expect(ScanCode.extractTagNo('DEMO260902-000001'), 'DEMO260902-000001');
    });

    test('nomor tag diambil dari teks yang terbawa awalan', () {
      expect(
        ScanCode.extractTagNo('TAG:STO260902-000009;area=WH1'),
        'STO260902-000009',
      );
    });

    test('input kosong atau terlalu pendek diabaikan', () {
      expect(ScanCode.extractTagNo(''), isNull);
      expect(ScanCode.extractTagNo('   '), isNull);
      expect(ScanCode.extractTagNo('ab'), isNull);
      expect(ScanCode.extractTagNo(null), isNull);
    });

    test('ketikan manual yang belum lengkap tetap diteruskan', () {
      expect(ScanCode.extractTagNo('sto2609'), 'STO2609');
    });
  });
}
