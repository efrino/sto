/// Konfigurasi global aplikasi STO Preparation.
class AppConfig {
  AppConfig._();

  static const String appName = 'STO';
  static const String companyName = 'PT. MEKAR ARMADA JAYA';
  static const String plantName = 'PLANT TAMBUN';
  static const String departement = 'IT Department';

  /// Alamat server yang sah, sebagai pilihan tetap.
  ///
  /// Diketik bebas dulu, dan satu salah ketik membuat seluruh aplikasi diam
  /// tanpa penjelasan - sedangkan alamatnya cuma dua dan jarang berubah.
  ///
  /// Keduanya HARUS berakhir di '/api': jalur endpoint ditulis sebagai
  /// '/sto/part-list', jadi tanpa '/api' server menjawab 404 untuk semuanya.
  static const Map<String, String> serverPilihan = {
    'Internet (HTTPS)': 'https://mspin.newarmada.biz/sto/public/api',
    'Jaringan pabrik (HTTP)': 'http://192.168.10.67/majsf_rest_api/api',
  };

  /// Base URL bawaan: HTTPS, dan sengaja disebut sebagai pilihan pertama pada
  /// [serverPilihan] - bukan alamat tersendiri, supaya tidak mungkin ada
  /// bawaan yang tidak ada di daftar pilihan.
  ///
  /// HTTPS yang jadi bawaan karena handheld baru bisa saja dinyalakan di luar
  /// jaringan pabrik; alamat 192.168.10.67 hanya menjawab dari dalam, dan
  /// operator tidak punya cara menebak bahwa itulah sebab aplikasinya diam.
  static String get defaultBaseUrl => serverPilihan.values.first;

  /// Area yang dikenal STO, sama persis dengan isi kolom
  /// `majsf_sto.master_data.area` di server (IFRM 952 part, PRESS 1.168,
  /// IFPP 1.962, WELD 1.442, IFPD 984).
  ///
  /// Ditulis apa adanya - termasuk `WELD`, bukan "WELDING" - karena nilai
  /// inilah yang dipakai saat menyaring part milik operator; salah satu huruf
  /// saja membuat daftar partnya kosong tanpa pesan kesalahan.
  static const List<String> areaSto = [
    'IFRM',
    'PRESS',
    'IFPP',
    'WELD',
    'IFPD',
  ];

  /// Tim penghitung, mengikuti enum kolom `majsf_sto.users.tim` di server:
  /// hanya A dan B. Bukan daftar yang bisa ditambah admin - menambah tim
  /// ketiga berarti mengubah tipe kolomnya lebih dulu.
  static const List<String> timSto = ['A', 'B'];

  static const Duration httpTimeout = Duration(seconds: 15);

  /// Umur cache master part sebelum di-refresh dari server.
  static const Duration partCacheTtl = Duration(hours: 12);

  /// Batas jumlah tag per sekali cetak.
  ///
  /// Tiap tag adalah satu panggilan `print-tag` ke server (API belum
  /// punya versi massal), dan tiap nomor yang terlanjur dibuat tidak bisa
  /// dicetak ulang - jadi batch besar berarti risiko besar bila putus di
  /// tengah jalan.
  /// Batas hasil pencarian part yang diminta ke server sekali jalan.
  ///
  /// Master part berisi ribuan baris; menariknya sekaligus membuat handheld
  /// berat dan operator tetap tidak akan membaca semuanya. Yang dibutuhkan
  /// hanyalah beberapa baris teratas yang cocok dengan kata kuncinya.
  static const int partSearchLimit = 50;

  /// Batas baris master part yang disimpan ke cache perangkat per penyegaran.
  ///
  /// Dulu 10.000 (seluruh master) - satu balasan HTTP sebesar itu memakan
  /// waktu dan memori handheld. Sisanya tetap bisa ditemukan lewat pencarian
  /// ke server saat kata kuncinya tidak ada di cache.
  static const int partCacheLimit = 2000;

  static const int maxTagPerBatch = 5;
  static const int defaultTagPerBatch = 1;

  /// Panjang nomor urut pada tag (STO2609-000123).
  static const int sequencePadding = 6;

  /// Prefix nomor tag saat sequence diambil offline (belum dapat dari server).
  static const String offlineSequencePrefix = 'L';
}

/// Lebar kertas printer. Blueprint MPOS 332 memakai kertas 58mm.
/// Tinggi satu baris teks dalam titik (font A, 203 dpi).
///
/// Dipakai menerjemahkan setelan jarak (mm) menjadi jumlah baris kosong.
/// Perintah `ESC J n` - "maju n titik" - TERBUKTI DIABAIKAN printer handheld
/// ini: mengubah nilainya dari 90 ke 32 lalu ke 0 sama sekali tidak mengubah
/// panjang kertas yang keluar. Yang pasti dijalankan hanyalah baris kosong
/// biasa (LF), karena badan tag sendiri dicetak baris demi baris.
const int dotsPerLine = 24;

// Catatan hasil uji lapangan 4 Sep 2026: printer handheld ini hanya
// menjalankan perintah gerak berbasis BARIS (LF). Perintah berbasis titik
// `ESC J n` diabaikan diam-diam, dan `ESC e n` (mundur n baris) lebih buruk
// lagi - huruf "e"-nya ikut TERCETAK di kepala tag ("ePT. MEKAR ARMADA
// JAYA"). Karena itu jangan menambahkan perintah gerak selain LF di sini.

/// Jarak maju kertas TAMBAHAN setelah tag terakhir, dalam titik.
///
/// Nol karena printer ini sudah memajukan kertasnya sendiri saat aliran data
/// berhenti - firmware-nya maju ke posisi sobek tanpa diminta. Jarak itu
/// muncul dua kali: sebagai ekor cetakan ini, lalu sebagai kepala kosong
/// cetakan berikutnya. Menambah jarak sendiri di atasnya hanya memperpanjang
/// keduanya.
///
/// Printer yang TIDAK maju sendiri tetap bisa dilayani: operator menaikkan
/// angkanya lewat Setting > Printer.
const int feedAfterTagDots = 0;

/// Jarak antar tag dalam satu batch, dalam titik (8 titik = 1 mm).
///
/// Berbeda urusan dengan [feedAfterTagDots]: di tengah batch aliran datanya
/// tidak pernah berhenti, jadi firmware tidak menyisipkan apa pun dan jarak
/// ini SEPENUHNYA dari aplikasi. Tanpa jarak ini kotak isian tag sebelumnya
/// menempel ke kepala tag berikutnya - tidak ada tempat untuk menggunting.
///
/// 96 titik = 4 baris kosong (~12 mm).
///
/// Perjalanannya: 12 titik (tidak terlihat sama sekali) -> 2 baris (masih
/// mepet) -> 3 baris (sudah bisa digunting) -> 4 baris atas permintaan
/// lapangan, supaya guntingnya tidak perlu presisi.
const int gapAntarTagDots = 96;

enum PaperSize {
  mm58(charPerLine: 32, dots: 384, label: '58 mm (32 karakter)'),
  mm80(charPerLine: 48, dots: 576, label: '80 mm (48 karakter)');

  const PaperSize({
    required this.charPerLine,
    required this.dots,
    required this.label,
  });

  final int charPerLine;

  /// Lebar area cetak dalam titik (dot) - dipakai saat mencetak gambar,
  /// mis. kotak isian yang digambar sebagai bitmap.
  final int dots;

  final String label;

  static PaperSize fromName(String? name) => PaperSize.values.firstWhere(
        (e) => e.name == name,
        orElse: () => PaperSize.mm58,
      );
}
