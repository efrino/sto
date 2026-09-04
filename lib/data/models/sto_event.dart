import 'app_user.dart';

enum StoEventStatus {
  open('BUKA'),
  closed('TUTUP');

  const StoEventStatus(this.label);
  final String label;

  static StoEventStatus fromName(String? value) =>
      (value ?? '').trim().toLowerCase() == 'closed'
          ? StoEventStatus.closed
          : StoEventStatus.open;
}

/// Periode pelaksanaan STO. Tag hanya boleh dibuat saat ada event berstatus
/// BUKA, dan tiap tag menyimpan `event_id`-nya sebagai jejak periode.
class StoEvent {
  const StoEvent({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.areas = const [],
    this.status = StoEventStatus.open,
    this.createdBy = '-',
    required this.createdAt,
  });

  /// Dipakai saat server mengirim `end_date` kosong: periodenya belum
  /// ditentukan ujungnya, bukan berakhir hari itu juga.
  static final DateTime tanpaBatas = DateTime(2999, 12, 31);

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  /// Area yang dihitung pada event ini. Kosong = semua area.
  final List<String> areas;

  final StoEventStatus status;
  final String createdBy;
  final DateTime createdAt;

  bool get isOpen => status == StoEventStatus.open;

  /// Aktif = statusnya BUKA dan tanggal hari ini masuk rentang periode.
  bool isActiveOn(DateTime date) {
    if (!isOpen) return false;
    final day = DateTime(date.year, date.month, date.day);
    final from = DateTime(startDate.year, startDate.month, startDate.day);
    final to = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  bool coversArea(String area) {
    if (areas.isEmpty) return true;
    final target = area.trim().toUpperCase();
    return areas.any((a) => a.toUpperCase() == target);
  }

  bool get tanpaTanggalSelesai => endDate.year >= 2999;

  String get periodLabel => tanpaTanggalSelesai
      ? '${_d(startDate)} - belum ditentukan'
      : '${_d(startDate)} - ${_d(endDate)}';

  static String _d(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';

  String get areaLabel => areas.isEmpty ? 'Semua area' : areas.join(', ');

  StoEvent copyWith({
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? areas,
    StoEventStatus? status,
  }) {
    return StoEvent(
      id: id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      areas: areas ?? this.areas,
      status: status ?? this.status,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'areas': areas.join(','),
        'status': status.name,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory StoEvent.fromMap(Map<String, dynamic> map) => StoEvent(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '-',
        startDate: DateTime.tryParse('${map['start_date']}') ?? DateTime.now(),
        endDate: DateTime.tryParse('${map['end_date']}') ?? DateTime.now(),
        areas: AppUser.parseAreas(map['areas']),
        status: StoEventStatus.fromName(map['status'] as String?),
        createdBy: map['created_by'] as String? ?? '-',
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      );

  Map<String, dynamic> toApiJson() => {
        'id': id,
        'name': name,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'areas': areas,
        'status': status.name,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  /// Bentuk dari backend STO: `id_event`, `event_name`, `status` 1/0.
  factory StoEvent.fromServer(Map<String, dynamic> json) {
    final akhir = '${json['end_date'] ?? ''}'.trim();
    return StoEvent(
      id: '${json['id_event'] ?? json['id'] ?? ''}',
      name: '${json['event_name'] ?? json['name'] ?? '-'}',
      startDate: DateTime.tryParse('${json['start_date']}') ?? DateTime.now(),
      endDate: akhir.isEmpty
          ? tanpaBatas
          : (DateTime.tryParse(akhir) ?? tanpaBatas),
      // `events` di server belum punya kolom area - kosong berarti semua area.
      areas: const [],
      status: '${json['status']}' == '1'
          ? StoEventStatus.open
          : StoEventStatus.closed,
      createdBy: '${json['created_by'] ?? 'SERVER'}',
      createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
    );
  }

  factory StoEvent.fromJson(Map<String, dynamic> json) => StoEvent(
        id: (json['id'] ?? json['event_id'] ?? '').toString(),
        name: (json['name'] ?? json['nama'] ?? '-').toString(),
        startDate: DateTime.tryParse('${json['start_date']}') ?? DateTime.now(),
        endDate: DateTime.tryParse('${json['end_date']}') ?? DateTime.now(),
        areas: AppUser.parseAreas(json['areas'] ?? json['area']),
        status: StoEventStatus.fromName(json['status']?.toString()),
        createdBy: (json['created_by'] ?? '-').toString(),
        createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
      );
}
