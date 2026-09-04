import 'part_item.dart';

/// Status sebuah tag STO.
///
/// Aturan bisnis:
/// - tag hanya boleh dicetak SATU kali;
/// - setiap nomor yang dibuat pasti dicetak (draft hanya status sesaat
///   sebelum printer melapor sukses);
/// - pembatalan diajukan operator, disetujui admin.
///
/// draft -> printed -> pendingCancel -> cancelled
///                              \-> kembali printed bila ditolak admin
enum TagStatus {
  draft('BELUM TERCETAK'),
  printed('SUDAH CETAK'),
  pendingCancel('DIAJUKAN BATAL'),
  cancelled('DIBATALKAN');

  const TagStatus(this.label);
  final String label;

  static TagStatus fromName(String? name) => TagStatus.values.firstWhere(
        (e) => e.name == name,
        orElse: () => TagStatus.draft,
      );
}

/// Status sinkronisasi ke server (API menyusul -> semua antre di outbox).
enum SyncStatus {
  pending('BELUM SINKRON'),
  synced('TERSINKRON'),
  failed('GAGAL SINKRON');

  const SyncStatus(this.label);
  final String label;

  static SyncStatus fromName(String? name) => SyncStatus.values.firstWhere(
        (e) => e.name == name,
        orElse: () => SyncStatus.pending,
      );
}

class StoTag {
  const StoTag({
    this.id,
    required this.tagNo,
    required this.sequence,
    required this.batchId,
    required this.partNumber,
    required this.jobNumber,
    required this.partName,
    this.customer = '-',
    this.model = '-',
    this.unit = 'PCS',
    this.area = '-',
    this.location = '-',
    this.partType = 'FP',
    this.eventId,
    this.qty = 0,
    this.status = TagStatus.draft,
    this.syncStatus = SyncStatus.pending,
    required this.createdBy,
    required this.createdAt,
    this.printedAt,
    this.cancelledAt,
    this.cancelReason,
    this.cancelRequestedBy,
    this.cancelRequestedAt,
    this.cancelApprovedBy,
    this.note,
    this.offlineSequence = false,
  });

  final int? id;

  /// Nomor unik tag, dipakai sebagai isi QR (contoh: STO2609-000123).
  final String tagNo;
  final int sequence;
  final String batchId;

  final String partNumber;
  final String jobNumber;
  final String partName;
  final String customer;
  final String model;
  final String unit;
  final String area;
  final String location;

  /// FP (finish part) / WIP (work in process) - dicetak pada baris STATUS.
  final String partType;

  /// Event STO tempat tag ini dibuat (lihat [StoEvent]).
  final String? eventId;
  final int qty;

  final TagStatus status;
  final SyncStatus syncStatus;

  final String createdBy;
  final DateTime createdAt;
  final DateTime? printedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  /// Jejak alur pembatalan: operator mengajukan, admin menyetujui.
  final String? cancelRequestedBy;
  final DateTime? cancelRequestedAt;
  final String? cancelApprovedBy;
  final String? note;

  /// true bila nomor urut diambil dari counter lokal (offline),
  /// server perlu melakukan rekonsiliasi saat sinkronisasi.
  final bool offlineSequence;

  bool get isPrintable => status == TagStatus.draft;

  /// Operator hanya boleh mengajukan pembatalan untuk tag yang sudah tercetak.
  bool get canRequestCancel => status == TagStatus.printed;

  /// Admin boleh membatalkan tag tercetak maupun yang sedang diajukan.
  bool get canBeCancelledByAdmin =>
      status == TagStatus.printed || status == TagStatus.pendingCancel;

  bool get isPendingCancel => status == TagStatus.pendingCancel;

  StoTag copyWith({
    int? id,
    TagStatus? status,
    SyncStatus? syncStatus,
    DateTime? printedAt,
    DateTime? cancelledAt,
    String? cancelReason,
    String? cancelRequestedBy,
    DateTime? cancelRequestedAt,
    String? cancelApprovedBy,
    String? note,
    int? qty,
  }) {
    return StoTag(
      id: id ?? this.id,
      tagNo: tagNo,
      sequence: sequence,
      batchId: batchId,
      partNumber: partNumber,
      jobNumber: jobNumber,
      partName: partName,
      customer: customer,
      model: model,
      unit: unit,
      area: area,
      location: location,
      partType: partType,
      eventId: eventId,
      qty: qty ?? this.qty,
      status: status ?? this.status,
      syncStatus: syncStatus ?? this.syncStatus,
      createdBy: createdBy,
      createdAt: createdAt,
      printedAt: printedAt ?? this.printedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelReason: cancelReason ?? this.cancelReason,
      cancelRequestedBy: cancelRequestedBy ?? this.cancelRequestedBy,
      cancelRequestedAt: cancelRequestedAt ?? this.cancelRequestedAt,
      cancelApprovedBy: cancelApprovedBy ?? this.cancelApprovedBy,
      note: note ?? this.note,
      offlineSequence: offlineSequence,
    );
  }

