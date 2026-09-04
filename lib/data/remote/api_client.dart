import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.errors = const []});

  final String message;
  final int? statusCode;

  /// Daftar kesalahan validasi dari backend (field `errors`).
  final List<String> errors;

  @override
  String toString() =>
      errors.isEmpty ? message : '$message: ${errors.join('; ')}';
}

/// Dilempar saat aplikasi memanggil fitur yang endpoint-nya memang belum ada.
/// Dibedakan dari [ApiException] supaya pemanggil bisa jatuh ke data lokal
/// tanpa menampilkan pesan "server error" yang menyesatkan.
class ApiNotAvailableException extends ApiException {
  ApiNotAvailableException(String fitur)
      : super('$fitur belum tersedia di API STO - sementara dilayani '
            'data perangkat ini.');
}

/// Pembungkus tipis di atas package http:
/// - base URL diambil dari setting (bisa diganti user tanpa rebuild)
/// - timeout seragam
/// - error jaringan diseragamkan jadi [ApiException]
class ApiClient {
  ApiClient({required this.baseUrlResolver, http.Client? client})
      : _client = client ?? http.Client();

  final Future<String> Function() baseUrlResolver;
  final http.Client _client;

  String? authToken;

  Future<Uri> _uri(String path, [Map<String, dynamic>? query]) async {
    final base = (await baseUrlResolver()).replaceAll(RegExp(r'/+$'), '');
    final cleaned = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && '$value'.isNotEmpty) cleaned[key] = '$value';
    });
    return Uri.parse('$base$path').replace(
      queryParameters: cleaned.isEmpty ? null : cleaned,
    );
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (authToken != null && authToken!.isNotEmpty)
          'Authorization': 'Bearer $authToken',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final uri = await _uri(path, query);
    try {
      // GET tidak mengubah apa pun, jadi aman diulang sekali bila sambungan
      // sempat terputus - lihat [_kirim].
      return _decode(await _kirim('GET', uri, ulangiBilaTerputus: true));
    } on TimeoutException {
      throw ApiException('Server tidak merespons (timeout).');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(await _pesanJaringan(e));
    }
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final uri = await _uri(path);
    try {
      // POST TIDAK diulang otomatis: mengirim ulang bisa berarti dua tag
      // tercetak atau dua user terdaftar. Lebih baik operator melihat pesan
      // gagal lalu menekan sendiri.
      return _decode(await _kirim('POST', uri, body: jsonEncode(body)));
    } on TimeoutException {
      throw ApiException('Server tidak merespons (timeout).');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(await _pesanJaringan(e));
    }
  }

  /// Mengirim satu permintaan dengan `Connection: close`.
  ///
  /// Sambungan keep-alive adalah sumber galat "Connection closed before full
  /// header was received": Apache menutup sambungan menganggur (KeepAliveTimeout
  /// beberapa detik), sementara `package:http` menyangka sambungan itu masih
  /// bisa dipakai lagi dan mengirim permintaan ke soket yang sudah mati.
  /// Handheld STO memakai jaringan lokal dan permintaannya jarang, jadi
  /// membuka sambungan baru tiap kali jauh lebih murah daripada operator
  /// melihat galat yang tidak bisa dia perbaiki.
  Future<http.Response> _kirim(
    String method,
    Uri uri, {
    String? body,
    bool ulangiBilaTerputus = false,
  }) async {
    try {
      return await _sekaliKirim(method, uri, body);
    } catch (e) {
      if (!ulangiBilaTerputus || !_karenaSambunganTerputus(e)) rethrow;
      // Satu kali percobaan ulang: sambungan basi hanya gagal sekali.
      return _sekaliKirim(method, uri, body);
    }
  }

  Future<http.Response> _sekaliKirim(
    String method,
    Uri uri,
    String? body,
  ) async {
    final request = http.Request(method, uri)
      ..headers.addAll(_headers)
      ..persistentConnection = false;
    if (body != null) request.body = body;

    final streamed = await _client.send(request).timeout(AppConfig.httpTimeout);
    return http.Response.fromStream(streamed);
  }

  bool _karenaSambunganTerputus(Object error) {
    final teks = '$error';
    return teks.contains('Connection closed before full header') ||
        teks.contains('Connection reset by peer') ||
        teks.contains('Connection closed while receiving data');
  }

  /// Menerjemahkan kegagalan jaringan menjadi kalimat yang berguna di
  /// lapangan. Operator tidak bisa berbuat apa-apa dengan teks
  /// "ClientException with SocketException ... errno = 101"; yang perlu dia
  /// tahu cuma: servernya tidak terjangkau, dan alamat mana yang dicoba.
  Future<String> _pesanJaringan(Object error) async {
    final alamat = Uri.tryParse(await baseUrlResolver())?.host ?? 'server';

    if (error is SocketException || error is HttpException) {
      return 'Server $alamat tidak terjangkau. Periksa Wi-Fi perangkat, '
          'atau alamat server di menu Setting.';
    }
    if (error is FormatException) {
      return 'Balasan server tidak bisa dibaca (bukan JSON). '
          'Periksa alamat server di menu Setting.';
    }
    final teks = '$error';

    if (_karenaSambunganTerputus(error)) {
      return 'Sambungan ke server $alamat terputus sebelum balasan lengkap. '
          'Coba sekali lagi.';
    }

    // Paket http membungkus kegagalan soket jadi ClientException.
    if (teks.contains('SocketException') ||
        teks.contains('Connection failed') ||
        teks.contains('Connection refused') ||
        teks.contains('Network is unreachable')) {
      return 'Server $alamat tidak terjangkau. Periksa Wi-Fi perangkat, '
          'atau alamat server di menu Setting.';
    }
    return 'Gagal terhubung ke server: $teks';
  }

  /// Backend STO membungkus semua balasan dengan `status` + `message`, dan
  /// mengirim kegagalan validasi tetap dengan HTTP 200. Jadi kode HTTP saja
  /// tidak cukup - field `status` yang menentukan.
  dynamic _decode(http.Response response) {
    final httpStatus = response.statusCode;
    dynamic body;
    try {
      body = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      body = response.body;
    }

    if (body is Map) {
      final status = body['status'];

      // REST_Controller menolak method yang tidak dikenal dengan
      // {"status": false, "error": "..."}.
      if (status == false) {
        throw ApiException(
          '${body['error'] ?? 'Endpoint tidak dikenal'}',
          statusCode: httpStatus,
        );
      }

      if (status == 'failed') {
        throw ApiException(
          '${body['message'] ?? 'Permintaan ditolak server'}',
          statusCode: httpStatus,
          errors: (body['errors'] as List?)?.map((e) => '$e').toList() ??
              const [],
        );
      }
    }

    if (httpStatus >= 200 && httpStatus < 300) return body;

    final message = body is Map && body['message'] != null
        ? '${body['message']}'
        : 'Permintaan gagal (HTTP $httpStatus)';
    throw ApiException(message, statusCode: httpStatus);
  }

  void close() => _client.close();
}
