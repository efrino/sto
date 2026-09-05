import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sto_prep/core/config/app_config.dart';
import 'package:sto_prep/data/remote/api_client.dart';

void main() {
  Future<String> alamat() async => 'http://192.168.10.67/majsf_rest_api/api';

  http.Response balasanSukses() => http.Response(
        jsonEncode({'status': 'success', 'message': 'ok', 'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );

  /// Galat yang muncul saat `package:http` memakai ulang sambungan keep-alive
  /// yang sudah ditutup Apache (KeepAliveTimeout 5 detik di server STO).
  http.ClientException sambunganBasi() => http.ClientException(
        'Connection closed before full header was received',
        Uri.parse('http://192.168.10.67/majsf_rest_api/api/sto/device-list'),
      );

  group('Sambungan keep-alive yang basi', () {
    test('GET diulang sekali dan berhasil', () async {
      var percobaan = 0;
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async {
          percobaan++;
          if (percobaan == 1) throw sambunganBasi();
          return balasanSukses();
        }),
      );

      final hasil = await client.get('/sto/device-list');

      expect(percobaan, 2, reason: 'percobaan pertama gagal, kedua berhasil');
      expect((hasil as Map)['status'], 'success');
    });

    test('GET yang gagal dua kali menyerah dengan pesan yang bisa dibaca',
        () async {
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async => throw sambunganBasi()),
      );

      await expectLater(
        client.get('/sto/device-list'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('terputus'), contains('192.168.10.67')),
          ),
        ),
      );
    });

    test('POST TIDAK diulang - kiriman ganda lebih berbahaya', () async {
      var percobaan = 0;
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async {
          percobaan++;
          throw sambunganBasi();
        }),
      );

      await expectLater(
        client.post('/sto/print-tag', {'area': 'IFPD'}),
        throwsA(isA<ApiException>()),
      );
      expect(percobaan, 1, reason: 'print-tag tidak boleh terkirim dua kali');
    });
  });

  group('Permintaan yang dikirim', () {
    test('memakai Connection: close supaya tidak mewarisi sambungan basi',
        () async {
      http.BaseRequest? terkirim;
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async {
          terkirim = request;
          return balasanSukses();
        }),
      );

      await client.get('/sto/device-list', query: {'nik': 'E.9948'});

      expect(terkirim, isNotNull);
      expect(terkirim!.persistentConnection, isFalse);
      expect(terkirim!.url.queryParameters['nik'], 'E.9948');
    });
  });

  group('Amplop respons backend', () {
    test('status "failed" jadi ApiException walau HTTP 200', () async {
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'status': 'failed',
              'message': 'Input tidak valid',
              'errors': ['nik wajib diisi'],
            }),
            200,
          );
        }),
      );

      await expectLater(
        client.post('/sto/register', const {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Input tidak valid')
              .having((e) => e.errors, 'errors', ['nik wajib diisi']),
        ),
      );
    });
  });

  group('Kegagalan yang bisa dibereskan operator sendiri', () {
    Future<String> pesanDari(Object galat) async {
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async => throw galat),
      );
      try {
        await client.get('/sto/device-list');
        return 'TIDAK GAGAL';
      } on ApiException catch (e) {
        return e.message;
      }
    }

    test('TLS gagal disebut sebagai urusan Wi-Fi, bukan sertifikat', () async {
      // Yang benar-benar terjadi di lapangan: hotspot tanpa internet atau
      // captive portal. Operator melihat "CERTIFICATE_VERIFY_FAILED" dan
      // tidak punya petunjuk apa pun.
      final pesan = await pesanDari(
        HandshakeException(
          'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)',
        ),
      );
      expect(pesan, contains('Wi-Fi'));
      expect(pesan.toLowerCase(), isNot(contains('handshake')));
      expect(pesan, isNot(contains('CERTIFICATE_VERIFY_FAILED')));
    });

    test('nama server tidak ketemu disebut sebagai belum ada internet',
        () async {
      final pesan = await pesanDari(
        SocketException('Failed host lookup: mspin.newarmada.biz'),
      );
      expect(pesan, contains('192.168.10.67'));
      expect(pesan, contains('internet'));
    });

    test('server diam sampai batas waktu disebut lama menjawab', () async {
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async {
          await Future<void>.delayed(AppConfig.httpTimeout * 2);
          return balasanSukses();
        }),
      );
      await expectLater(
        client.get('/sto/device-list'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('tidak menjawab'),
          ),
        ),
      );
    });

    test('halaman HTML captive portal tidak dibaca sebagai data kosong',
        () async {
      // Dulu balasan begini diteruskan apa adanya dan berakhir sebagai daftar
      // kosong - layar tampak berhasil padahal tidak ada data yang datang.
      final client = ApiClient(
        baseUrlResolver: alamat,
        client: MockClient(
          (request) async => http.Response(
            '<html><body>Silakan login dulu</body></html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      await expectLater(
        client.get('/sto/device-list'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('bukan JSON'),
          ),
        ),
      );
    });
  });
}
