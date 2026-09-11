/// Menerjemahkan galat teknis menjadi kalimat yang bisa ditindaklanjuti.
///
/// Sebagian besar jalur sudah melempar pesan berbahasa manusia (ApiClient
/// menerjemahkan kegagalan jaringan, repository melempar aturan dalam kalimat).
/// Yang lolos adalah galat dari lapisan yang tidak kita tulis sendiri -
/// database perangkat, plugin Bluetooth/kamera, dan kesalahan pemrograman -
/// yang bunyinya "PlatformException(read failed, socket might closed...)".
///
/// Kalimat semacam itu tidak menolong siapa pun di lapangan. Operator tidak
/// tahu apa yang harus dilakukan, dan admin yang menerimanya lewat telepon
/// pun tidak. Di sini semuanya disapu jadi kalimat pendek yang menyebut apa
/// yang bisa dicoba, dan sisanya dicatat untuk pengembang.
class PesanGalat {
  PesanGalat._();

  /// Kalimat siap tampil untuk [galat] apa pun.
  static String manusiawi(Object? galat) {
    if (galat == null) return 'Terjadi kesalahan yang tidak dikenali.';
    final mentah = galat.toString().trim();
    if (mentah.isEmpty) return 'Terjadi kesalahan yang tidak dikenali.';

    final kecil = mentah.toLowerCase();

    // Pola teknis yang paling sering muncul, diurutkan dari yang paling khas.
    if (kecil.contains('platformexception') ||
        kecil.contains('bluetooth') && kecil.contains('socket') ||
        kecil.contains('read failed') ||
        kecil.contains('broken pipe')) {
      return 'Sambungan ke printer terputus. Pastikan Bluetooth dan '
          'printernya menyala, lalu coba lagi.';
    }
    if (kecil.contains('missingpluginexception')) {
      return 'Fitur ini belum tersedia pada versi aplikasi yang terpasang. '
          'Perbarui aplikasinya.';
    }
    if (kecil.contains('databaseexception') ||
        kecil.contains('sqlite') ||
        kecil.contains('unique constraint')) {
      return 'Penyimpanan di perangkat bermasalah. Tutup aplikasi lalu buka '
          'lagi; bila berulang, hubungi admin.';
    }
    if (kecil.contains('cameraexception') ||
        kecil.contains('camera') && kecil.contains('permission')) {
      return 'Kamera tidak bisa dipakai. Periksa izin kamera untuk aplikasi '
          'ini di setelan perangkat.';
    }
    if (kecil.contains('permission')) {
      return 'Izin yang dibutuhkan belum diberikan. Buka setelan perangkat '
          'dan izinkan aplikasi ini.';
    }
    if (kecil.contains('socketexception') ||
        kecil.contains('connection refused') ||
        kecil.contains('failed host lookup') ||
        kecil.contains('network is unreachable') ||
        kecil.contains('connection reset')) {
      return 'Server tidak terjangkau. Periksa sambungan jaringan, lalu '
          'coba lagi.';
    }
    if (kecil.contains('timeoutexception') || kecil.contains('timed out')) {
      return 'Server lama menjawab. Coba lagi sebentar.';
    }
    if (kecil.contains('handshakeexception') ||
        kecil.contains('certificate')) {
      return 'Sambungan aman ke server gagal diperiksa. Pastikan jam '
          'perangkat benar, atau pakai alamat jaringan pabrik.';
    }
    if (kecil.contains('formatexception') ||
        kecil.contains('unexpected character') ||
        kecil.contains('is not a subtype') ||
        kecil.contains('type \'')) {
      return 'Jawaban server tidak bisa dibaca aplikasi. Coba lagi; bila '
          'berulang, laporkan ke admin.';
    }
    if (kecil.contains('null check operator') ||
        kecil.contains('noSuchMethod'.toLowerCase()) ||
        kecil.contains('rangeerror') ||
        kecil.contains('bad state')) {
      return 'Aplikasi menemui keadaan yang tidak terduga. Ulangi langkahnya; '
          'bila berulang, laporkan ke admin.';
    }

    // Bukan pola teknis: kemungkinan besar sudah kalimat manusia dari lapisan
    // kita sendiri. Cukup buang awalan "Exception:" yang ditambahkan Dart.
    return _tanpaAwalan(mentah);
  }

  static String _tanpaAwalan(String teks) {
    var hasil = teks;
    for (final awalan in const [
      'Exception: ',
      'Bad state: ',
      'Invalid argument(s): ',
      'StateError: ',
      'ArgumentError: ',
    ]) {
      if (hasil.startsWith(awalan)) hasil = hasil.substring(awalan.length);
    }
    return hasil;
  }
}
