import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/data/remote/api_client.dart';
import 'package:sto_prep/data/remote/sto_api.dart';
import 'package:sto_prep/data/repositories/count_repository.dart';

void main() {
  group('Lookup tag dari handheld / server lain', () {
    test('endpoint GET /sto/tag-detail mengembalikan detail tag secara langsung',
        () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/sto/tag-detail')) {
          expect(request.url.queryParameters['id_tag'], 'STO260903-51');
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'id_tag': 'STO260903-51',
                'id_event': 5,
                'area': 'IFPD',
                'print_status': 'printed',
                'is_canceled': 0,
                'part_number': '53801-BZ010',
                'job_number': 'JOB-2601',
                'material_description': 'PANEL SIDE OUTER RH',
                'type': 'FP',
                'created_by': 'A.10525',
                'created_at': '2026-09-04 10:00:00',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'failed', 'message': 'not found'}),
          404,
        );
      });

      final api = HttpStoApi(
        ApiClient(
          baseUrlResolver: () async => 'http://contoh/api',
          client: client,
        ),
      );

      final detail = await api.fetchTagDetail('STO260903-51');
      expect(detail, isNotNull);

      final scannedTag = ScannedTag.fromJson('STO260903-51', detail!);
      expect(scannedTag.tagNo, 'STO260903-51');
      expect(scannedTag.partNumber, '53801-BZ010');
      expect(scannedTag.jobNumber, 'JOB-2601');
      expect(scannedTag.partName, 'PANEL SIDE OUTER RH');
      expect(scannedTag.area, 'IFPD');
      expect(scannedTag.partType, 'FP');
      expect(scannedTag.status, TagStatus.printed);
      expect(scannedTag.bolehDihitung, isTrue);
    });

    test('tag baru yang ada di print-history berhasil ditemukan dan boleh dihitung',
        () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/sto/tag-detail')) {
          return http.Response(
            jsonEncode({'status': 'failed', 'message': 'not found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/sto/print-history')) {
          expect(request.url.queryParameters['q'], 'STO260904-550');
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': [
                {
                  'id_tag': 'STO260904-550',
                  'id_event': 5,
                  'area': 'IFPD',
                  'print_status': 'printed',
                  'is_canceled': 0,
                  'part_number': '53801-BZ010',
                  'job_number': 'JOB-2601',
                  'material_description': 'PANEL SIDE OUTER RH',
                  'type': 'FP',
                  'created_by': 'A.10525',
                  'created_at': '2026-09-04 10:00:00',
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'failed', 'message': 'not found'}),
          404,
        );
      });

      final api = HttpStoApi(
        ApiClient(
          baseUrlResolver: () async => 'http://contoh/api',
          client: client,
        ),
      );

      final detail = await api.fetchTagDetail('STO260904-550', nik: 'A.20431');
      expect(detail, isNotNull);

      final scannedTag = ScannedTag.fromJson('STO260904-550', detail!);
      expect(scannedTag.tagNo, 'STO260904-550');
      expect(scannedTag.partNumber, '53801-BZ010');
      expect(scannedTag.jobNumber, 'JOB-2601');
      expect(scannedTag.partName, 'PANEL SIDE OUTER RH');
      expect(scannedTag.area, 'IFPD');
      expect(scannedTag.partType, 'FP');
      expect(scannedTag.printedBy, 'A.10525');
      expect(scannedTag.status, TagStatus.printed);
      expect(scannedTag.bolehDihitung, isTrue);
    });

    test('tag yang dibatalkan di server lain ditandai dan tidak boleh dihitung',
        () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/sto/tag-detail')) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'id_tag': 'STO260904-551',
                'area': 'IFPD',
                'print_status': 'printed',
                'is_canceled': 1,
                'cancel_reason': 'Salah part',
                'part_number': '53801-BZ010',
                'job_number': 'JOB-2601',
                'material_description': 'PANEL SIDE OUTER RH',
                'type': 'FP',
                'created_by': 'A.10525',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'failed'}),
          404,
        );
      });

      final api = HttpStoApi(
        ApiClient(
          baseUrlResolver: () async => 'http://contoh/api',
          client: client,
        ),
      );

      final detail = await api.fetchTagDetail('STO260904-551');
      expect(detail, isNotNull);

      final scannedTag = ScannedTag.fromJson('STO260904-551', detail!);
      expect(scannedTag.status, TagStatus.cancelled);
      expect(scannedTag.bolehDihitung, isFalse);
      expect(scannedTag.alasanTidakBolehDihitung, contains('DIBATALKAN'));
    });

    test('fallback ke scan-history jika print-history tidak menemukan baris',
        () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/sto/tag-detail') ||
            request.url.path.contains('/sto/print-history')) {
          return http.Response(
            jsonEncode({'status': 'success', 'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/sto/scan-history')) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': [
                {
                  'id_tag': 'STO260904-552',
                  'area': 'IFPP',
                  'part_number': '51531-BZ010',
                  'job_number': '51531-BZ010',
                  'material_description': 'PROTECTOR, FR BUMPER',
                  'created_by': 'A.10525',
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'failed'}),
          404,
        );
      });

      final api = HttpStoApi(
        ApiClient(
          baseUrlResolver: () async => 'http://contoh/api',
          client: client,
        ),
      );

      final detail = await api.fetchTagDetail('STO260904-552');
      expect(detail, isNotNull);

      final scannedTag = ScannedTag.fromJson('STO260904-552', detail!);
      expect(scannedTag.tagNo, 'STO260904-552');
      expect(scannedTag.partName, 'PROTECTOR, FR BUMPER');
      expect(scannedTag.bolehDihitung, isTrue);
    });
  });
}