  factory StoTag.fromPart({
    required PartItem part,
    required String tagNo,
    required int sequence,
    required String batchId,
    required String createdBy,
    required DateTime createdAt,
    String? areaOverride,
    String? note,
    String? eventId,
    int qty = 0,
    bool offlineSequence = false,
  }) {
    return StoTag(
      tagNo: tagNo,
      sequence: sequence,
      batchId: batchId,
      partNumber: part.partNumber,
      jobNumber: part.jobNumber,
      partName: part.partName,
      customer: part.customer,
      model: part.model,
      unit: part.unit,
      area: (areaOverride != null && areaOverride.isNotEmpty)
          ? areaOverride
          : part.area,
      location: part.location,
      partType: part.partType,
      eventId: eventId,
      qty: qty,
      createdBy: createdBy,
      createdAt: createdAt,
      note: note,
      offlineSequence: offlineSequence,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'tag_no': tagNo,
        'sequence': sequence,
        'batch_id': batchId,
        'part_number': partNumber,
        'job_number': jobNumber,
        'part_name': partName,
        'customer': customer,
        'model': model,
        'unit': unit,
        'area': area,
        'location': location,
        'part_type': partType,
        'event_id': eventId,
        'qty': qty,
        'status': status.name,
        'sync_status': syncStatus.name,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'printed_at': printedAt?.toIso8601String(),
        'cancelled_at': cancelledAt?.toIso8601String(),
        'cancel_reason': cancelReason,
        'cancel_requested_by': cancelRequestedBy,
        'cancel_requested_at': cancelRequestedAt?.toIso8601String(),
        'cancel_approved_by': cancelApprovedBy,
        'note': note,
        'offline_sequence': offlineSequence ? 1 : 0,
      };

  factory StoTag.fromMap(Map<String, dynamic> map) => StoTag(
        id: (map['id'] as num?)?.toInt(),
        tagNo: map['tag_no'] as String? ?? '',
        sequence: (map['sequence'] as num?)?.toInt() ?? 0,
        batchId: map['batch_id'] as String? ?? '',
        partNumber: map['part_number'] as String? ?? '',
        jobNumber: map['job_number'] as String? ?? '',
        partName: map['part_name'] as String? ?? '-',
        customer: map['customer'] as String? ?? '-',
        model: map['model'] as String? ?? '-',
        unit: map['unit'] as String? ?? 'PCS',
        area: map['area'] as String? ?? '-',
        location: map['location'] as String? ?? '-',
        partType: PartItem.normalizeType(map['part_type']),
        eventId: map['event_id'] as String?,
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        status: TagStatus.fromName(map['status'] as String?),
        syncStatus: SyncStatus.fromName(map['sync_status'] as String?),
        createdBy: map['created_by'] as String? ?? '-',
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
        printedAt: DateTime.tryParse('${map['printed_at']}'),
        cancelledAt: DateTime.tryParse('${map['cancelled_at']}'),
        cancelReason: map['cancel_reason'] as String?,
        cancelRequestedBy: map['cancel_requested_by'] as String?,
        cancelRequestedAt: DateTime.tryParse('${map['cancel_requested_at']}'),
        cancelApprovedBy: map['cancel_approved_by'] as String?,
        note: map['note'] as String?,
        // Bisa berasal dari sqflite (0/1) maupun payload outbox (true/false).
        offlineSequence: map['offline_sequence'] == true ||
            map['offline_sequence'] == 1 ||
            map['offline_sequence'] == '1',
      );

  /// Payload untuk dikirim ke API (kontrak sementara, lihat docs/API_CONTRACT.md).
  Map<String, dynamic> toApiJson() => {
        'tag_no': tagNo,
        'sequence': sequence,
        'batch_id': batchId,
        'part_number': partNumber,
        'job_number': jobNumber,
        'part_name': partName,
        'customer': customer,
        'model': model,
        'unit': unit,
        'area': area,
        'location': location,
        'part_type': partType,
        'event_id': eventId,
        'qty': qty,
        'status': status.name,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'printed_at': printedAt?.toIso8601String(),
        'cancelled_at': cancelledAt?.toIso8601String(),
        'cancel_reason': cancelReason,
        'cancel_requested_by': cancelRequestedBy,
        'cancel_requested_at': cancelRequestedAt?.toIso8601String(),
        'cancel_approved_by': cancelApprovedBy,
        'note': note,
        'offline_sequence': offlineSequence,
      };
}
