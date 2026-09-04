import 'part_item.dart';
import 'sto_tag.dart';

/// Keadaan cetak satu tag menurut server (`print-history`).
enum PrintState {
  draft('BELUM TERCETAK'),
  printed('SUDAH CETAK'),
  error('GAGAL CETAK');

  const PrintState(this.label);
  final String label;

  static PrintState fromName(String? name) => PrintState.values.firstWhere(
        (e) => e.name == (name ?? '').trim().toLowerCase(),
        orElse: () => PrintState.draft,
      );
}

/// Satu baris riwayat cetak - datanya milik server, perangkat hanya menampilkan.
///
/// Barisnya sengaja membawa identitas material selengkap label tag, supaya
/// draft yang tertinggal bisa dicetak ulang tanpa perlu mencarinya lagi di
/// master part.
class PrintEntry {
  const PrintEntry({
    required this.tagNo,
    required this.area,
    required this.state,
    this.errorMessage = '',
    this.printedAt,
    this.canceled = false,
    this.cancelReason = '',
    this.cancelRequestedAt,
    this.cancelRequestedBy = '',
    this.cancelApprovedBy = '',
    required this.createdBy,
    required this.createdAt,
    this.eventId = '',
    this.eventName = '',
    this.itemId,
    this.partNumber = '',
    this.jobNumber = '',
    this.partName = '',
    this.partType = '',
    this.statusPart = '',
    this.customer = '',
    this.model = '',
    this.plant = '',
  });

  final String tagNo;
  final String area;
  final PrintState state;

  /// Alasan gagal apa adanya dari server, mis. "Kertas printer habis".
  final String errorMessage;
  final DateTime? printedAt;

  final bool canceled;
  final String cancelReason;

  /// Terisi bila ada pengajuan pembatalan yang BELUM diputus admin. Tag-nya
  /// masih sah - yang membatalkan hanya persetujuan admin ([canceled]).
  final DateTime? cancelRequestedAt;
  final String cancelRequestedBy;
  final String cancelApprovedBy;

  /// Pengajuan yang masih menggantung: sudah diajukan, belum dibatalkan.
  bool get cancelDiajukan => !canceled && cancelRequestedAt != null;

  final String createdBy;
  final DateTime createdAt;

  final String eventId;
  final String eventName;

  final int? itemId;
  final String partNumber;
  final String jobNumber;
  final String partName;
  final String partType;
  final String statusPart;
  final String customer;
  final String model;
  final String plant;

  /// Tag yang masih perlu keluar dari printer.
  ///
  /// Tag yang sudah dibatalkan tidak ikut - lembarannya memang tidak boleh
  /// dicetak lagi. Yang sedang diajukan batal juga ditahan: mencetaknya
  /// sekarang berarti kertas terbuang bila admin ternyata menyetujui.
  bool get perluCetak =>
      !canceled && !cancelDiajukan && state != PrintState.printed;

  factory PrintEntry.fromServer(Map<String, dynamic> json) {
    DateTime? waktu(Object? nilai) {
      final teks = '${nilai ?? ''}'.trim();
      if (teks.isEmpty) return null;
      return DateTime.tryParse(teks);
    }

    return PrintEntry(
      tagNo: '${json['id_tag'] ?? ''}',
      area: '${json['area'] ?? ''}',
      state: PrintState.fromName('${json['print_status'] ?? ''}'),
      errorMessage: '${json['print_error'] ?? ''}'.trim(),
      printedAt: waktu(json['printed_at']),
      canceled: '${json['is_canceled'] ?? 0}' == '1',
      cancelReason: '${json['cancel_reason'] ?? ''}'.trim(),
      cancelRequestedAt: waktu(json['cancel_requested_at']),
      cancelRequestedBy: '${json['cancel_requested_by'] ?? ''}'.trim(),
      cancelApprovedBy: '${json['cancel_approved_by'] ?? ''}'.trim(),
      createdBy: '${json['created_by'] ?? ''}',
      createdAt: waktu(json['created_at']) ?? DateTime.now(),
      eventId: '${json['id_event'] ?? ''}',
      eventName: '${json['event_name'] ?? ''}',
      itemId: int.tryParse('${json['id_item'] ?? ''}'),
      partNumber: '${json['part_number'] ?? ''}',
      jobNumber: '${json['job_number'] ?? ''}',
      partName: '${json['material_description'] ?? ''}',
      partType: '${json['type'] ?? ''}',
      statusPart: '${json['status_part'] ?? ''}',
      customer: '${json['customer'] ?? ''}',
      model: '${json['model'] ?? ''}',
      plant: '${json['plant'] ?? ''}',
    );
  }

  /// Bentuk tag untuk dicetak ulang.
  ///
  /// Nomor tag dipertahankan apa adanya - lembaran ulangan harus membawa
  /// nomor yang sama dengan barisnya di server, bukan nomor baru.
  StoTag toTag() => StoTag.fromPart(
        part: PartItem(
          partNumber: partNumber,
          jobNumber: jobNumber,
          partName: partName,
          customer: customer,
          model: model,
          area: area,
          location: '',
          partType: partType,
        ),
        tagNo: tagNo,
        sequence: 0,
        batchId: 'SERVER',
        createdBy: createdBy,
        createdAt: createdAt,
        eventId: eventId,
      );
}

/// Hasil `print-history`: barisnya dan ringkasan angka dari server.
class PrintHistory {
  const PrintHistory({this.entries = const [], this.summary = const {}});

  final List<PrintEntry> entries;

  /// total / draft / printed / error / dibatalkan - dihitung server supaya
  /// angkanya sama di semua perangkat.
  final Map<String, int> summary;

  int get total => summary['total'] ?? 0;
  int get draft => summary['draft'] ?? 0;
  int get printed => summary['printed'] ?? 0;
  int get error => summary['error'] ?? 0;
  int get diajukanBatal => summary['diajukan_batal'] ?? 0;
  int get canceled => summary['dibatalkan'] ?? 0;

  /// Tag yang menunggu dicetak ulang: draft maupun yang gagal.
  int get menunggu => draft + error;
}
