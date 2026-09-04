import 'print_entry.dart';
import 'sto_tag.dart';

/// Hasil hitung satu tim atas sebuah tag.
class HasilHitung {
  const HasilHitung({
    required this.tim,
    required this.nik,
    required this.qty,
    this.waktu,
  });

  final String tim;
  final String nik;
  final int qty;
  final DateTime? waktu;
}

/// Satu pengajuan pembatalan beserta jejak tag-nya.
///
/// Admin memutuskan pembatalan berdasarkan hal yang tidak terlihat dari nomor
/// tag saja: lembarnya sudah keluar dari printer atau belum, dan sudah ada
/// yang menghitungnya atau belum. Membatalkan tag yang SUDAH dihitung berarti
/// angka hasil hitung itu ikut hilang dari perhitungan STO - keputusan yang
/// berbeda bobotnya dengan membatalkan tag yang bahkan belum tercetak.
class PengajuanBatal {
  const PengajuanBatal({
    required this.tag,
    required this.keadaanCetak,
    this.dicetakPada,
    this.hitungan = const [],
  });

  final StoTag tag;

  /// Keadaan cetak menurut server (draft / printed / error).
  final PrintState keadaanCetak;
  final DateTime? dicetakPada;

  /// Hasil hitung per tim; kosong berarti belum ada yang menghitung.
  final List<HasilHitung> hitungan;

  bool get sudahDicetak => keadaanCetak == PrintState.printed;
  bool get sudahDihitung => hitungan.isNotEmpty;

  /// Total qty dari seluruh tim yang sudah menghitung.
  int get totalQty => hitungan.fold(0, (jumlah, h) => jumlah + h.qty);

  /// Ringkas keadaan tag untuk ditampilkan di kartu pengajuan.
  String get ringkasan {
    if (!sudahDicetak) {
      return keadaanCetak == PrintState.error
          ? 'Gagal cetak - lembarnya tidak pernah keluar'
          : 'Belum tercetak - lembarnya tidak pernah keluar';
    }
    if (!sudahDihitung) return 'Sudah dicetak, belum dihitung siapa pun';
    return 'Sudah dihitung - $totalQty pcs';
  }

  /// true bila pembatalannya menghapus angka hasil hitung yang sudah ada.
  ///
  /// Dipakai layar untuk memperingatkan admin sebelum menyetujui.
  bool get berisiko => sudahDihitung;

  factory PengajuanBatal.fromServer(
    Map<String, dynamic> row,
    StoTag tag,
  ) {
    DateTime? waktu(Object? nilai) {
      final teks = '${nilai ?? ''}'.trim();
      return teks.isEmpty ? null : DateTime.tryParse(teks);
    }

    HasilHitung? hitung(String tim, String kolomNik, String kolomQty,
        String kolomWaktu) {
      final nik = '${row[kolomNik] ?? ''}'.trim();
      final saat = waktu(row[kolomWaktu]);
      // Penanda "sudah dihitung" adalah WAKTU-nya, bukan qty: hasil hitung 0
      // itu sah dan tetap harus terlihat admin.
      if (nik.isEmpty && saat == null) return null;
      return HasilHitung(
        tim: tim,
        nik: nik.isEmpty ? '-' : nik,
        qty: int.tryParse('${row[kolomQty] ?? 0}') ?? 0,
        waktu: saat,
      );
    }

    final a = hitung('A', 'nik_a', 'qty_a', 'updated_a');
    final b = hitung('B', 'nik_b', 'qty_b', 'updated_b');

    return PengajuanBatal(
      tag: tag,
      keadaanCetak: PrintState.fromName('${row['print_status'] ?? ''}'),
      dicetakPada: waktu(row['printed_at']),
      hitungan: [?a, ?b],
    );
  }
}
