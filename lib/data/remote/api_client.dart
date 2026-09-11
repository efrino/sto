import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.errors = const [],
    this.body,
  });

  final String message;
  final int? statusCode;

  /// Daftar kesalahan validasi dari backend (field `errors`).
  final List<String> errors;

  /// Badan response apa adanya. Penolakan tidak selalu berarti kegagalan:
  /// 409 pada tag OK membawa baris yang sudah ada, atau daftar event yang
  /// harus dipilih - keduanya perlu ditampilkan, bukan dibuang.
  final Map<String, dynamic>? body;

  /// true bila server menolak karena keadaan, bukan karena permintaannya
  /// salah bentuk - layar menampilkannya sebagai keterangan, bukan galat.
  bool get konflik => statusCode == 409;

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

  /// Mencoba satu jalur pada beberapa alamat server sekaligus, memakai yang
  /// pertama menjawab. Dipakai untuk endpoint yang belum ada di semua
  /// deployment - bukan untuk panggilan biasa, yang harus tetap patuh pada
  /// alamat pilihan operator.
  Future<Object?> getAbsolute(
    Iterable<String> alamatServer,
    String path, {
    Map<String, String>? query,
  }) async {
    final terpakai = (await baseUrlResolver()).replaceAll(RegExp(r'/+$'), '');
    Object? galat;

    for (final alamat in alamatServer) {
      final base = alamat.replaceAll(RegExp(r'/+$'), '');
      if (base == terpakai) continue;
      try {
        return await getPada(base, path, query: query);
      } catch (e) {
        galat = e;
      }
    }

    throw galat ?? ApiException('Tidak ada server yang menjawab $path.');
  }

  /// GET pada satu alamat server tertentu, di luar alamat pilihan operator.
  Future<dynamic> getPada(
    String base,
    String path, {
    Map<String, String>? query,
  }) async {
    final bersih = <String, String>{};
    query?.forEach((k, v) {
      if (v.isNotEmpty) bersih[k] = v;
    });
    final uri = Uri.parse('$base$path').replace(
      queryParameters: bersih.isEmpty ? null : bersih,
    );

    try {
      return _decode(await _kirim('GET', uri, ulangiBilaTerputus: true));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(await _pesanJaringan(e));
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final uri = await _uri(path, query);
    try {
      // GET tidak mengubah apa pun, jadi aman diulang sekali bila sambungan
      // sempat terputus - lihat [_kirim].
      return _decode(await _kirim('GET', uri, ulangiBilaTerputus: true));
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
    final teksAwal = '$error';

    if (error is TimeoutException) {
      return 'Server $alamat tidak menjawab dalam '
          '${AppConfig.httpTimeout.inSeconds} detik. Sinyal mungkin lemah - '
          'coba sekali lagi.';
    }

    // Kegagalan TLS - dan ini JARANG berarti sertifikat servernya bermasalah.
    //
    // Penyebab yang benar-benar terjadi di lapangan: handheld tersambung ke
    // Wi-Fi/hotspot yang tidak punya internet atau memakai halaman login
    // (captive portal). Yang menjawab bukan server STO, jadi sertifikat yang
    // disodorkan memang bukan miliknya. Tanpa kalimat ini operator hanya
    // melihat "HandshakeException ... CERTIFICATE_VERIFY_FAILED" dan tidak
    // punya petunjuk apa pun untuk membereskannya.
    if (error is HandshakeException ||
        error is TlsException ||
        error is CertificateException ||
        teksAwal.contains('CERTIFICATE_VERIFY_FAILED') ||
        teksAwal.contains('HandshakeException')) {
      return 'Sambungan aman ke $alamat gagal diverifikasi. Biasanya karena '
          'Wi-Fi yang dipakai belum punya internet atau masih meminta login '
          'di halaman browser. Periksa jaringannya, atau pilih server '
          'jaringan pabrik di menu Setting.';
    }

    // Nama server tidak bisa diterjemahkan jadi alamat - DNS atau internet
    // yang bermasalah, bukan servernya.
    if (teksAwal.contains('Failed host lookup') ||
        teksAwal.contains('nodename nor servname')) {
      return 'Server tidak terjangkau. Perangkat ini belum '
          'terhubung internet.';
    }

    if (error is SocketException || error is HttpException) {
      return 'Server tidak terjangkau. Periksa Wi-Fi perangkat.';
    }
    if (error is FormatException) {
      return 'Balasan server tidak bisa dibaca (bukan JSON). '
          'Periksa alamat server di menu Setting.';
    }
    final teks = '$error';

    if (_karenaSambunganTerputus(error)) {
      return 'Sambungan ke server terputus sebelum balasan lengkap. '
          'Coba sekali lagi.';
    }

    // Paket http membungkus kegagalan soket jadi ClientException.
    if (teks.contains('SocketException') ||
        teks.contains('Connection failed') ||
        teks.contains('Connection refused') ||
        teks.contains('Network is unreachable')) {
      return 'Server tidak terjangkau. Periksa Wi-Fi perangkat.';
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
      // {"status": false, "error": "Unknown method"}.
      if (status == false) {
        final rawError = '${body['error'] ?? 'Endpoint tidak dikenal'}';
        throw ApiException(
          _terjemahkanPesanBackend(rawError),
          statusCode: httpStatus,
        );
      }

      if (status == 'failed') {
        final rawMsg = '${body['message'] ?? 'Permintaan ditolak server'}';
        throw ApiException(
          _terjemahkanPesanBackend(rawMsg),
          statusCode: httpStatus,
          errors: (body['errors'] as List?)
                  ?.map((e) => _terjemahkanPesanBackend('$e'))
                  .toList() ??
              const [],
          body: Map<String, dynamic>.from(body),
        );
      }
    }

    // Balasan 2xx yang isinya bukan JSON hampir selalu halaman HTML milik
    // captive portal atau proxy. Dulu isinya diteruskan apa adanya: pemanggil
    // membacanya sebagai daftar kosong, sehingga layar tampak "berhasil tapi
    // datanya tidak ada" - kegagalan paling sulit dilacak dari lapangan.
    if (httpStatus >= 200 && httpStatus < 300) {
      if (body is String) {
        throw ApiException(
          'Balasan dari jaringan ini bukan data STO (bukan JSON). Wi-Fi yang '
          'dipakai kemungkinan masih meminta login lewat halaman browser.',
          statusCode: httpStatus,
        );
      }
      return body;
    }

    final rawMessage = body is Map && body['message'] != null
        ? '${body['message']}'
        : _pesanStatusHttp(httpStatus);
    final message = _terjemahkanPesanBackend(rawMessage);
    throw ApiException(message, statusCode: httpStatus);
  }

  static String _terjemahkanPesanBackend(String pesan) {
    final lower = pesan.toLowerCase().trim();
    if (lower == 'unknown method' || lower.contains('unknown method')) {
      return 'Layanan belum tersedia di server STO ini. Hubungi tim IT untuk pembaruan sistem.';
    }
    if (lower == 'invalid api key' || lower.contains('invalid api key')) {
      return 'Kunci akses tidak valid atau telah kedaluwarsa.';
    }
    if (lower == 'unauthorized' || lower.contains('unauthorized')) {
      return 'Sesi login telah berakhir atau akses ditolak. Silakan login kembali.';
    }
    if (lower == 'forbidden' || lower.contains('access forbidden')) {
      return 'Anda tidak memiliki izin untuk melakukan tindakan ini.';
    }
    if (lower == 'not found' || lower == 'endpoint not found') {
      return 'Layanan atau data yang diminta tidak ditemukan di server.';
    }
    if (lower == 'method not allowed') {
      return 'Metode pengiriman data tidak didukung oleh server.';
    }
    if (lower == 'internal server error') {
      return 'Terjadi kendala pada server STO. Silakan hubungi tim IT.';
    }
    return pesan;
  }

  static String _pesanStatusHttp(int status) {
    switch (status) {
      case 400:
        return 'Permintaan data tidak valid (HTTP 400).';
      case 401:
        return 'Sesi login telah berakhir (HTTP 401). Silakan login kembali.';
      case 403:
        return 'Akses ditolak (HTTP 403). Anda tidak memiliki izin.';
      case 404:
        return 'Layanan atau data tidak ditemukan di server (HTTP 404).';
      case 405:
        return 'Layanan ini belum didukung oleh server (HTTP 405).';
      case 408:
        return 'Waktu tunggu permintaan habis (HTTP 408). Sinyal lemah, coba lagi.';
      case 409:
        return 'Terdapat konflik status data pada server (HTTP 409).';
      case 500:
        return 'Terjadi kendala pada server STO (HTTP 500). Hubungi tim IT.';
      case 502:
        return 'Server STO tidak merespons (HTTP 502 - Bad Gateway).';
      case 503:
        return 'Server STO sedang sibuk atau dalam pemeliharaan (HTTP 503).';
      case 504:
        return 'Waktu koneksi ke server habis (HTTP 504 - Gateway Timeout).';
      default:
        return 'Permintaan gagal diproses (HTTP $status).';
    }
  }

  void close() => _client.close();
}
