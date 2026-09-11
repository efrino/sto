import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/utils/pesan_galat.dart';

/// Tidak ada galat teknis yang boleh sampai ke layar operator apa adanya.
void main() {
  group('Galat teknis jadi kalimat manusia', () {
    test('PlatformException dari plugin Bluetooth', () {
      final hasil = PesanGalat.manusiawi(
        'PlatformException(write_error, read failed, socket might closed or '
        'timeout, read ret: -1, null, null)',
      );
      expect(hasil, contains('printer'));
      expect(hasil, isNot(contains('PlatformException')));
      expect(hasil, isNot(contains('socket')));
    });

    test('DatabaseException dari sqflite', () {
      final hasil = PesanGalat.manusiawi(
        'DatabaseException(UNIQUE constraint failed: sto_counts.tag_no) '
        'sql \'INSERT INTO sto_counts\'',
      );
      expect(hasil, contains('Penyimpanan di perangkat'));
      expect(hasil, isNot(contains('sqflite')));
      expect(hasil, isNot(contains('INSERT')));
    });

    test('kesalahan pemrograman tidak bocor sebagai jejak', () {
      expect(
        PesanGalat.manusiawi('Null check operator used on a null value'),
        contains('laporkan ke admin'),
      );
      expect(
        PesanGalat.manusiawi(
          "type 'Null' is not a subtype of type 'String' in type cast",
        ),
        isNot(contains('subtype')),
      );
    });

    test('kalimat yang sudah manusiawi dibiarkan, awalan Exception dibuang',
        () {
      expect(
        PesanGalat.manusiawi('Exception: Tag ini sudah dibatalkan admin.'),
        'Tag ini sudah dibatalkan admin.',
      );
      expect(
        PesanGalat.manusiawi('Qty tidak boleh negatif.'),
        'Qty tidak boleh negatif.',
      );
    });

    test('null dan kosong tetap menghasilkan kalimat', () {
      expect(PesanGalat.manusiawi(null), isNotEmpty);
      expect(PesanGalat.manusiawi(''), isNotEmpty);
    });
  });
}
