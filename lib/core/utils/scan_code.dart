/// Membaca isi QR / hasil ketikan scanner menjadi nomor tag.
///
/// QR pada tag berisi nomornya apa adanya (STO260902-000123), tetapi hasil
/// scan bisa terbawa spasi, huruf kecil, atau awalan lain bila nanti formatnya
/// berubah - jadi nomor tag diambil lewat pola.
class ScanCode {
  ScanCode._();

  /// Contoh yang cocok: STO260902-000123, LSTO260902-000004, DEMO260902-000001.
  static final RegExp _tagPattern = RegExp(r'[A-Z0-9]+-\d{4,}');

  /// Kode Tag OK dari produksi, mis. MAJ2708260202754.
  ///
  /// Tanpa tanda hubung, jadi tidak cocok dengan pola tag STO - diambil apa
  /// adanya setelah dirapikan. Panjang minimum menjaga hasil pindai yang
  /// terpotong tidak ikut dikirim ke server.
  static String? extractTagOk(String? raw) {
    final value = raw?.trim().toUpperCase() ?? '';
    if (value.length < 6) return null;

    final match = RegExp(r'[A-Z0-9-]{6,}').firstMatch(value);
    return match?.group(0);
  }

  static String? extractTagNo(String? raw) {
    final value = raw?.trim().toUpperCase() ?? '';
    if (value.isEmpty) return null;

    final match = _tagPattern.firstMatch(value);
    if (match != null) return match.group(0);

    // Ketikan manual yang belum lengkap tetap diteruskan supaya pesan
    // "tidak ditemukan" muncul dengan teks yang diketik operator.
    return value.length >= 4 ? value : null;
  }
}
