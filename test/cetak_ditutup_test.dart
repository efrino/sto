import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sto_prep/data/remote/api_client.dart';
import 'package:sto_prep/data/remote/sto_api.dart';

/// Penolakan cetak karena `allow_print = 0`.
///
/// Admin menutup pencetakan begitu penghitungan dimulai, supaya tidak ada tag
/// baru yang lahir di tengah hitungan. Bagi operator itu keadaan yang wajar,
/// bukan kerusakan - dan aplikasi harus bisa membedakannya dari kegagalan
/// jaringan, kalau tidak ia akan menekan tombolnya berulang kali.
void main() {
  HttpStoApi apiYangMembalas(http.Response balasan) => HttpStoApi(
        ApiClient(
          baseUrlResolver: () async => 'http://contoh/api',
          client: MockClient((_) async => balasan),
        ),
      );

  http.Response tolakCetak() => http.Response(
        jsonEncode({
          'status': 'failed',
          'message': 'Untuk saat ini belum boleh print. Pencetakan tag pada '
              'event "TESTING EVENT STO" sedang ditutup oleh admin.',
          'id_event': 8,
          'event_name': 'TESTING EVENT STO',
          'allow_print': 0,
        }),
        403,
        headers: {'content-type': 'application/json'},
      );

  test('403 dengan allow_print 0 dikenali sebagai pencetakan ditutup',
      () async {
    final api = apiYangMembalas(tolakCetak());

    await expectLater(
      api.printTag(area: 'IFPP', partNumber: '12904-06201', nik: 'F.9964'),
      throwsA(
        isA<ApiCetakDitutupException>()
            .having((e) => e.namaEvent, 'namaEvent', 'TESTING EVENT STO')
            .having((e) => e.statusCode, 'statusCode', 403)
            .having(
              (e) => e.message,
              'message',
              contains('sedang ditutup oleh admin'),
            ),
      ),
    );
  });

  test('403 lain TIDAK ikut dibaca sebagai pencetakan ditutup', () async {
    // Perangkat yang pemasangannya dicabut juga membalas 403. Menyamakan
    // keduanya akan menampilkan "pencetakan ditutup admin" untuk masalah
    // yang sama sekali berbeda.
    final api = apiYangMembalas(
      http.Response(
        jsonEncode({
          'status': 'failed',
          'message': 'Anda tidak terdaftar di perangkat ini',
        }),
        403,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      api.printTag(area: 'IFPP', partNumber: '12904-06201', nik: 'F.9964'),
      throwsA(
        allOf(
          isA<ApiException>(),
          isNot(isA<ApiCetakDitutupException>()),
        ),
      ),
    );
  });

  test('penolakan tetap dikenali walau nama event tidak disebut', () async {
    final api = apiYangMembalas(
      http.Response(
        jsonEncode({
          'status': 'failed',
          'message': 'Untuk saat ini belum boleh print.',
          'allow_print': 0,
        }),
        403,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      api.printTag(area: 'IFPP', partNumber: '12904-06201', nik: 'F.9964'),
      throwsA(
        isA<ApiCetakDitutupException>()
            .having((e) => e.namaEvent, 'namaEvent', isEmpty),
      ),
    );
  });
}
