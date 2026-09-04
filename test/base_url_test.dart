import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/config/app_config.dart';

/// Alamat server yang salah satu ruasnya kurang membuat SELURUH panggilan
/// dijawab 404 - dan gejalanya tidak terlihat seperti salah alamat, melainkan
/// seperti aplikasi yang rusak. Jadi bentuknya diuji, bukan dipercaya.
void main() {
  group('Pilihan alamat server', () {
    test('semuanya berakhir di /api', () {
      // Jalur endpoint ditulis sebagai '/sto/part-list', jadi base URL wajib
      // sudah memuat '/api'.
      for (final url in AppConfig.serverPilihan.values) {
        expect(url, endsWith('/api'), reason: url);
      }
    });

    test('tidak ada garis miring berlebih di ujung', () {
      for (final url in AppConfig.serverPilihan.values) {
        expect(url, isNot(endsWith('/api/')), reason: url);
      }
    });

    test('alamat bawaan termasuk salah satu pilihan', () {
      // Kalau bawaannya di luar daftar, layar Setting menampilkannya sebagai
      // alamat mentah yang tidak cocok pilihan mana pun.
      expect(
        AppConfig.serverPilihan.values,
        contains(AppConfig.defaultBaseUrl),
      );
    });

    test('bawaannya HTTPS', () {
      // Handheld baru bisa saja dinyalakan di luar jaringan pabrik; alamat
      // 192.168.10.67 hanya menjawab dari dalam, dan diamnya aplikasi tidak
      // memberi petunjuk apa pun soal itu.
      expect(AppConfig.defaultBaseUrl, startsWith('https://'));
    });
  });
}
