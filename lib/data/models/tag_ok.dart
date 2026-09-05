/// Tag OK - tag hasil produksi yang sudah dinyatakan OK, dipakai sebagai
/// satuan hitung saat STO.
///
/// Alurnya dua langkah dan sengaja dipisah:
/// 1. **Siapkan** - petugas memindai tag di lapangan lalu menyetujuinya;
///    [terbuka] menjadi true. Artinya "tag ini ada dan siap dihitung".
/// 2. **Hitung** - penghitung memindai tag yang sama lalu mengisi qty
///    fisiknya; tag tertutup kembali beserta [qtyScan] dan [scannedBy].
///
/// Pemisahan itu yang membuat selisih bisa ditelusuri: tag yang disiapkan
/// tetapi tidak pernah dihitung tetap terlihat, dan tag tidak mungkin dihitung
/// tanpa pernah disiapkan.
class TagOk {
  const TagOk({
    required this.idTagOk,
    required this.area,
    this.partNumber = '',
    this.jobNumber = '',
    this.process = '',
    this.line = '',
    this.shift,
    this.customer = '',
    this.project = '',
    this.status = '',
    this.qtyKbn = '',
    this.eventId,
    this.terbuka = false,
    this.openedBy = '',
    this.openedAt,
    this.qtyScan,
    this.scannedBy = '',
    this.scannedAt,
    this.scanBy = '',
    this.scanAt,
    this.batal = 0,
    this.cancelReason = '',
    this.canceledBy = '',
    this.canceledAt,
  });

  final String idTagOk;
  final String area;
  final String partNumber;
  final String jobNumber;
  final String process;
  final String line;
  final int? shift;
  final String customer;
  final String project;
  final String status;

  /// Qty kanban yang tercetak pada tag - acuan saat menghitung fisik.
  final String qtyKbn;

  final int? eventId;

  /// true bila tag sudah disiapkan dan menunggu dihitung.
  final bool terbuka;
  final String openedBy;
  final DateTime? openedAt;

  /// Hasil hitung fisik; null berarti belum pernah dihitung.
  final int? qtyScan;
  final String scannedBy;
  final DateTime? scannedAt;

  /// Jejak dari sistem produksi: kapan dan oleh siapa tag ini diterbitkan.
  /// Berbeda dari [scannedBy]/[scannedAt], yang mencatat hasil hitung STO.
  final String scanBy;
  final DateTime? scanAt;

  /// Keadaan pembatalan mengikuti kesepakatan tabel: 0 normal,
  /// 1 dibatalkan, 2 menunggu keputusan admin.
  final int batal;
  final String cancelReason;
  final String canceledBy;
  final DateTime? canceledAt;

  bool get dibatalkan => batal == 1;
  bool get menungguKeputusan => batal == 2;

  bool get sudahDihitung => scannedAt != null;

  /// Tag batal - dan yang sedang diajukan batal - tidak boleh disiapkan
  /// maupun dihitung; server menolaknya, dan tombolnya ikut dimatikan supaya
  /// penolakan itu tidak datang sebagai kejutan.
  bool get bisaDiproses => batal == 0;

  /// Qty kanban sebagai angka, atau null bila tidak terbaca.
  int? get kanban => int.tryParse(qtyKbn.trim());

  /// Selisih hasil hitung terhadap qty kanban - null bila salah satunya
  /// tidak diketahui. Nilai negatif berarti fisik kurang dari kanban.
  int? get selisih {
    final k = kanban;
    final q = qtyScan;
    if (k == null || q == null) return null;
    return q - k;
  }

  String get keadaan {
    if (dibatalkan) return 'DIBATALKAN';
    if (menungguKeputusan) return 'MENUNGGU KEPUTUSAN';
    if (sudahDihitung) return 'SUDAH DIHITUNG';
    if (terbuka) return 'SIAP DIHITUNG';
    return 'BELUM DISIAPKAN';
  }

  factory TagOk.fromServer(Map<String, dynamic> json) {
    DateTime? waktu(Object? nilai) {
      final teks = '${nilai ?? ''}'.trim();
      return teks.isEmpty ? null : DateTime.tryParse(teks);
    }

    return TagOk(
      idTagOk: '${json['id_tag_ok'] ?? ''}',
      area: '${json['area'] ?? ''}',
      partNumber: '${json['part_number'] ?? ''}',
      jobNumber: '${json['job_number'] ?? ''}',
      process: '${json['process'] ?? ''}',
      line: '${json['line'] ?? ''}',
      shift: int.tryParse('${json['shift'] ?? ''}'),
      customer: '${json['customer'] ?? ''}',
      project: '${json['project'] ?? ''}',
      status: '${json['status'] ?? ''}',
      qtyKbn: '${json['qty_kbn'] ?? ''}',
      eventId: int.tryParse('${json['id_event'] ?? ''}'),
      terbuka: '${json['scan_open'] ?? 0}' == '1',
      openedBy: '${json['opened_by'] ?? ''}',
      openedAt: waktu(json['opened_at']),
      qtyScan: int.tryParse('${json['qty_scan'] ?? ''}'),
      scannedBy: '${json['scanned_by'] ?? ''}',
      scannedAt: waktu(json['scanned_at']),
      scanBy: '${json['scan_by'] ?? ''}',
      scanAt: waktu(json['scan_at']),
      batal: int.tryParse('${json['is_canceled'] ?? 0}') ?? 0,
      cancelReason: '${json['cancel_reason'] ?? ''}',
      canceledBy: '${json['canceled_by'] ?? ''}',
      canceledAt: waktu(json['canceled_at']),
    );
  }
}
