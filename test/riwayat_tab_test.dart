import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/app_user.dart';
import 'package:sto_prep/data/models/print_entry.dart';
import 'package:sto_prep/data/models/sto_count.dart';
import 'package:sto_prep/features/history/riwayat_page.dart';
import 'package:sto_prep/features/history/sto_history_page.dart';

/// Isi halaman Riwayat mengikuti IZIN, bukan peran.
///
/// Tag STO kini satu daftar - cetak, scan, dan pembatalan adalah kejadian pada
/// tag yang sama - jadi yang mengikuti izin bukan lagi jumlah tab, melainkan
/// baris dan saringan di dalamnya.
void main() {
  AppUser userDengan(List<AppPermission> izin) => AppUser(
        nik: 'M.9276',
        name: 'M.9276',
        permissions: izin,
      );

  group('Tab riwayat mengikuti izin', () {
    test('izin tag STO apa pun menghasilkan satu tab STO', () {
      for (final izin in [
        AppPermission.prepare,
        AppPermission.scan,
        AppPermission.cancel,
      ]) {
        final tabs = RiwayatPage.tabsUntuk(userDengan([izin]));

        expect(tabs.length, 1, reason: 'izin $izin');
        expect(tabs.single.label, 'STO');
        expect(tabs.single.judul, 'Riwayat Tag STO');
      }
    });

    test('ketiga izin tag STO tetap satu tab, bukan tiga', () {
      final tabs = RiwayatPage.tabsUntuk(
        userDengan([
          AppPermission.prepare,
          AppPermission.scan,
          AppPermission.cancel,
        ]),
      );

      expect(tabs.map((t) => t.label), ['STO']);
    });

    test('izin Tag OK menambah tab kedua', () {
      final tabs = RiwayatPage.tabsUntuk(
        userDengan([AppPermission.prepare, AppPermission.scanOk]),
      );

      expect(tabs.map((t) => t.label), ['STO', 'Tag OK']);
    });

    test('admin melihat keduanya tanpa izin disebut satu per satu', () {
      // `can()` meloloskan admin untuk semua izin - jadi tabnya lengkap walau
      // daftar permissions-nya kosong.
      final tabs = RiwayatPage.tabsUntuk(
        const AppUser(nik: 'E.9948', name: 'ADMIN', role: UserRole.admin),
      );

      expect(tabs.map((t) => t.label), ['STO', 'Tag OK']);
    });

    test('tab Tag OK muncul dari izin Tag OK saja, bukan izin tag STO', () {
      // Izin tag STO tidak membawa serta Tag OK: petugasnya sering beda orang.
      expect(
        RiwayatPage.tabsUntuk(userDengan([AppPermission.prepare]))
            .map((t) => t.label),
        ['STO'],
      );
      expect(
        RiwayatPage.tabsUntuk(userDengan([AppPermission.cancelOk]))
            .map((t) => t.label),
        ['Tag OK'],
      );
    });

    test('tanpa izin sama sekali -> tidak ada isi yang boleh dibuka', () {
      expect(RiwayatPage.tabsUntuk(userDengan([])), isEmpty);
      expect(RiwayatPage.tabsUntuk(null), isEmpty);
    });

    test('tombol sinkron hanya ikut bila user memang mencatat hasil hitung',
        () {
      // Tombol itu menyinkronkan hasil scan; bagi yang hanya mencetak, tidak
      // ada yang perlu dikirim.
      expect(
        RiwayatPage.tabsUntuk(userDengan([AppPermission.prepare])).single.aksi,
        isEmpty,
      );
      expect(
        RiwayatPage.tabsUntuk(userDengan([AppPermission.scan])).single.aksi,
        hasLength(1),
      );
    });
  });

  group('Saringan riwayat STO mengikuti izin', () {
    test('yang hanya mencetak tidak ditawari saringan scan', () {
      final saringan = SaringanSto.untuk(userDengan([AppPermission.prepare]));

      expect(saringan, contains(SaringanSto.belumCetak));
      expect(saringan, contains(SaringanSto.gagal));
      expect(saringan, isNot(contains(SaringanSto.discan)));
      expect(saringan, isNot(contains(SaringanSto.pembatalan)));
    });

    test('Semua selalu ada, dan admin mendapat seluruh saringan', () {
      expect(
        SaringanSto.untuk(userDengan([AppPermission.scan])).first,
        SaringanSto.semua,
      );
      expect(
        SaringanSto.untuk(
          const AppUser(nik: 'E.9948', name: 'ADMIN', role: UserRole.admin),
        ),
        SaringanSto.values,
      );
    });

    test('tanpa user tidak ada saringan sama sekali', () {
      expect(SaringanSto.untuk(null), isEmpty);
    });
  });

  group('Daftar gabungan riwayat STO', () {
    final pagi = DateTime(2026, 9, 4, 7);
    final siang = DateTime(2026, 9, 4, 12);
    final sore = DateTime(2026, 9, 4, 16);

    PrintEntry cetak({
      String tagNo = 'STO260904-001',
      PrintState state = PrintState.printed,
      bool canceled = false,
      bool diajukan = false,
      DateTime? printedAt,
    }) =>
        PrintEntry(
          tagNo: tagNo,
          area: 'IFPP',
          state: state,
          canceled: canceled,
          cancelRequestedAt: diajukan ? siang : null,
          cancelRequestedBy: diajukan ? 'M.9276' : '',
          printedAt: printedAt ?? pagi,
          createdBy: 'M.9276',
          createdAt: pagi,
        );

    StoCount hitung({String tagNo = 'STO260904-001', DateTime? waktu}) =>
        StoCount(
          tagNo: tagNo,
          nik: 'M.9276',
          team: 'A',
          qty: 34,
          countedAt: waktu ?? siang,
        );

    test('kejadian pada tag yang sama menyambung menurut waktu', () {
      final baris = BarisRiwayatSto.gabung(
        user: userDengan([AppPermission.prepare, AppPermission.scan]),
        cetak: [cetak(printedAt: pagi)],
        hitung: [hitung(waktu: sore)],
      );

      // Terbaru lebih dulu: hasil hitung sore di atas cetakan pagi.
      expect(baris.length, 2);
      expect(baris.first.hitung, isNotNull);
      expect(baris.last.cetak, isNotNull);
    });

    test('baris hitung tidak muncul untuk user tanpa izin scan', () {
      final baris = BarisRiwayatSto.gabung(
        user: userDengan([AppPermission.prepare]),
        cetak: [cetak()],
        hitung: [hitung()],
      );

      expect(baris, hasLength(1));
      expect(baris.single.cetak, isNotNull);
    });

    test('izin batal saja hanya membuka baris pembatalannya', () {
      // Yang berhak membatalkan tidak otomatis boleh membaca seluruh riwayat
      // cetak orang lain - yang ia butuhkan hanya tag yang batal.
      final baris = BarisRiwayatSto.gabung(
        user: userDengan([AppPermission.cancel]),
        cetak: [
          cetak(tagNo: 'STO260904-001'),
          cetak(tagNo: 'STO260904-002', canceled: true),
          cetak(tagNo: 'STO260904-003', diajukan: true),
        ],
        hitung: [hitung()],
      );

      expect(
        baris.map((b) => b.tagNo).toSet(),
        {'STO260904-002', 'STO260904-003'},
      );
    });

    test('tanpa user daftarnya kosong, bukan seluruh riwayat', () {
      expect(
        BarisRiwayatSto.gabung(
          user: null,
          cetak: [cetak()],
          hitung: [hitung()],
        ),
        isEmpty,
      );
    });

    test('saringan memilah jenis baris yang benar', () {
      final semua = BarisRiwayatSto.gabung(
        user: userDengan([
          AppPermission.prepare,
          AppPermission.scan,
          AppPermission.cancel,
        ]),
        cetak: [
          cetak(tagNo: 'A', state: PrintState.draft),
          cetak(tagNo: 'B', state: PrintState.error),
          cetak(tagNo: 'C', canceled: true),
        ],
        hitung: [hitung(tagNo: 'D')],
      );

      List<String> tag(SaringanSto s) =>
          semua.where((b) => b.cocok(s)).map((b) => b.tagNo).toList();

      expect(tag(SaringanSto.semua), hasLength(4));
      expect(tag(SaringanSto.belumCetak), ['A']);
      expect(tag(SaringanSto.gagal), ['B']);
      expect(tag(SaringanSto.pembatalan), ['C']);
      expect(tag(SaringanSto.discan), ['D']);
    });

    test('tag batal tidak ikut terhitung sebagai belum cetak', () {
      // Tag yang dibatalkan selagi berstatus draft tetap "belum cetak" secara
      // teknis; menampilkannya di sana membuat orang mencoba mencetak ulang
      // sesuatu yang sudah dibatalkan.
      final baris = BarisRiwayatSto.gabung(
        user: userDengan([AppPermission.prepare]),
        cetak: [cetak(state: PrintState.draft, canceled: true)],
        hitung: const [],
      );

      expect(baris.single.cocok(SaringanSto.belumCetak), isFalse);
      expect(baris.single.cocok(SaringanSto.pembatalan), isTrue);
    });
  });
}
