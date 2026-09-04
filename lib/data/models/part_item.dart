/// Master part / job yang bisa dicari pada halaman pencarian.
class PartItem {
  const PartItem({
    required this.partNumber,
    required this.jobNumber,
    required this.partName,
    this.customer = '-',
    this.model = '-',
    this.unit = 'PCS',
    this.area = '-',
    this.location = '-',
    this.partType = 'FP',
    this.stdPack = 0,
    this.updatedAt,
  });

  final String partNumber;
  final String jobNumber;
  final String partName;
  final String customer;
  final String model;
  final String unit;
  final String area;
  final String location;

  /// Status part: FP (finish part) atau WIP (work in process).
  /// Dicetak pada tag menggantikan baris lokasi.
  final String partType;

  /// Standard packing (qty per kanban/box) - dipakai sebagai saran jumlah tag.
  final int stdPack;
  final DateTime? updatedAt;

  String get displayTitle => partNumber.isEmpty
      ? jobNumber
      : '$partNumber  •  $jobNumber';

  /// Baris `part-list` dari API STO. `part_number` bisa kosong di master -
  /// job number-lah yang selalu ada, jadi jangan dijadikan syarat.
  factory PartItem.fromServer(Map<String, dynamic> json) => PartItem(
        partNumber: '${json['part_number'] ?? ''}'.trim(),
        jobNumber: '${json['job_number'] ?? ''}'.trim(),
        partName: '${json['material_description'] ?? '-'}'.trim(),
        customer: '${json['customer'] ?? '-'}',
        model: '${json['model'] ?? '-'}',
        area: '${json['area'] ?? '-'}'.trim().toUpperCase(),
        // `type` di master berisi FP/WIP; `status_part` isinya lain
        // (REGULER dsb) dan tidak dipakai pada tag.
        partType: '${json['type'] ?? 'FP'}'.trim().toUpperCase(),
        location: '${json['process'] ?? '-'}',
      );

  /// Dipakai untuk pencarian lokal (offline) di sqflite / memori.
  String get searchIndex => [
        partNumber,
        jobNumber,
        partName,
        customer,
        model,
        area,
        location,
        partType,
      ].join(' ').toLowerCase();

  /// Server boleh mengirim "FP"/"WIP", "finish part", "work in process", dst.
  static String normalizeType(Object? raw) {
    final value = '${raw ?? ''}'.trim().toUpperCase();
    if (value.isEmpty) return 'FP';
    if (value.startsWith('W')) return 'WIP';
    if (value.startsWith('F')) return 'FP';
    return value;
  }

  factory PartItem.fromJson(Map<String, dynamic> json) {
    return PartItem(
      partNumber: (json['part_number'] ?? json['partno'] ?? '').toString(),
      jobNumber: (json['job_number'] ?? json['job_no'] ?? '').toString(),
      partName:
          (json['part_name'] ?? json['description'] ?? json['desc'] ?? '-')
              .toString(),
      customer: (json['customer'] ?? '-').toString(),
      model: (json['model'] ?? json['tipe'] ?? '-').toString(),
      unit: (json['unit'] ?? json['uom'] ?? 'PCS').toString(),
      area: (json['area'] ?? '-').toString(),
      location: (json['location'] ?? json['lokasi'] ?? '-').toString(),
      partType: normalizeType(
        json['part_type'] ?? json['status'] ?? json['type'],
      ),
      stdPack: int.tryParse('${json['std_pack'] ?? json['lot_size'] ?? 0}') ?? 0,
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
    );
  }

  Map<String, dynamic> toMap() => {
        'part_number': partNumber,
        'job_number': jobNumber,
        'part_name': partName,
        'customer': customer,
        'model': model,
        'unit': unit,
        'area': area,
        'location': location,
        'part_type': partType,
        'std_pack': stdPack,
        'search_index': searchIndex,
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory PartItem.fromMap(Map<String, dynamic> map) => PartItem(
        partNumber: map['part_number'] as String? ?? '',
        jobNumber: map['job_number'] as String? ?? '',
        partName: map['part_name'] as String? ?? '-',
        customer: map['customer'] as String? ?? '-',
        model: map['model'] as String? ?? '-',
        unit: map['unit'] as String? ?? 'PCS',
        area: map['area'] as String? ?? '-',
        location: map['location'] as String? ?? '-',
        partType: normalizeType(map['part_type']),
        stdPack: (map['std_pack'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse('${map['updated_at'] ?? ''}'),
      );
}
