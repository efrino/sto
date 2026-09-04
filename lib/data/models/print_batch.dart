import 'sto_tag.dart';

/// Satu sesi persiapan: 1 part/job + N tag unik (increment id, bukan copy).
class PrintBatch {
  const PrintBatch({
    required this.batchId,
    required this.partNumber,
    required this.jobNumber,
    required this.partName,
    required this.area,
    required this.qty,
    required this.createdBy,
    required this.createdAt,
    this.note,
    this.printedCount = 0,
    this.cancelledCount = 0,
  });

  final String batchId;
  final String partNumber;
  final String jobNumber;
  final String partName;
  final String area;

  /// Jumlah tag yang dibuat (tiap tag punya nomor sendiri).
  final int qty;
  final String createdBy;
  final DateTime createdAt;
  final String? note;
  final int printedCount;
  final int cancelledCount;

  int get draftCount => qty - printedCount - cancelledCount;
  bool get isDone => draftCount <= 0;

  Map<String, dynamic> toMap() => {
        'batch_id': batchId,
        'part_number': partNumber,
        'job_number': jobNumber,
        'part_name': partName,
        'area': area,
        'qty': qty,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'note': note,
      };

  factory PrintBatch.fromMap(Map<String, dynamic> map) => PrintBatch(
        batchId: map['batch_id'] as String? ?? '',
        partNumber: map['part_number'] as String? ?? '',
        jobNumber: map['job_number'] as String? ?? '',
        partName: map['part_name'] as String? ?? '-',
        area: map['area'] as String? ?? '-',
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        createdBy: map['created_by'] as String? ?? '-',
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
        note: map['note'] as String?,
        printedCount: (map['printed_count'] as num?)?.toInt() ?? 0,
        cancelledCount: (map['cancelled_count'] as num?)?.toInt() ?? 0,
      );

  factory PrintBatch.fromTags(List<StoTag> tags) {
    final first = tags.first;
    return PrintBatch(
      batchId: first.batchId,
      partNumber: first.partNumber,
      jobNumber: first.jobNumber,
      partName: first.partName,
      area: first.area,
      qty: tags.length,
      createdBy: first.createdBy,
      createdAt: first.createdAt,
      note: first.note,
      printedCount: tags.where((t) => t.status == TagStatus.printed).length,
      cancelledCount: tags.where((t) => t.status == TagStatus.cancelled).length,
    );
  }
}
