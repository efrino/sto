import 'sto_tag.dart';

/// Hasil hitung satu tag STO oleh satu tim.
///
/// Aturan yang dijaga (lihat [CountDao] & [CountRepository]):
/// - satu tag boleh dihitung beberapa tim (tim A dan tim B masing-masing satu
///   catatan) - karena itu kuncinya `tag_no + team`;
/// - dalam satu tim hanya boleh ada satu pencatat: koreksi hanya boleh oleh
///   NIK yang sama dengan yang mencatat pertama kali.
class StoCount {
  const StoCount({
    this.id,
    required this.tagNo,
    required this.nik,
    required this.team,
    required this.qty,
    this.partNumber = '-',
    this.jobNumber = '-',
    this.partName = '-',
    this.area = '-',
    this.unit = 'PCS',
    required this.countedAt,
    this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  });

  final int? id;
  final String tagNo;

  /// NIK pencatat - hanya dia yang boleh mengoreksi angkanya.
  final String nik;

  /// Tim tempat NIK tersebut berada (diatur admin pada data user).
  final String team;

  final int qty;
  final String partNumber;
  final String jobNumber;
  final String partName;
  final String area;
  final String unit;

  final DateTime countedAt;
  final DateTime? updatedAt;
  final SyncStatus syncStatus;

  bool get pernahDikoreksi => updatedAt != null;


  /// Satu baris `scan-history` dari server.
  ///
  /// Riwayat scan milik server: hasil hitung tim A dan tim B bisa datang dari
  /// handheld berbeda, jadi catatan satu perangkat tidak pernah utuh.
  factory StoCount.fromServer(Map<String, dynamic> json) {
    DateTime waktu(Object? nilai) =>
        DateTime.tryParse('${nilai ?? ''}') ?? DateTime.now();

    return StoCount(
      id: int.tryParse('${json['id'] ?? ''}'),
      tagNo: '${json['id_tag'] ?? ''}',
      nik: '${json['nik'] ?? '-'}',
      team: '${json['tim'] ?? '-'}',
      qty: int.tryParse('${json['qty'] ?? 0}') ?? 0,
      partNumber: '${json['part_number'] ?? '-'}',
      jobNumber: '${json['job_number'] ?? '-'}',
      partName: '${json['material_description'] ?? '-'}',
      area: '${json['area'] ?? '-'}',
      countedAt: waktu(json['scanned_at']),
      // Datang dari server, jadi memang sudah tersinkron.
      syncStatus: SyncStatus.synced,
    );
  }

  StoCount copyWith({
    int? id,
    int? qty,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    return StoCount(
      id: id ?? this.id,
      tagNo: tagNo,
      nik: nik,
      team: team,
      qty: qty ?? this.qty,
      partNumber: partNumber,
      jobNumber: jobNumber,
      partName: partName,
      area: area,
      unit: unit,
      countedAt: countedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'tag_no': tagNo,
        'nik': nik,
        'team': team,
        'qty': qty,
        'part_number': partNumber,
        'job_number': jobNumber,
        'part_name': partName,
        'area': area,
        'unit': unit,
        'counted_at': countedAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'sync_status': syncStatus.name,
      };

  factory StoCount.fromMap(Map<String, dynamic> map) => StoCount(
        id: (map['id'] as num?)?.toInt(),
        tagNo: map['tag_no'] as String? ?? '',
        nik: map['nik'] as String? ?? '-',
        team: map['team'] as String? ?? '-',
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        partNumber: map['part_number'] as String? ?? '-',
        jobNumber: map['job_number'] as String? ?? '-',
        partName: map['part_name'] as String? ?? '-',
        area: map['area'] as String? ?? '-',
        unit: map['unit'] as String? ?? 'PCS',
        countedAt: DateTime.tryParse('${map['counted_at']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${map['updated_at']}'),
        syncStatus: SyncStatus.fromName(map['sync_status'] as String?),
      );

  /// Payload POST hasil hitung (lihat docs/API_CONTRACT.md).
  Map<String, dynamic> toApiJson() => {
        'nik': nik,
        'tag_no': tagNo,
        'tim': team,
        'qty': qty,
        'counted_at': countedAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}
