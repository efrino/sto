/// Satu pesan pada kotak pesan operator - admin.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.thread,
    required this.fromNik,
    required this.body,
    required this.createdAt,
    this.broadcast = false,
  });

  final int id;

  /// NIK operator pemilik percakapan, atau [ChatThread.broadcast].
  final String thread;

  final String fromNik;
  final String body;
  final DateTime createdAt;

  /// Pengumuman dari admin - dibaca semua orang, dibalas tidak.
  final bool broadcast;

  factory ChatMessage.fromServer(Map<String, dynamic> json) => ChatMessage(
        id: int.tryParse('${json['id'] ?? 0}') ?? 0,
        thread: '${json['thread'] ?? ''}',
        fromNik: '${json['from_nik'] ?? ''}',
        body: '${json['body'] ?? ''}',
        broadcast: '${json['broadcast'] ?? 0}' == '1',
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

  /// Judul yang dilihat pembacanya - percakapan sendiri tidak perlu diberi
  /// nama NIK-nya sendiri.
  String judulUntuk(String nik) {
    if (broadcast) return 'Pengumuman';
    return thread == nik ? 'Admin' : thread;
  }

  factory ChatThread.fromServer(Map<String, dynamic> json) => ChatThread(
        thread: '${json['thread'] ?? ''}',
        broadcast: '${json['broadcast'] ?? 0}' == '1',
        lastId: int.tryParse('${json['last_id'] ?? 0}') ?? 0,
        lastBody: '${json['last_body'] ?? ''}',
        lastFrom: '${json['last_from'] ?? ''}',
        lastAt: DateTime.tryParse('${json['last_at'] ?? ''}'),
        belumDibaca: int.tryParse('${json['belum_dibaca'] ?? 0}') ?? 0,
      );
}
