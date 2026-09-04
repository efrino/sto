import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/app_user.dart';

/// Riwayat scan disaring per NIK di sisi server; yang menentukan penyaringnya
/// adalah peran user.
///
/// Aturannya: operator hanya melihat hasil hitungnya sendiri (ia hanya
/// bertanggung jawab atas angkanya), admin melihat semuanya (dialah yang
/// memeriksa jalannya STO).
void main() {
  /// Menyalin aturan yang dipakai CountRepository.
  String? nikPenyaring(AppUser? user) =>
      (user?.isAdmin ?? false) ? null : user?.nik;

  test('operator disaring ke NIK-nya sendiri', () {
    const operator = AppUser(nik: 'M.9276', name: 'M.9276');
    expect(nikPenyaring(operator), 'M.9276');
  });

  test('admin tidak disaring - melihat seluruh riwayat', () {
    const admin = AppUser(nik: 'E.9948', name: 'E.9948', role: UserRole.admin);
    expect(nikPenyaring(admin), isNull);
  });

  test('tanpa sesi juga tidak menyaring apa pun', () {
    // Tidak ada NIK yang bisa dipakai; server yang memutuskan.
    expect(nikPenyaring(null), isNull);
  });
}
