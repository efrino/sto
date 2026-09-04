import 'app_user.dart';

/// Perangkat perusahaan yang dipakai untuk STO.
///
/// Login operator hanya sah bila NIK-nya terpasang pada perangkat ini
/// (dikunci oleh ANDROID_ID, bukan MAC address - lihat DeviceIdentityService).
class StoDevice {
  const StoDevice({
    required this.deviceId,
    this.assetName = '',
    this.model = '-',
    this.niks = const [],
    this.active = true,
    required this.registeredAt,
    this.registeredBy = '-',
    this.lastSeenAt,
    this.serverId,
    this.totalUserServer = 0,
  });

  /// ANDROID_ID perangkat.
  final String deviceId;

  /// Nomor aset perusahaan, mis. 016-HSS-TBN.
  final String assetName;

  final String model;

  /// NIK yang boleh login di perangkat ini (boleh lebih dari satu, mis. shift).
  final List<String> niks;

  final bool active;
  final DateTime registeredAt;
  final String registeredBy;
  final DateTime? lastSeenAt;

  /// `devices.id` di server. null = perangkat ini baru ada di perangkat
  /// (belum didaftarkan lewat device-create).
  final int? serverId;

  /// `total_user` menurut server - jumlah user yang device_id-nya menunjuk
  /// ke perangkat ini. Tidak sama dengan [niks], yang merupakan catatan lokal.
  final int totalUserServer;

  bool get terdaftarDiServer => serverId != null;

  bool get terdaftar => assetName.trim().isNotEmpty;

  String get label => terdaftar ? assetName : 'Belum diberi nomor aset';

  String get nikLabel => niks.isEmpty ? 'Belum dipasangkan' : niks.join(', ');

  bool allows(String nik) {
    final target = nik.trim().toUpperCase();
    return niks.any((n) => n.trim().toUpperCase() == target);
  }

  StoDevice copyWith({
    String? assetName,
    String? model,
    List<String>? niks,
    bool? active,
    int? serverId,
    int? totalUserServer,
    DateTime? lastSeenAt,
  }) {
    return StoDevice(
      deviceId: deviceId,
      assetName: assetName ?? this.assetName,
      model: model ?? this.model,
      niks: niks ?? this.niks,
      active: active ?? this.active,
      registeredAt: registeredAt,
      registeredBy: registeredBy,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      serverId: serverId ?? this.serverId,
      totalUserServer: totalUserServer ?? this.totalUserServer,
    );
  }

  Map<String, dynamic> toMap() => {
        'device_id': deviceId,
        'asset_name': assetName,
        'model': model,
        'niks': niks.join(','),
        'active': active ? 1 : 0,
        'registered_at': registeredAt.toIso8601String(),
        'registered_by': registeredBy,
        'last_seen_at': lastSeenAt?.toIso8601String(),
        'server_id': serverId,
        'total_user_server': totalUserServer,
      };

  factory StoDevice.fromMap(Map<String, dynamic> map) => StoDevice(
        deviceId: map['device_id'] as String? ?? '',
        assetName: (map['asset_name'] as String? ?? '').trim(),
        model: map['model'] as String? ?? '-',
        niks: AppUser.parseAreas(map['niks']),
        active: ((map['active'] as num?)?.toInt() ?? 1) == 1,
        registeredAt:
            DateTime.tryParse('${map['registered_at']}') ?? DateTime.now(),
        registeredBy: map['registered_by'] as String? ?? '-',
        lastSeenAt: DateTime.tryParse('${map['last_seen_at']}'),
        serverId: (map['server_id'] as num?)?.toInt(),
        totalUserServer: (map['total_user_server'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toApiJson() => {
        'device_id': deviceId,
        'asset_name': assetName,
        'model': model,
        'niks': niks,
        'active': active,
        'registered_at': registeredAt.toIso8601String(),
        'registered_by': registeredBy,
        'last_seen_at': lastSeenAt?.toIso8601String(),
      };

  factory StoDevice.fromJson(Map<String, dynamic> json) => StoDevice(
        deviceId: (json['device_id'] ?? '').toString(),
        assetName: (json['asset_name'] ?? json['nama_aset'] ?? '').toString(),
        model: (json['model'] ?? '-').toString(),
        niks: AppUser.parseAreas(json['niks'] ?? json['nik']),
        active: json['active'] == null ||
            json['active'] == true ||
            json['active'] == 1,
        registeredAt:
            DateTime.tryParse('${json['registered_at']}') ?? DateTime.now(),
        registeredBy: (json['registered_by'] ?? '-').toString(),
        lastSeenAt: DateTime.tryParse('${json['last_seen_at']}'),
      );
}
