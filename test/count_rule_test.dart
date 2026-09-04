import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/app_user.dart';
import 'package:sto_prep/data/models/sto_count.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/data/repositories/count_repository.dart';

void main() {
  group('Hasil hitung STO', () {
    final count = StoCount(
      tagNo: 'STO260903-000010',
      nik: 'A.20431',
      team: 'A',
      qty: 24,
      partNumber: '48601-BZ010',
      jobNumber: 'JOB-2620',
      partName: 'BRACKET SUSPENSION UPPER',
      area: 'WAREHOUSE 2',
      countedAt: DateTime(2026, 9, 3, 8, 10),
    );

    test('payload POST memuat nik, tag, tim, dan qty', () {
      final payload = count.toApiJson();
      expect(payload['nik'], 'A.20431');
      expect(payload['tag_no'], 'STO260903-000010');
      expect(payload['tim'], 'A');
      expect(payload['qty'], 24);
    });

    test('baris database bolak-balik tanpa kehilangan data', () {
      final kembali = StoCount.fromMap(count.toMap());
      expect(kembali.tagNo, count.tagNo);
      expect(kembali.team, 'A');
      expect(kembali.qty, 24);
      expect(kembali.syncStatus, SyncStatus.pending);
      expect(kembali.pernahDikoreksi, isFalse);
    });

    test('koreksi menandai waktu perubahan dan antre kirim ulang', () {
      final dikoreksi = count.copyWith(
        qty: 26,
        updatedAt: DateTime(2026, 9, 3, 9),
        syncStatus: SyncStatus.pending,
      );
      expect(dikoreksi.qty, 26);
      expect(dikoreksi.pernahDikoreksi, isTrue);
      expect(dikoreksi.toApiJson()['qty'], 26);
    });
  });

  group('Tim pada data user', () {
    test('tim wajib ada sebelum boleh mencatat', () {
      const tanpaTim = AppUser(nik: 'A.1', name: 'OPERATOR');
      expect(tanpaTim.hasTeam, isFalse);
      expect(tanpaTim.teamLabel, 'Tim belum diatur');

      const denganTim = AppUser(nik: 'A.1', name: 'OPERATOR', team: 'A');
      expect(denganTim.hasTeam, isTrue);
      expect(denganTim.teamLabel, 'TIM A');
    });

    test('tim ikut tersimpan di baris user dan payload login', () {
      const user = AppUser(nik: 'A.20431', name: 'BUDI', team: 'A');
      expect(user.toMap()['team'], 'A');
      expect(AppUser.fromMap(user.toMap()).team, 'A');
      // Nilai lama "TIM B" dan penulisan huruf kecil ikut diseragamkan.
      expect(AppUser.fromJson({'nik': 'X', 'name': 'Y', 'tim': 'tim b'}).team,
          'B');
      expect(AppUser.fromMap({'nik': 'X', 'name': 'Y', 'team': 'TIM A'}).team,
          'A');
    });

    test('hak akses menu mengikuti pemberian admin', () {
      const penuh = AppUser(nik: 'A.1', name: 'OPERATOR');
      expect(penuh.canPrepare, isTrue);
      expect(penuh.canScan, isTrue);
      expect(penuh.canCancel, isTrue);

      const hanyaScan = AppUser(
        nik: 'A.2',
        name: 'OPERATOR',
        permissions: [AppPermission.scan],
      );
      expect(hanyaScan.canScan, isTrue);
      expect(hanyaScan.canPrepare, isFalse);
      expect(hanyaScan.canCancel, isFalse);

      // Admin tetap punya semuanya walau daftar izinnya kosong.
      const admin = AppUser(
        nik: 'A.3',
        name: 'ADMIN',
        role: UserRole.admin,
        permissions: [],
      );
      expect(admin.canPrepare, isTrue);
      expect(admin.canCancel, isTrue);
    });

    test('izin bolak-balik lewat baris database dan JSON', () {
      const user = AppUser(
        nik: 'A.4',
        name: 'OPERATOR',
        permissions: [AppPermission.prepare, AppPermission.cancel],
      );
      expect(user.toMap()['permissions'], 'prepare,cancel');
      expect(
        AppUser.fromMap(user.toMap()).permissions,
        [AppPermission.prepare, AppPermission.cancel],
      );
      // Baris lama tanpa kolom permissions dianggap punya semua akses.
      expect(
        AppUser.fromMap({'nik': 'X', 'name': 'Y'}).permissions,
        AppPermission.values,
      );
    });
  });

  group('Tag yang boleh dihitung', () {
    ScannedTag tag(TagStatus? status) => ScannedTag(
          tagNo: 'STO260903-000010',
          partNumber: '48601-BZ010',
          jobNumber: 'JOB-2620',
          partName: 'BRACKET SUSPENSION UPPER',
          area: 'WAREHOUSE 2',
          status: status,
        );

    test('hanya tag yang benar-benar tercetak yang boleh dihitung', () {
      expect(tag(TagStatus.printed).bolehDihitung, isTrue);
      expect(tag(TagStatus.draft).bolehDihitung, isFalse);
      expect(tag(TagStatus.pendingCancel).bolehDihitung, isFalse);
      expect(tag(TagStatus.cancelled).bolehDihitung, isFalse);
    });

    test('tag yang dibatalkan menjelaskan alasannya ke operator', () {
      expect(
        tag(TagStatus.cancelled).alasanTidakBolehDihitung,
        contains('DIBATALKAN'),
      );
      expect(
        tag(TagStatus.pendingCancel).alasanTidakBolehDihitung,
        contains('menunggu keputusan admin'),
      );
      expect(tag(TagStatus.printed).alasanTidakBolehDihitung, isEmpty);
    });

    test('tag milik perangkat lain (status belum diketahui) tetap boleh', () {
      expect(tag(null).bolehDihitung, isTrue);
    });
  });
}
