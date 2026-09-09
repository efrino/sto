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

/// Letak sebuah periode STO terhadap hari ini.
enum JadwalEvent { akanDatang, berjalan, terlewat }

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
    this.bolehCetak = true,
    this.totalTim = 2,
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

  /// Izin mencetak tag baru pada event ini (`allow_print` di server).
  ///
  /// Terpisah dari [status] karena keduanya memang keputusan yang berbeda:
  /// menjelang akhir pelaksanaan, pencetakan tag dihentikan jauh sebelum
  /// perhitungannya selesai. Event tetap BUKA supaya hasil hitung masih bisa
  /// masuk, tapi tidak ada tag baru yang boleh keluar dari printer.
  final bool bolehCetak;

  /// Jumlah tim penghitung pada event ini - 1 atau 2 (`total_tim`).
  final int totalTim;

  final String createdBy;
  final DateTime createdAt;

  bool get isOpen => status == StoEventStatus.open;

  /// Boleh menyiapkan tag: event berjalan hari ini DAN pencetakan dibuka.
  bool bolehSiapkanPada(DateTime kini) => isActiveOn(kini) && bolehCetak;

  /// Alasan tag tidak bisa disiapkan; kosong berarti boleh.
  ///
  /// Sengaja menyebut sebabnya satu per satu: "tidak bisa mencetak" tanpa
  /// keterangan membuat operator menyangka printernya rusak, lalu ia mencabut
  /// dan menyambung ulang printer yang sebenarnya sehat.
  String alasanTidakBolehSiapkan(DateTime kini) {
    if (!isActiveOn(kini)) {
      return isOpen
          ? 'Event "$name" belum berjalan hari ini (${jadwalLabel(kini)}).'
          : 'Event "$name" sudah ditutup admin.';
    }
    if (!bolehCetak) {
      return 'Pencetakan tag pada event "$name" sedang ditutup admin. '
          'Hasil hitung tetap bisa dikirim.';
    }
    return '';
  }

  /// Aktif = statusnya BUKA dan tanggal hari ini masuk rentang periode.
  bool isActiveOn(DateTime date) {
    if (!isOpen) return false;
    final day = DateTime(date.year, date.month, date.day);
    final from = DateTime(startDate.year, startDate.month, startDate.day);
    final to = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  /// Letak periode ini terhadap hari yang sedang berjalan.
  ///
  /// Status BUKA saja tidak cukup memberi tahu apa pun: event yang dibuka
  /// bulan lalu dan sudah lewat tetap tampil "BUKA", dan operator baru sadar
  /// ada yang salah ketika tagnya ditolak. Keterangan ini memisahkan yang
  /// benar-benar berjalan hari ini dari yang belum mulai atau sudah lewat.
  JadwalEvent jadwalPada(DateTime kini) {
    final hari = DateTime(kini.year, kini.month, kini.day);
    final mulai = DateTime(startDate.year, startDate.month, startDate.day);

    if (hari.isBefore(mulai)) return JadwalEvent.akanDatang;
    if (tanpaTanggalSelesai) return JadwalEvent.berjalan;

    final selesai = DateTime(endDate.year, endDate.month, endDate.day);
    return hari.isAfter(selesai) ? JadwalEvent.terlewat : JadwalEvent.berjalan;
  }

  /// Selisih hari ke tanggal mulai (bila belum mulai) atau dari tanggal
  /// selesai (bila sudah lewat). Selalu >= 0.
  int selisihHari(DateTime kini) {
    final hari = DateTime(kini.year, kini.month, kini.day);
    switch (jadwalPada(kini)) {
      case JadwalEvent.akanDatang:
        return DateTime(startDate.year, startDate.month, startDate.day)
            .difference(hari)
            .inDays;
      case JadwalEvent.terlewat:
        return hari
            .difference(DateTime(endDate.year, endDate.month, endDate.day))
            .inDays;
      case JadwalEvent.berjalan:
        return 0;
    }
  }

  /// Kalimat pendek untuk ditempel di kartu event.
  String jadwalLabel([DateTime? saat]) {
    final kini = saat ?? DateTime.now();
    final jarak = selisihHari(kini);

    switch (jadwalPada(kini)) {
      case JadwalEvent.akanDatang:
        return jarak == 1 ? 'Mulai besok' : 'Mulai $jarak hari lagi';
      case JadwalEvent.terlewat:
        return jarak == 1
            ? 'Sudah lewat kemarin'
            : 'Sudah lewat $jarak hari lalu';
      case JadwalEvent.berjalan:
        if (tanpaTanggalSelesai) return 'Berlangsung hari ini';
        final sisa = DateTime(endDate.year, endDate.month, endDate.day)
            .difference(DateTime(kini.year, kini.month, kini.day))
            .inDays;
        if (sisa == 0) return 'Hari terakhir';
        if (sisa == 1) return 'Berlangsung, sisa 1 hari';
        return 'Berlangsung, sisa $sisa hari';
    }
  }

  /// true bila periodenya menaungi hari ini, apa pun status BUKA/TUTUP-nya.
  bool berjalanPada(DateTime kini) => jadwalPada(kini) == JadwalEvent.berjalan;

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
    bool? bolehCetak,
    int? totalTim,
  }) {
    return StoEvent(
      id: id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      areas: areas ?? this.areas,
      status: status ?? this.status,
      bolehCetak: bolehCetak ?? this.bolehCetak,
      totalTim: totalTim ?? this.totalTim,
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
        'allow_print': bolehCetak ? 1 : 0,
        'total_tim': totalTim,
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
        // Baris cache lama belum punya kolom ini. Diam-diam menganggapnya
        // "dilarang mencetak" akan mengunci handheld yang sedang offline,
        // jadi yang tidak diketahui dianggap boleh - server tetap yang
        // memutuskan begitu jaringannya kembali.
        bolehCetak: '${map['allow_print'] ?? 1}' != '0',
        totalTim: int.tryParse('${map['total_tim'] ?? 2}') ?? 2,
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
        'allow_print': bolehCetak ? 1 : 0,
        'total_tim': totalTim,
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
      // Deployment lama belum mengirim kolom ini sama sekali; ketiadaannya
      // dibaca sebagai "boleh", bukan "dilarang".
      bolehCetak: '${json['allow_print'] ?? 1}' != '0',
      totalTim: int.tryParse('${json['total_tim'] ?? 2}') ?? 2,
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
        bolehCetak: '${json['allow_print'] ?? 1}' != '0',
        totalTim: int.tryParse('${json['total_tim'] ?? 2}') ?? 2,
        createdBy: (json['created_by'] ?? '-').toString(),
        createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
      );
}
