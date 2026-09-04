/// Hak akses per menu, diatur admin untuk tiap user.
enum AppPermission {
  prepare('Siapkan & cetak tag'),
  scan('Scan & input qty'),
  cancel('Ajukan pembatalan'),
  prepareOk('Siapkan Tag OK'),
  scanOk('Scan Tag OK'),
  cancelOk('Batal Tag OK');

  const AppPermission(this.label);
  final String label;

  static AppPermission? fromName(String? value) {
    // Dibandingkan tanpa peduli besar-kecil huruf: nama izin Tag OK memakai
    // camelCase ("prepareOk"), dan sebelumnya nilai dari server dikecilkan
    // lebih dulu sehingga tidak pernah cocok - izinnya hilang diam-diam.
    final v = (value ?? '').trim().toLowerCase();
    for (final p in AppPermission.values) {
      if (p.name.toLowerCase() == v) return p;
    }
    return null;
  }

  static List<AppPermission> parse(Object? raw) {
    if (raw == null) return const [];
    final items = raw is List
        ? raw.map((e) => '$e')
        : '$raw'.split(RegExp(r'[|,;]')).map((e) => e.trim());
    return items
        .map(AppPermission.fromName)
        .whereType<AppPermission>()
        .toList();
  }
}

/// Peran user - menentukan menu dan wewenang pembatalan tag.
enum UserRole {
  admin('Admin'),
  operator('Operator');

  const UserRole(this.label);
  final String label;

  static UserRole fromName(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return v == 'admin' ? UserRole.admin : UserRole.operator;
  }
}

/// User aplikasi: identitas sesi sekaligus baris data pada
/// menu Setting > User (CRUD oleh admin).
class AppUser {
  const AppUser({
    required this.nik,
    required this.name,
    this.department = '-',
    this.section = '-',
    this.role = UserRole.operator,
    this.areas = const [],
    this.team = '',
    this.permissions = AppPermission.values,
    this.active = true,
    this.token,
  });

  final String nik;
  final String name;
  final String department;
  final String section;
  final UserRole role;

  /// Area yang boleh disiapkan tagnya. Kosong = semua area
  /// (dipakai admin dan user yang belum dibatasi).
  final List<String> areas;

  /// Tim tempat user ini berada. Isinya hanya nama tim (mis. "A") yang
  /// dipilih dari daftar tim milik admin - bukan teks bebas. Ikut dikirim
  /// setiap kali hasil hitung disimpan, dan menjadi kunci "satu tim satu
  /// angka per tag".
  final String team;

  /// Menu yang boleh dipakai user ini. Admin selalu dianggap punya semuanya.
  final List<AppPermission> permissions;

  final bool active;
  final String? token;

  bool get isAdmin => role == UserRole.admin;

  /// Admin selalu bebas; operator dibatasi bila daftar areanya diisi.
  bool get hasAreaLimit => !isAdmin && areas.isNotEmpty;

  bool can(AppPermission permission) =>
      isAdmin || permissions.contains(permission);

  bool get canPrepare => can(AppPermission.prepare);
  bool get canScan => can(AppPermission.scan);
  bool get canCancel => can(AppPermission.cancel);

  // Tag OK berdiri sendiri dari tag STO: petugasnya sering beda orang, jadi
  // izinnya juga dipisah - memegang "Siapkan Tag" tidak otomatis berarti
  // berhak menyiapkan Tag OK.
  bool get canPrepareOk => can(AppPermission.prepareOk);
  bool get canScanOk => can(AppPermission.scanOk);
  bool get canCancelOk => can(AppPermission.cancelOk);

  /// true bila user memegang salah satu izin Tag OK.
  bool get punyaTagOk => canPrepareOk || canScanOk || canCancelOk;

  String get permissionLabel {
    if (isAdmin) return 'Semua menu';
    if (permissions.isEmpty) return 'Belum diberi akses';
    return permissions.map((p) => p.label).join(', ');
  }

  bool get hasTeam => team.trim().isNotEmpty;

  String get teamLabel => hasTeam ? 'TIM $team' : 'Tim belum diatur';

  String get areaLabel => areas.isEmpty
      ? (isAdmin ? 'Semua area' : 'Belum diatur')
      : areas.join(', ');

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  /// Menerima "A", "a", maupun nilai lama "TIM A" - semuanya menjadi "A"
  /// supaya cocok dengan daftar tim yang dikelola admin.
  static String parseTeam(Object? raw) {
    var value = '${raw ?? ''}'.trim().toUpperCase();
    if (value.startsWith('TIM ')) value = value.substring(4).trim();
    return value;
  }

  /// Menerima "WH 1,WH 2", ["WH 1","WH 2"], maupun null.
  static List<String> parseAreas(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => '$e'.trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return '$raw'
        .split(RegExp(r'[|,;]'))
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  AppUser copyWith({
    String? nik,
    String? name,
    String? department,
    String? section,
    UserRole? role,
    List<String>? areas,
    String? team,
    List<AppPermission>? permissions,
    bool? active,
    String? token,
  }) {
    return AppUser(
      nik: nik ?? this.nik,
      name: name ?? this.name,
      department: department ?? this.department,
      section: section ?? this.section,
      role: role ?? this.role,
      areas: areas ?? this.areas,
      team: team ?? this.team,
      permissions: permissions ?? this.permissions,
      active: active ?? this.active,
      token: token ?? this.token,
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      nik: json['nik']?.toString() ?? '',
      name: (json['name'] ?? json['nama'] ?? json['full_name'] ?? '-')
          .toString(),
      department: (json['department'] ?? json['dept'] ?? '-').toString(),
      section: (json['section'] ?? '-').toString(),
      role: UserRole.fromName(json['role']?.toString()),
      areas: parseAreas(json['areas'] ?? json['area']),
      team: parseTeam(json['team'] ?? json['tim']),
      permissions: json['permissions'] == null
          ? AppPermission.values
          : AppPermission.parse(json['permissions']),
      active: json['active'] == null ||
          json['active'] == true ||
          json['active'] == 1 ||
          json['active'] == '1',
      token: json['token']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'nik': nik,
        'name': name,
        'department': department,
        'section': section,
        'role': role.name,
        'areas': areas,
        'team': team,
        'permissions': permissions.map((p) => p.name).toList(),
        'active': active,
        'token': token,
      };

  /// Baris tabel `users` di database lokal.
  Map<String, dynamic> toMap() => {
        'nik': nik,
        'name': name,
        'department': department,
        'section': section,
        'role': role.name,
        'areas': areas.join(','),
        'team': team,
        'permissions': permissions.map((p) => p.name).join(','),
        'active': active ? 1 : 0,
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        nik: map['nik'] as String? ?? '',
        name: map['name'] as String? ?? '-',
        department: map['department'] as String? ?? '-',
        section: map['section'] as String? ?? '-',
        role: UserRole.fromName(map['role'] as String?),
        areas: parseAreas(map['areas']),
        team: parseTeam(map['team']),
        // Baris lama (sebelum kolom permissions ada) dianggap punya semua akses
        // supaya user yang sudah bekerja tidak mendadak kehilangan menu.
        permissions: map['permissions'] == null
            ? AppPermission.values
            : AppPermission.parse(map['permissions']),
        active: ((map['active'] as num?)?.toInt() ?? 1) == 1,
      );
}
