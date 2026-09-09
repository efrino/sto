import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/sto_device.dart';
import 'package:sto_prep/data/remote/api_client.dart';
import 'package:sto_prep/data/repositories/auth_repository.dart';

void main() {
  group('Perangkat mengaku sendiri', () {
    // Operator pindah ke HP pribadi saat handheld habis baterai. Login
    // ditolak karena NIK-nya masih menempel di handheld; perangkat ini
    // mengaku, lalu login diulang.
    test('penolakan perangkat memicu klaim', () {
      final e = ApiException(
        'Anda tidak terdaftar di perangkat ini',
        statusCode: 403,
      );
      expect(bolehKlaimPerangkat(e, 'HP BUDI'), isTrue);
    });

    test('perangkat tanpa nama tidak boleh mengaku', () {
      // Tanpa nama, perangkat ini akan tercatat sebagai baris tanpa
      // identitas di layar admin - tidak ada yang bisa mengenalinya.
      final e = ApiException('x', statusCode: 403);
      expect(bolehKlaimPerangkat(e, ''), isFalse);
      expect(bolehKlaimPerangkat(e, '   '), isFalse);
    });

    test('NIK yang tidak terdaftar tidak dicoba ulang', () {
      // 404 datang dari NIK yang belum didaftarkan admin. Mengulanginya
      // tidak akan pernah berhasil, dan pesan aslinya justru hilang.
      final e = ApiException('NIK tidak terdaftar', statusCode: 404);
      expect(bolehKlaimPerangkat(e, 'HP BUDI'), isFalse);
    });

    test('gangguan server tidak memindahkan perangkat', () {
      // Perangkat tidak boleh berpindah gara-gara server tersendat -
      // perpindahan itu mencabut NIK dari perangkat yang mungkin sedang
      // dipakai bekerja.
      for (final kode in [500, 502, 408, null]) {
        expect(
          bolehKlaimPerangkat(ApiException('x', statusCode: kode), 'HP BUDI'),
          isFalse,
          reason: 'kode $kode',
        );
      }
    });
  });

  group('Pemasangan NIK ke perangkat', () {
    final device = StoDevice(
      deviceId: '20a92433c2f589cd',
      assetName: '016-HSS-TBN',
      model: 'SENRAISE H10',
      niks: const ['A.20431', '11223344'],
      registeredAt: DateTime(2026, 9, 3, 7),
      registeredBy: 'E.9948',
    );

    test('hanya NIK terpasang yang dikenali, tanpa peduli huruf besar/kecil',
        () {
      expect(device.allows('A.20431'), isTrue);
      expect(device.allows('a.20431'), isTrue);
      expect(device.allows(' 11223344 '), isTrue);
      expect(device.allows('A.10525'), isFalse);
    });

    test('satu perangkat boleh memuat beberapa NIK (mis. dua shift)', () {
      final ditambah = device.copyWith(niks: [...device.niks, 'A.30001']);
      expect(ditambah.niks.length, 3);
      expect(ditambah.allows('A.30001'), isTrue);
      expect(ditambah.nikLabel, 'A.20431, 11223344, A.30001');
    });

    test('lepas semua NIK saat event selesai', () {
      final dilepas = device.copyWith(niks: const []);
      expect(dilepas.niks, isEmpty);
      expect(dilepas.allows('A.20431'), isFalse);
      expect(dilepas.nikLabel, 'Belum dipasangkan');
    });

    test('perangkat tanpa nomor aset ditandai belum terdaftar', () {
      final baru = StoDevice(
        deviceId: 'abc123',
        registeredAt: DateTime(2026, 9, 3),
      );
      expect(baru.terdaftar, isFalse);
      expect(baru.label, 'Belum diberi nomor aset');

      expect(device.terdaftar, isTrue);
      expect(device.label, '016-HSS-TBN');
    });

    test('baris database bolak-balik tanpa kehilangan pemasangan', () {
      final kembali = StoDevice.fromMap(device.toMap());
      expect(kembali.deviceId, device.deviceId);
      expect(kembali.assetName, '016-HSS-TBN');
      expect(kembali.niks, ['A.20431', '11223344']);
      expect(kembali.active, isTrue);
    });

    test('payload API memakai daftar NIK, bukan teks gabungan', () {
      final json = device.toApiJson();
      expect(json['device_id'], '20a92433c2f589cd');
      expect(json['asset_name'], '016-HSS-TBN');
      expect(json['niks'], ['A.20431', '11223344']);

      // Server boleh mengirim balik dalam bentuk daftar maupun teks koma.
      expect(
        StoDevice.fromJson({
          'device_id': 'x',
          'asset_name': '017-HSS-TBN',
          'niks': 'a.1, a.2',
        }).niks,
        ['A.1', 'A.2'],
      );
    });
  });
}
