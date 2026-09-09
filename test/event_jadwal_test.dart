import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/sto_event.dart';

/// Keterangan jadwal event pada kartu Setting > Event.
///
/// Yang diuji di sini bukan tampilannya, melainkan hal yang selama ini tidak
/// terlihat: event berstatus BUKA yang tanggalnya sudah lewat. Dari daftar ia
/// tampak sehat, dan admin baru tahu ada yang salah setelah operator melapor
/// tagnya ditolak.
void main() {
  StoEvent buat({
    required DateTime mulai,
    required DateTime selesai,
    StoEventStatus status = StoEventStatus.open,
  }) =>
      StoEvent(
        id: '1',
        name: 'ALL CUSTOMER',
        startDate: mulai,
        endDate: selesai,
        status: status,
        createdAt: DateTime(2026, 1, 1),
      );

  final kini = DateTime(2026, 9, 7, 10, 30);

  group('Jadwal event terhadap hari ini', () {
    test('periode yang menaungi hari ini disebut berlangsung', () {
      final e = buat(
        mulai: DateTime(2026, 9, 6),
        selesai: DateTime(2026, 9, 9),
      );

      expect(e.jadwalPada(kini), JadwalEvent.berjalan);
      expect(e.selisihHari(kini), 0);
      expect(e.jadwalLabel(kini), 'Berlangsung, sisa 2 hari');
    });

    test('hari terakhir disebut apa adanya, bukan "sisa 0 hari"', () {
      final e = buat(
        mulai: DateTime(2026, 9, 1),
        selesai: DateTime(2026, 9, 7),
      );

      expect(e.jadwalLabel(kini), 'Hari terakhir');
    });

    test('periode yang belum mulai menyebut berapa hari lagi', () {
      final e = buat(
        mulai: DateTime(2026, 9, 10),
        selesai: DateTime(2026, 9, 12),
      );

      expect(e.jadwalPada(kini), JadwalEvent.akanDatang);
      expect(e.selisihHari(kini), 3);
      expect(e.jadwalLabel(kini), 'Mulai 3 hari lagi');
    });

    test('besok dan kemarin disebut dengan katanya, bukan angka 1', () {
      expect(
        buat(mulai: DateTime(2026, 9, 8), selesai: DateTime(2026, 9, 9))
            .jadwalLabel(kini),
        'Mulai besok',
      );
      expect(
        buat(mulai: DateTime(2026, 9, 1), selesai: DateTime(2026, 9, 6))
            .jadwalLabel(kini),
        'Sudah lewat kemarin',
      );
    });

    test('status BUKA tidak menutupi periode yang sudah lewat', () {
      // Inilah keadaan yang membuat operator kebingungan: event terdaftar
      // BUKA, tapi tanggalnya habis pekan lalu.
      final e = buat(
        mulai: DateTime(2026, 8, 30),
        selesai: DateTime(2026, 9, 2),
      );

      expect(e.isOpen, isTrue);
      expect(e.isActiveOn(kini), isFalse);
      expect(e.jadwalPada(kini), JadwalEvent.terlewat);
      expect(e.jadwalLabel(kini), 'Sudah lewat 5 hari lalu');
    });

    test('periode tanpa tanggal selesai tidak pernah dianggap lewat', () {
      final e = buat(
        mulai: DateTime(2026, 9, 1),
        selesai: StoEvent.tanpaBatas,
      );

      expect(e.jadwalPada(kini), JadwalEvent.berjalan);
      expect(e.jadwalLabel(kini), 'Berlangsung hari ini');
    });

    test('event mendatang dan yang lewat bisa dipilih dari daftar', () {
      // Urutan yang dipakai kartu beranda: yang berjalan, lalu yang paling
      // dekat akan mulai, terakhir yang paling baru saja lewat. Yang diuji di
      // sini kuncinya - tanggal mana yang dipakai mengurutkan.
      final daftar = [
        buat(mulai: DateTime(2026, 8, 1), selesai: DateTime(2026, 8, 3)),
        buat(mulai: DateTime(2026, 9, 20), selesai: DateTime(2026, 9, 21)),
        buat(mulai: DateTime(2026, 9, 12), selesai: DateTime(2026, 9, 13)),
        buat(mulai: DateTime(2026, 9, 2), selesai: DateTime(2026, 9, 4)),
      ];

      final akanDatang = daftar
          .where((e) => e.jadwalPada(kini) == JadwalEvent.akanDatang)
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      expect(akanDatang.first.startDate, DateTime(2026, 9, 12));

      final lewat = daftar
          .where((e) => e.jadwalPada(kini) == JadwalEvent.terlewat)
          .toList()
        ..sort((a, b) => b.endDate.compareTo(a.endDate));
      expect(lewat.first.endDate, DateTime(2026, 9, 4));
    });

    test('izin cetak terpisah dari status buka/tutup', () {
      // Menjelang akhir pelaksanaan, pencetakan tag dihentikan lebih dulu
      // sementara hasil hitung masih masuk berjam-jam. Kalau keduanya jadi
      // satu saklar, menutup pencetakan ikut menutup perhitungannya.
      final berjalan = buat(
        mulai: DateTime(2026, 9, 6),
        selesai: DateTime(2026, 9, 9),
      );
      expect(berjalan.bolehCetak, isTrue);
      expect(berjalan.bolehSiapkanPada(kini), isTrue);
      expect(berjalan.alasanTidakBolehSiapkan(kini), isEmpty);

      final cetakDitutup = berjalan.copyWith(bolehCetak: false);
      expect(cetakDitutup.isActiveOn(kini), isTrue, reason: 'tetap berjalan');
      expect(cetakDitutup.bolehSiapkanPada(kini), isFalse);
      expect(
        cetakDitutup.alasanTidakBolehSiapkan(kini),
        contains('Hasil hitung tetap bisa dikirim'),
      );
    });

    test('sebab tidak boleh menyiapkan disebut satu per satu', () {
      // "Tidak bisa mencetak" tanpa keterangan membuat operator menyangka
      // printernya rusak, lalu ia mencabut-sambung printer yang sehat.
      final belumMulai = buat(
        mulai: DateTime(2026, 9, 10),
        selesai: DateTime(2026, 9, 12),
      );
      expect(
        belumMulai.alasanTidakBolehSiapkan(kini),
        contains('Mulai 3 hari lagi'),
      );

      final ditutup = buat(
        mulai: DateTime(2026, 9, 6),
        selesai: DateTime(2026, 9, 9),
        status: StoEventStatus.closed,
      );
      expect(
        ditutup.alasanTidakBolehSiapkan(kini),
        contains('ditutup admin'),
      );
    });

    test('kolom yang belum dikirim server lama dibaca sebagai BOLEH', () {
      // Deployment /sto yang lama tidak mengirim allow_print sama sekali.
      // Menganggap ketiadaannya sebagai "dilarang" akan mengunci seluruh
      // handheld yang masih menunjuk ke sana.
      final lama = StoEvent.fromServer({
        'id_event': 8,
        'event_name': 'TESTING EVENT STO',
        'start_date': '2026-09-01',
        'end_date': '2026-09-30',
        'status': 1,
      });
      expect(lama.bolehCetak, isTrue);
      expect(lama.totalTim, 2);

      final baru = StoEvent.fromServer({
        'id_event': 8,
        'event_name': 'TESTING EVENT STO',
        'start_date': '2026-09-01',
        'end_date': '2026-09-30',
        'status': 1,
        'allow_print': 0,
        'total_tim': 1,
      });
      expect(baru.bolehCetak, isFalse);
      expect(baru.totalTim, 1);
    });

    test('izin cetak bolak-balik lewat cache perangkat', () {
      final asal = buat(
        mulai: DateTime(2026, 9, 6),
        selesai: DateTime(2026, 9, 9),
      ).copyWith(bolehCetak: false, totalTim: 1);

      final kembali = StoEvent.fromMap(asal.toMap());
      expect(kembali.bolehCetak, isFalse);
      expect(kembali.totalTim, 1);
    });

    test('jadwal dihitung dari tanggal, bukan jam', () {
      // Event yang mulai hari ini tetap "berlangsung" walau jam mulainya
      // tercatat lewat tengah hari.
      final e = buat(
        mulai: DateTime(2026, 9, 7, 20, 30),
        selesai: DateTime(2026, 9, 8, 7),
      );

      expect(e.jadwalPada(kini), JadwalEvent.berjalan);
      expect(e.berjalanPada(kini), isTrue);
    });
  });
}
