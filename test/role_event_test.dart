import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/core/config/app_config.dart';
import 'package:sto_prep/data/models/app_user.dart';
import 'package:sto_prep/data/models/part_item.dart';
import 'package:sto_prep/data/models/sto_event.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/data/local/tag_dao.dart';
import 'package:sto_prep/data/repositories/tag_repository.dart';

void main() {
  group('Peran & izin area', () {
    const admin = AppUser(nik: 'A.10525', name: 'ADMIN', role: UserRole.admin);
    const operator = AppUser(
      nik: 'A.20431',
      name: 'OPERATOR',
      areas: ['WAREHOUSE 1', 'WAREHOUSE 2'],
    );

    test('admin tidak dibatasi area, operator dibatasi', () {
      expect(admin.isAdmin, isTrue);
      expect(admin.hasAreaLimit, isFalse);

      expect(operator.isAdmin, isFalse);
      expect(operator.hasAreaLimit, isTrue);
      expect(operator.areas, ['WAREHOUSE 1', 'WAREHOUSE 2']);
    });

    test('operator tanpa area yang diatur admin dianggap tanpa batas', () {
      const belumDiatur = AppUser(nik: 'X.1', name: 'BARU');
      expect(belumDiatur.hasAreaLimit, isFalse);
      expect(belumDiatur.areaLabel, 'Belum diatur');
    });

    test('daftar area diterima sebagai teks maupun list', () {
      expect(
        AppUser.parseAreas('warehouse 1, warehouse 2'),
        ['WAREHOUSE 1', 'WAREHOUSE 2'],
      );
      expect(AppUser.parseAreas(['wh 1', ' wh 2 ']), ['WH 1', 'WH 2']);
      expect(AppUser.parseAreas(null), isEmpty);
    });

    test('peran dibaca dari teks apa pun bentuknya', () {
      expect(UserRole.fromName('admin'), UserRole.admin);
      expect(UserRole.fromName('ADMIN'), UserRole.admin);
      expect(UserRole.fromName('operator'), UserRole.operator);
      expect(UserRole.fromName(null), UserRole.operator);
    });

    test('keputusan pembatalan hanya boleh oleh admin', () {
      // Aturan ini dijaga di repository, bukan cuma di layar: tombolnya sudah
      // disembunyikan untuk operator, tapi keputusannya terlalu mahal untuk
      // hanya bergantung pada tampilan.
      expect(
        () => TagRepository.pastikanAdmin(operator, 'menyetujui pengajuan'),
        throwsA(isA<TagStateException>()),
      );
      expect(
        () => TagRepository.pastikanAdmin(admin, 'menyetujui pengajuan'),
        returnsNormally,
      );
    });

    test('penolakan menyebut NIK dan perannya supaya jelas di layar', () {
      try {
        TagRepository.pastikanAdmin(operator, 'menolak pengajuan pembatalan');
        fail('seharusnya ditolak');
      } on TagStateException catch (e) {
        expect(e.message, contains('Hanya admin'));
        expect(e.message, contains('A.20431'));
        expect(e.message, contains('Operator'));
      }
    });

    test('baris tabel user bolak-balik tanpa kehilangan izin', () {
      final map = operator.toMap();
      final kembali = AppUser.fromMap(map);
      expect(kembali.nik, operator.nik);
      expect(kembali.areas, operator.areas);
      expect(kembali.role, UserRole.operator);
      expect(kembali.active, isTrue);
    });
  });

  group('Event STO', () {
    final event = StoEvent(
      id: 'STO-202609',
      name: 'STO SEPTEMBER 2026',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
      areas: const ['WAREHOUSE 1'],
      createdAt: DateTime(2026, 8, 30),
    );

    test('aktif hanya di dalam periode dan saat status buka', () {
      expect(event.isActiveOn(DateTime(2026, 9, 2)), isTrue);
      expect(event.isActiveOn(DateTime(2026, 9, 1)), isTrue);
      expect(event.isActiveOn(DateTime(2026, 9, 30)), isTrue);
      expect(event.isActiveOn(DateTime(2026, 8, 31)), isFalse);
      expect(event.isActiveOn(DateTime(2026, 10, 1)), isFalse);

      final ditutup = event.copyWith(status: StoEventStatus.closed);
      expect(ditutup.isActiveOn(DateTime(2026, 9, 2)), isFalse);
    });

    test('cakupan area kosong berarti semua area', () {
      expect(event.coversArea('WAREHOUSE 1'), isTrue);
      expect(event.coversArea('warehouse 1'), isTrue);
      expect(event.coversArea('WAREHOUSE 3'), isFalse);

      final semua = event.copyWith(areas: const []);
      expect(semua.coversArea('WAREHOUSE 3'), isTrue);
    });
  });

  group('Alur pembatalan bertingkat', () {
    final tag = StoTag.fromPart(
      part: const PartItem(
        partNumber: '48601-BZ010',
        jobNumber: 'JOB-2620',
        partName: 'BRACKET SUSPENSION UPPER',
        area: 'WAREHOUSE 2',
      ),
      tagNo: 'STO260902-000010',
      sequence: 10,
      batchId: 'B1',
      createdBy: 'A.20431',
      createdAt: DateTime(2026, 9, 2, 8),
      eventId: 'STO-202609',
    );

    test('tag menyimpan event tempat ia dibuat', () {
      expect(tag.eventId, 'STO-202609');
      expect(tag.toApiJson()['event_id'], 'STO-202609');
    });

    test('belum tercetak: tidak bisa diajukan batal', () {
      expect(tag.isPrintable, isTrue);
      expect(tag.canRequestCancel, isFalse);
      expect(tag.canBeCancelledByAdmin, isFalse);
    });

    test('sudah tercetak: operator mengajukan, admin bisa langsung batal', () {
      final printed = tag.copyWith(
        status: TagStatus.printed,
        printedAt: DateTime(2026, 9, 2, 8, 1),
      );
      expect(printed.canRequestCancel, isTrue);
      expect(printed.canBeCancelledByAdmin, isTrue);
      expect(printed.isPrintable, isFalse);
    });

    test('sedang diajukan: menunggu admin, bukan operator lagi', () {
      final diajukan = tag.copyWith(
        status: TagStatus.pendingCancel,
        cancelRequestedBy: 'A.20431',
        cancelRequestedAt: DateTime(2026, 9, 2, 9),
        cancelReason: 'Mispart - part tidak sesuai',
      );
      expect(diajukan.isPendingCancel, isTrue);
      expect(diajukan.canRequestCancel, isFalse);
      expect(diajukan.canBeCancelledByAdmin, isTrue);
      expect(diajukan.cancelRequestedBy, 'A.20431');
    });

    test('sudah dibatalkan: status akhir', () {
      final batal = tag.copyWith(
        status: TagStatus.cancelled,
        cancelApprovedBy: 'A.10525',
      );
      expect(batal.canRequestCancel, isFalse);
      expect(batal.canBeCancelledByAdmin, isFalse);
      expect(batal.isPrintable, isFalse);
      expect(batal.cancelApprovedBy, 'A.10525');
    });

    test('jejak pengajuan ikut tersimpan di baris database', () {
      final diajukan = tag.copyWith(
        status: TagStatus.pendingCancel,
        cancelRequestedBy: 'A.20431',
        cancelRequestedAt: DateTime(2026, 9, 2, 9),
      );
      final kembali = StoTag.fromMap(diajukan.toMap());
      expect(kembali.status, TagStatus.pendingCancel);
      expect(kembali.cancelRequestedBy, 'A.20431');
      expect(kembali.eventId, 'STO-202609');
    });
  });

  group('Event dari backend STO', () {
    test('bentuk server (id_event, event_name, status 1/0) dibaca benar', () {
      final event = StoEvent.fromServer({
        'id_event': 5,
        'event_name': 'STO Internal HMMI IFPD',
        'start_date': '2026-09-03',
        'end_date': '2026-09-30',
        'status': 1,
        'total_tag': 0,
      });

      expect(event.id, '5');
      expect(event.name, 'STO Internal HMMI IFPD');
      expect(event.isOpen, isTrue);
      expect(event.isActiveOn(DateTime(2026, 9, 10)), isTrue);
      expect(event.isActiveOn(DateTime(2026, 10, 1)), isFalse);
    });

    test('status 0 berarti tutup', () {
      final event = StoEvent.fromServer({
        'id_event': 2,
        'event_name': 'STO - ADM SAP Non GPart',
        'start_date': '2026-09-12',
        'end_date': '2026-08-05',
        'status': 0,
      });
      expect(event.isOpen, isFalse);
      expect(event.isActiveOn(DateTime(2026, 9, 12)), isFalse);
    });

    test('end_date kosong berarti belum ditentukan, bukan berakhir hari itu', () {
      final event = StoEvent.fromServer({
        'id_event': 5,
        'event_name': 'STO tanpa tanggal selesai',
        'start_date': '2026-09-03',
        'end_date': '',
        'status': 1,
      });

      expect(event.tanpaTanggalSelesai, isTrue);
      expect(event.periodLabel, contains('belum ditentukan'));
      // Tetap aktif berhari-hari sesudah tanggal mulai.
      expect(event.isActiveOn(DateTime(2026, 12, 31)), isTrue);
    });
  });

  group('Identitas akun STO', () {
    // Tabel `users` di server hanya menyimpan nik, role, permissions, tim,
    // dan device_id - tidak ada nama/departemen/seksi. Form admin pun tidak
    // lagi menanyakannya, jadi NIK sekaligus menjadi identitas yang tampil.
    test('user dari server memakai NIK sebagai nama', () {
      final user = AppUser.fromJson({
        'nik': 'A.20431',
        'role': 'operator',
        'tim': 'B',
        'permissions': ['scan', 'cancel'],
        'area': ['IFPD'],
      });

      expect(user.nik, 'A.20431');
      expect(user.team, 'B');
      expect(user.permissions, [AppPermission.scan, AppPermission.cancel]);
      expect(user.areas, ['IFPD']);
      expect(user.canPrepare, isFalse);
    });

    test('permissions kosong dari server berarti belum diatur admin', () {
      final user = AppUser.fromJson({
        'nik': 'A.20431',
        'role': 'operator',
        'permissions': <String>[],
      });
      // Daftar kosong tidak sama dengan "tidak punya akses apa pun" - itu
      // ditangani HttpStoApi, yang membuka semua menu selama admin belum
      // mengaturnya.
      expect(user.permissions, isEmpty);
    });
  });

  group('Hanya satu event berjalan', () {
    StoEvent buat(String id, String nama, StoEventStatus status) => StoEvent(
          id: id,
          name: nama,
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 30),
          status: status,
          createdAt: DateTime(2026, 9, 1),
        );

    test('server menandai yang lain ditutup lewat status "confirm"', () {
      // Bentuk balasan yang ditahan server sebelum ada yang berubah.
      final balasan = {
        'status': 'confirm',
        'message': 'Hanya boleh ada satu event berjalan. Saat ini masih '
            'berjalan: #5 STO Internal HMMI IFPD.',
        'berjalan': [
          {'id_event': 5, 'event_name': 'STO Internal HMMI IFPD', 'status': 1},
        ],
      };

      expect(balasan['status'], 'confirm');
      final berjalan = (balasan['berjalan'] as List)
          .map((e) => StoEvent.fromServer(e as Map<String, dynamic>))
          .toList();
      expect(berjalan.single.isOpen, isTrue);
      expect(berjalan.single.id, '5');
    });

    test('event yang ditutup tidak lagi dianggap aktif hari ini', () {
      final berjalan = buat('5', 'BERJALAN', StoEventStatus.open);
      final ditutup = berjalan.copyWith(status: StoEventStatus.closed);

      expect(berjalan.isActiveOn(DateTime(2026, 9, 10)), isTrue);
      expect(ditutup.isActiveOn(DateTime(2026, 9, 10)), isFalse);
    });
  });

  group('Area STO', () {
    test('lima area master server dipakai apa adanya', () {
      // Nilainya harus sama persis dengan majsf_sto.master_data.area -
      // termasuk WELD (bukan "WELDING"), karena dipakai menyaring part.
      expect(AppConfig.areaSto, ['IFRM', 'PRESS', 'IFPP', 'WELD', 'IFPD']);
    });

    test('user boleh punya lebih dari satu area', () {
      const user = AppUser(
        nik: 'A.20431',
        name: 'A.20431',
        areas: ['IFPD', 'IFPP'],
      );

      expect(user.hasAreaLimit, isTrue);
      expect(user.areas.length, 2);
      expect(user.areaLabel, 'IFPD, IFPP');
      expect(user.toMap()['areas'], 'IFPD,IFPP');
      expect(AppUser.fromMap(user.toMap()).areas, ['IFPD', 'IFPP']);
    });

    test('area dari server dibaca sebagai daftar', () {
      final user = AppUser.fromJson({
        'nik': 'A.20431',
        'role': 'operator',
        'area': ['IFRM', 'WELD'],
      });
      expect(user.areas, ['IFRM', 'WELD']);
    });
  });

  group('Tim penghitung', () {
    test('pilihannya enum server: A dan B saja', () {
      // Kolom `majsf_sto.users.tim` bertipe enum('A','B'); menambah tim
      // ketiga berarti mengubah tipe kolomnya lebih dulu, bukan menambah
      // baris di aplikasi.
      expect(AppConfig.timSto, ['A', 'B']);
    });

    test('tim pada user dibaca dari nilai enum itu', () {
      final user = AppUser.fromJson({
        'nik': 'A.20431',
        'role': 'counter',
        'tim': 'b',
      });
      expect(user.team, 'B');
      expect(AppConfig.timSto.contains(user.team), isTrue);
    });
  });

  group('Master part dari part-list', () {
    test('baris server dipetakan apa adanya', () {
      final part = PartItem.fromServer({
        'id_item': 7073,
        'area': 'IFPD',
        'job_number': 'GT-3151',
        'part_number': '',
        'material_description': 'RAIL, ROOF SIDE, INNER RH',
        'type': 'FP',
        'status_part': 'REGULER',
        'customer': 'ADM',
        'model': 'D40D',
      });

      expect(part.area, 'IFPD');
      expect(part.jobNumber, 'GT-3151');
      expect(part.partType, 'FP');
      // part_number boleh kosong di master - jangan dijadikan syarat.
      expect(part.partNumber, isEmpty);
      expect(part.displayTitle, 'GT-3151');
    });

    test('status_part bukan FP/WIP, jadi tidak dipakai sebagai tipe tag', () {
      final part = PartItem.fromServer({
        'area': 'WELD',
        'job_number': 'X1',
        'part_number': '48601-BZ010',
        'type': 'WIP',
        'status_part': 'REGULER',
      });
      expect(part.partType, 'WIP');
    });
  });
}
