import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sto_prep/data/remote/api_client.dart';
import 'package:sto_prep/data/remote/sto_api.dart';

/// Server STO MENGABAIKAN `id_device` pada `user-list` - diuji ke server
/// sungguhan 4 Sep 2026: keempat perangkat membalas ketujuh user yang sama.
/// Akibatnya halaman Perangkat menampilkan SELURUH NIK sebagai terpasang di
/// setiap perangkat. Penyaringannya karena itu dikerjakan aplikasi.
void main() {
  Future<String> alamat() async => 'http://contoh.local/api';

  Map<String, dynamic> baris(String nik, int? deviceId) => {
        'nik': nik,
        'role': 'operator',
        'permissions': ['scan'],
        'device_id': deviceId,
        'device_name': deviceId == null ? '' : '00$deviceId-HSS-TBN',
        'android_id': deviceId == null ? '' : 'android$deviceId',
        'area': <String>[],
      };

  HttpStoApi apiDengan(List<Map<String, dynamic>> data, {Uri? Function(http.Request)? rekam}) {
    return HttpStoApi(
      ApiClient(
        baseUrlResolver: alamat,
        client: MockClient((request) async {
          rekam?.call(request);
          return http.Response(
            jsonEncode({'status': 'success', 'data': data}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
  }

  final semua = [
    baris('A.10525', 8),
    baris('E.9948', null),
    baris('F.9964', 2),
    baris('M.9276', null),
  ];

  group('Daftar user per perangkat', () {
    test('hanya NIK milik perangkat itu yang terbawa', () async {
      final api = apiDengan(semua);

      final hasil = await api.fetchUsers('E.9948', deviceId: 8);

      expect(hasil.map((u) => u.nik), ['A.10525']);
    });

    test('perangkat tanpa pemasangan menghasilkan daftar kosong', () async {
      final api = apiDengan(semua);

      expect(await api.fetchUsers('E.9948', deviceId: 6), isEmpty);
    });

    test('tanpa id_device daftarnya tetap utuh', () async {
      final api = apiDengan(semua);

      final hasil = await api.fetchUsers('E.9948');

      expect(hasil, hasLength(4));
    });

    test('id_device tetap dikirim supaya server yang sudah diperbaiki dipakai',
        () async {
      Uri? diminta;
      final api = apiDengan(semua, rekam: (r) => diminta = r.url);

      await api.fetchUsers('E.9948', deviceId: 8);

      expect(diminta?.queryParameters['id_device'], '8');
    });

    test('daftar user tidak menimpa perangkat sesi ini', () async {
      final api = apiDengan(semua);

      // Perangkat sesi hanya boleh diisi login/register. Dulu tiap baris
      // user-list ikut menimpanya, sehingga yang tersimpan adalah perangkat
      // milik user terakhir pada daftar.
      await api.fetchUsers('E.9948');

      expect(api.perangkatTerpasang, isNull);
    });
  });
}
