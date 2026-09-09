/// Keadaan pengiriman satu pesan yang ditulis sendiri.
///
/// Dipakai menggambar centang di gelembung pesan. Tanpa penanda ini pengirim
/// tidak punya cara membedakan pesan yang belum sampai dari yang sudah
/// dibaca - dan yang ia lakukan adalah mengirim ulang, lalu ditolak
/// penjagaan spam server.
enum KirimPesan {
  /// Masih dalam perjalanan ke server (belum punya id).
  mengirim,

  /// Tersimpan di server, belum dibuka lawan bicara.
  terkirim,

  /// Lawan bicara sudah membuka utasnya sampai pesan ini.
  dibaca,

  /// Ditolak server atau jaringan putus - isinya dikembalikan ke kotak tulis.
  gagal,
}

/// Isi satu percakapan beserta batas bacanya.
///
/// Batas baca dikirim di tingkat utas, bukan per pesan, karena memang begitu
/// bentuknya di server: satu baris `chat_reads` per orang per utas.
class IsiUtas {
  const IsiUtas({this.pesan = const [], this.dibacaSampai = 0});

  final List<ChatMessage> pesan;

  /// Id pesan terakhir yang sudah dibaca LAWAN BICARA; 0 bila belum ada.
  final int dibacaSampai;
}

/// Satu pesan pada kotak pesan operator - admin.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.thread,
    required this.fromNik,
    required this.body,
    required this.createdAt,
    this.broadcast = false,
    this.dariAdmin = false,
    this.kirim = KirimPesan.terkirim,
  });

  final int id;

  /// NIK operator pemilik percakapan, atau [ChatThread.broadcast].
  final String thread;

  final String fromNik;
  final String body;
  final DateTime createdAt;

  /// Pengumuman dari admin - dibaca semua orang, dibalas tidak.
  final bool broadcast;

  /// true bila pengirimnya admin. Datang dari server, bukan ditebak dari pola
  /// NIK: peran bisa berubah, dan operator perlu tahu apakah yang menjawab
  /// memang orang yang berwenang - bukan sekadar NIK asing.
  final bool dariAdmin;

  /// Keadaan pengiriman - hanya berarti untuk pesan yang ditulis sendiri.
  /// Pesan yang datang dari server selalu sudah terkirim.
  final KirimPesan kirim;

  /// Nama pengirim sebagaimana boleh ditampilkan di layar.
  ///
  /// NIK admin sengaja TIDAK pernah ditulis. Login STO tidak memakai kata
  /// sandi - NIK saja sudah cukup untuk masuk - jadi NIK admin yang terbaca
  /// operator sama artinya dengan kunci yang tergeletak: ia bisa masuk
  /// sebagai admin lalu memberi izin apa pun kepada dirinya sendiri.
  ///
  /// Bagi operator, yang penting memang bukan admin yang mana: jawabannya
  /// datang dari orang yang berwenang, dan itu saja yang perlu ia tahu.
  String get namaTampil => dariAdmin ? 'ADMIN' : fromNik;

  /// Pesan yang belum punya id server - ditampilkan lebih dulu supaya
  /// mengetik terasa seketika, lalu diganti balasan server.
  bool get menunggu => kirim == KirimPesan.mengirim;

  /// Centang apa yang pantas digambar untuk pesan ini, dilihat dari mata
  /// [nik] dengan batas baca lawan bicara [dibacaSampai].
  ///
  /// Aturannya ditaruh di model, bukan di layar: yang menentukan bukan
  /// tampilannya melainkan arti - dan artinya sama di mana pun pesan itu
  /// ditampilkan.
  KirimPesan keadaanKirim({required String nik, required int dibacaSampai}) {
    // Centang adalah kabar untuk pengirim. Pesan orang lain tidak punya.
    if (fromNik != nik) return KirimPesan.terkirim;

    if (kirim == KirimPesan.mengirim || kirim == KirimPesan.gagal) {
      return kirim;
    }

    // Pengumuman dibaca banyak orang, dan batas baca yang ada hanya milik
    // pembaca yang paling jauh. Menggambarnya sebagai "sudah dibaca" akan
    // terbaca sebagai "sudah dibaca semua orang" - itu tidak benar.
    if (broadcast) return KirimPesan.terkirim;

    return dibacaSampai >= id ? KirimPesan.dibaca : KirimPesan.terkirim;
  }

  ChatMessage salin({KirimPesan? kirim}) => ChatMessage(
        id: id,
        thread: thread,
        fromNik: fromNik,
        body: body,
        createdAt: createdAt,
        broadcast: broadcast,
        dariAdmin: dariAdmin,
        kirim: kirim ?? this.kirim,
      );

  factory ChatMessage.fromServer(Map<String, dynamic> json) => ChatMessage(
        id: int.tryParse('${json['id'] ?? 0}') ?? 0,
        thread: '${json['thread'] ?? ''}',
        fromNik: '${json['from_nik'] ?? ''}',
        body: '${json['body'] ?? ''}',
        broadcast: '${json['broadcast'] ?? 0}' == '1',
        dariAdmin: '${json['from_admin'] ?? 0}' == '1',
        createdAt:
            DateTime.tryParse('${json['created_at'] ?? ''}') ?? DateTime.now(),
      );
}

/// Satu baris pada daftar percakapan.
class ChatThread {
  const ChatThread({
    required this.thread,
    this.broadcast = false,
    this.lastId = 0,
    this.lastBody = '',
    this.lastFrom = '',
    this.lastAt,
    this.belumDibaca = 0,
    this.lastDariAdmin = false,
    this.pemilikAdmin = false,
  });

  /// Utas pengumuman - namanya sengaja bukan NIK siapa pun, jadi tidak
  /// mungkin bentrok dengan percakapan operator.
  static const String broadcastKey = 'BROADCAST';

  final String thread;
  final bool broadcast;

  final int lastId;
  final String lastBody;
  final String lastFrom;
  final DateTime? lastAt;
  final int belumDibaca;

  /// Pesan terakhir dikirim admin.
  final bool lastDariAdmin;

  /// Pemilik utas ini sendiri seorang admin - dipakai saat admin melihat
  /// daftar utas, supaya tahu lawan bicaranya rekan admin, bukan operator.
  final bool pemilikAdmin;

  /// Judul yang dilihat pembacanya - percakapan sendiri tidak perlu diberi
  /// nama NIK-nya sendiri.
  String judulUntuk(String nik) {
    if (broadcast) return 'Pengumuman';
    return thread == nik ? 'Admin' : thread;
  }

  /// Label peran pemilik utas; kosong berarti tidak perlu ditandai.
  String get labelPeran {
    if (broadcast) return '';
    return pemilikAdmin ? 'Admin' : 'Operator';
  }

  factory ChatThread.fromServer(Map<String, dynamic> json) => ChatThread(
        thread: '${json['thread'] ?? ''}',
        broadcast: '${json['broadcast'] ?? 0}' == '1',
        lastId: int.tryParse('${json['last_id'] ?? 0}') ?? 0,
        lastBody: '${json['last_body'] ?? ''}',
        lastFrom: '${json['last_from'] ?? ''}',
        lastAt: DateTime.tryParse('${json['last_at'] ?? ''}'),
        belumDibaca: int.tryParse('${json['belum_dibaca'] ?? 0}') ?? 0,
        lastDariAdmin: '${json['last_admin'] ?? 0}' == '1',
        pemilikAdmin: '${json['thread_admin'] ?? 0}' == '1',
      );
}
