import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/app_user.dart';

/// Hak akses milik server. Dulu daftar kosong dari server diperlakukan sebagai
/// "semua menu terbuka" - akibatnya admin mencabut semua centang, tersimpan
/// kosong di server, lalu dibaca kembali sebagai semua menu: suntingannya
/// seolah tidak pernah tersimpan.
void main() {
  group('Hak akses dari server', () {
    test('daftar kosong berarti belum diberi akses, bukan semua menu', () {
      const user = AppUser(nik: 'M.9276', name: 'M.9276', permissions: []);

      expect(user.permissions, isEmpty);
      expect(user.canPrepare, isFalse);
      expect(user.canScan, isFalse);
      expect(user.canCancel, isFalse);
      expect(user.permissionLabel, 'Belum diberi akses');
    });

    test('admin tetap terbuka walau daftarnya kosong', () {
      // Admin tidak pernah dibatasi menu; itu ditegakkan di can(), bukan
      // dengan mengisi daftar izinnya.
      const admin = AppUser(
        nik: 'E.9948',
        name: 'E.9948',
        role: UserRole.admin,
        permissions: [],
      );

      expect(admin.canPrepare, isTrue);
      expect(admin.canScan, isTrue);
      expect(admin.canCancel, isTrue);
    });

    test('izin sebagian dibaca apa adanya', () {
      const user = AppUser(
        nik: 'M.9276',
        name: 'M.9276',
        permissions: [AppPermission.prepare],
      );

      expect(user.canPrepare, isTrue);
      expect(user.canScan, isFalse);
    });

    test('teks izin dipakai daftar user', () {
      const user = AppUser(
        nik: 'A.10525',
        name: 'A.10525',
        permissions: [AppPermission.prepare, AppPermission.scan],
      );
      expect(user.permissionLabel, contains(AppPermission.prepare.label));
      expect(user.permissionLabel, contains(AppPermission.scan.label));
    });

    test('perubahan izin terbawa lewat penyegaran sesi, bukan login ulang',
        () async {
      // Yang disegarkan adalah objek user-nya; menu di halaman utama membaca
      // izin dari sini, jadi begitu objeknya berganti menunya ikut berganti.
      const sebelum = AppUser(
        nik: 'M.9276',
        name: 'M.9276',
        permissions: [AppPermission.prepare],
      );
      const sesudah = AppUser(
        nik: 'M.9276',
        name: 'M.9276',
        permissions: [AppPermission.prepare, AppPermission.scan],
      );

      expect(sebelum.canScan, isFalse);
      expect(sesudah.canScan, isTrue);
      expect(sesudah.nik, sebelum.nik, reason: 'akun yang sama, izin berbeda');
    });
  });
  group('Izin Tag OK terpisah dari tag STO', () {
    test('izin tag STO tidak membawa serta izin Tag OK', () {
      const user = AppUser(
        nik: 'M.9276',
        name: 'OPERATOR',
        permissions: [AppPermission.prepare, AppPermission.scan],
      );

      expect(user.canPrepare, isTrue);
      // Petugas Tag OK sering orang yang berbeda, jadi izinnya tidak boleh
      // menetes dari izin tag STO.
      expect(user.canPrepareOk, isFalse);
      expect(user.canScanOk, isFalse);
      expect(user.punyaTagOk, isFalse);
    });

    test('satu izin Tag OK sudah membuka menunya', () {
      const user = AppUser(
        nik: 'M.9276',
        name: 'OPERATOR',
        permissions: [AppPermission.cancelOk],
      );

      expect(user.punyaTagOk, isTrue);
      expect(user.canCancelOk, isTrue);
      expect(user.canScanOk, isFalse);
      expect(user.canCancel, isFalse);
    });

    test('admin memegang semua izin Tag OK tanpa disebut', () {
      const admin = AppUser(
        nik: 'F.9964',
        name: 'ADMIN',
        role: UserRole.admin,
        permissions: [],
      );

      expect(admin.canPrepareOk, isTrue);
      expect(admin.canScanOk, isTrue);
      expect(admin.canCancelOk, isTrue);
    });

    test('nama izin bertahan bolak-balik lewat server', () {
      final izin = AppPermission.parse('prepareOk,scanOk,cancelOk');

      expect(izin, [
        AppPermission.prepareOk,
        AppPermission.scanOk,
        AppPermission.cancelOk,
      ]);
    });
  });
}
