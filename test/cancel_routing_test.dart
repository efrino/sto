import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/data/remote/api_client.dart';
import 'package:sto_prep/data/remote/sto_api.dart';

/// Keputusan pembatalan harus mendarat di endpoint yang benar.
///
/// Bug yang pernah terjadi: persetujuan dikirim ke `cancel-tag`, sehingga
/// `cancel_approved_by` tidak pernah terisi - tidak ada jejak siapa yang
/// menyetujui pembatalan sebuah tag.
void main() {
  /// Mencatat permintaan terakhir, lalu menjawab seadanya.
  late List<String> jalur;
  late List<Map<String, dynamic>> badan;

  HttpStoApi apiPencatat() {
    jalur = [];
    badan = [];
    final klien = MockClient((request) async {
      jalur.add(request.url.path);
      badan.add(
        request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>,
      );
      return http.Response(
        jsonEncode({'status': 'success', 'message': 'ok'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    return HttpStoApi(
      ApiClient(
        baseUrlResolver: () async => 'http://contoh/api',
        client: klien,
      ),
    );
  }

  StoTag tagDasar({String? penyetuju, TagStatus status = TagStatus.printed}) =>
      StoTag(
        tagNo: 'STO260904-538',
        sequence: 1,
        batchId: 'B1',
        partNumber: '5070A635',
        jobNumber: 'SLC69',
        partName: 'BRACKET NO.2 BODY MOUNTING LH',
        area: 'IFPD',
        status: status,
        createdBy: 'M.9276',
        createdAt: DateTime(2026, 9, 4, 9),
        cancelApprovedBy: penyetuju,
      );

  test('persetujuan pengajuan memakai cancel-approve, bukan cancel-tag',
      () async {
    final api = apiPencatat();

    // Setelah admin menekan Setujui, status LOKAL sudah DIBATALKAN - jadi
    // penanda yang dipakai adalah adanya penyetuju, bukan statusnya.
    await api.cancelTag(
      tagDasar(penyetuju: 'E.9948', status: TagStatus.cancelled),
      'Tidak keluar dari printer',
    );

    expect(jalur.single, endsWith('/sto/cancel-approve'));
    expect(badan.single['nik'], 'E.9948');
    expect(badan.single['id_tag'], 'STO260904-538');
  });

  test('pembatalan langsung tanpa pengajuan tetap lewat cancel-tag', () async {
    final api = apiPencatat();

    await api.cancelTag(tagDasar(), 'Salah cetak');

    expect(jalur.single, endsWith('/sto/cancel-tag'));
    expect(badan.single['id_tag'], 'STO260904-538');
  });

  test('penolakan memakai cancel-reject dengan NIK penolak', () async {
    final api = apiPencatat();

    await api.rejectCancelTag(tagDasar(penyetuju: 'E.9948'));

    expect(jalur.single, endsWith('/sto/cancel-reject'));
    expect(badan.single['nik'], 'E.9948');
  });

  test('pengajuan memakai cancel-request beserta alasannya', () async {
    final api = apiPencatat();

    final tag = StoTag(
      tagNo: 'STO260904-540',
      sequence: 1,
      batchId: 'B1',
      partNumber: 'X',
      jobNumber: 'Y',
      partName: 'Z',
      area: 'IFPD',
      createdBy: 'M.9276',
      createdAt: DateTime(2026, 9, 4, 9),
      cancelRequestedBy: 'M.9276',
    );

    await api.requestCancelTag(tag, 'Kertas habis');

    expect(jalur.single, endsWith('/sto/cancel-request'));
    expect(badan.single['nik'], 'M.9276');
    expect(badan.single['reason'], 'Kertas habis');
  });
}
