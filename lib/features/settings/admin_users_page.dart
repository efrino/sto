import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/app_user.dart';
import '../../state/admin_provider.dart';
import '../../state/session_provider.dart';
import 'widgets/area_picker.dart';
import 'widgets/sync_notice.dart';

/// CRUD user + izin area (khusus admin).
///
/// Area yang dicentang di sini menentukan part apa saja yang muncul pada
/// halaman Siapkan Tag milik user tersebut.
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminProvider>().load(
        admin: context.read<SessionProvider>().user,
      ),
    );
  }

  Future<void> _openForm({AppUser? user}) async {
    final admin = context.read<AdminProvider>();

    final hasil = await showModalBottomSheet<AppUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _UserForm(
        user: user,
        areaOptions: admin.areas,
        teamOptions: admin.teamOptions,
      ),
    );
    if (hasil == null || !mounted) return;

    await admin.saveUser(hasil, previousNik: user?.nik);
    if (!mounted) return;

    // Bila yang disunting adalah akun yang sedang dipakai di perangkat ini,
    // sesinya ditarik ulang: menu harus langsung mengikuti izin barunya,
    // bukan menunggu login berikutnya.
    final aktif = context.read<SessionProvider>().user;
    if (aktif != null &&
        (aktif.nik == hasil.nik || aktif.nik == (user?.nik ?? ''))) {
      await context.read<SessionProvider>().refresh();
      if (!mounted) return;
    }

    AppFeedback.info(context, admin.message ?? 'Tersimpan.');
    admin.clearMessage();
  }

  Future<void> _delete(AppUser user) async {
    final admin = context.read<AdminProvider>();
    final aktif = context.read<SessionProvider>().user;
    if (aktif != null && aktif.nik == user.nik) {
      AppFeedback.error(
        context,
        'Tidak bisa menghapus akun yang sedang login.',
      );
      return;
    }

    final ok = await AppFeedback.confirm(
      context,
      title: 'Hapus user?',
      message:
          'NIK ${user.nik} tidak akan bisa login lagi. '
          'Riwayat tag yang pernah dibuatnya tetap tersimpan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;

    await admin.deleteUser(user.nik);
    if (!mounted) return;
    AppFeedback.info(context, admin.message ?? 'Selesai.');
    admin.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('User & Izin')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('USER BARU'),
      ),
      body: Column(
        children: [
          if (admin.peringatanSinkron != null)
            SyncNotice(message: admin.peringatanSinkron!),
          Expanded(
            child: admin.loading && admin.users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : admin.users.isEmpty
                ? EmptyState(
                    icon: Icons.group_outlined,
                    title: 'Belum ada user',
                    message:
                        'Tambahkan operator beserta area yang boleh '
                        'disiapkan tagnya.',
                    actionLabel: 'Tambah user',
                    onAction: () => _openForm(),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: admin.users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final user = admin.users[index];
                      return _UserTile(
                        user: user,
                        onEdit: () => _openForm(user: user),
                        onDelete: () => _delete(user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.onEdit,
    required this.onDelete,
  });

  final AppUser user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: user.isAdmin
                  ? AppColors.primarySoft
                  : AppColors.navySoft,
              child: Text(
                user.initials,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: user.isAdmin ? AppColors.primary : AppColors.navy,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.nik,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: user.isAdmin
                              ? AppColors.primarySoft
                              : AppColors.navySoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          user.role.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: user.isAdmin
                                ? AppColors.primary
                                : AppColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.teamLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Area: ${user.areaLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Izin ditampilkan sebagai chip, bukan satu baris teks
                  // panjang: admin perlu melihat sekilas menu mana yang
                  // dipegang seseorang sebelum memutuskan mengubahnya.
                  if (user.isAdmin)
                    _chipIzin('Semua menu', AppColors.primary,
                        AppColors.primarySoft)
                  else if (user.permissions.isEmpty)
                    _chipIzin('Belum diberi akses', AppColors.danger,
                        AppColors.dangerSoft)
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final izin in user.permissions)
                          _chipIzin(izin.label, AppColors.navy,
                              AppColors.navySoft),
                      ],
                    ),
                  if (!user.active)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Nonaktif - tidak bisa login',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Barisnya memang bisa diketuk, tetapi tanpa tombol yang
            // terlihat tidak ada yang tahu izinnya bisa disunting.
            Column(
              children: [
                IconButton(
                  tooltip: 'Ubah peran, izin & area',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined,
                      color: AppColors.primary),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.danger),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _chipIzin(String teks, Color warna, Color latar) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        teks,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: warna,
        ),
      ),
    );

class _UserForm extends StatefulWidget {
  const _UserForm({
    required this.user,
    required this.areaOptions,
    required this.teamOptions,
  });

  final AppUser? user;
  final List<String> areaOptions;

  /// Tim aktif yang dikelola admin (Setting > Tim penghitung).
  final List<String> teamOptions;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  late final TextEditingController _nik;
  String? _team;
  late UserRole _role;
  late List<String> _areas;
  late List<AppPermission> _permissions;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _nik = TextEditingController(text: user?.nik ?? '');
    // Tim lama yang sudah dihapus dari daftar tetap ditampilkan sebagai
    // pilihan supaya data user tidak diam-diam berubah saat disimpan ulang.
    final tim = (user?.team ?? '').trim().toUpperCase();
    _team = tim.isEmpty ? null : tim;
    _role = user?.role ?? UserRole.operator;
    _areas = List<String>.from(user?.areas ?? const []);
    _permissions = List<AppPermission>.from(
      user?.permissions ?? AppPermission.values,
    );
    _active = user?.active ?? true;
  }

  @override
  void dispose() {
    _nik.dispose();
    super.dispose();
  }

  /// Tim aktif + tim lama milik user ini (kalau sudah dinonaktifkan admin).
  List<String> get _pilihanTim {
    final daftar = <String>{...widget.teamOptions};
    if (_team != null) daftar.add(_team!);
    final hasil = daftar.toList()..sort();
    return hasil;
  }

  void _submit() {
    Navigator.pop(
      context,
      AppUser(
        nik: _nik.text.trim().toUpperCase(),
        // Server tidak menyimpan nama karyawan, jadi NIK sekaligus menjadi
        // identitas yang ditampilkan - bukan nama kosong yang membingungkan.
        name: _nik.text.trim().toUpperCase(),
        role: _role,
        areas: _role == UserRole.admin ? const [] : _areas,
        team: _team ?? '',
        // Admin memang selalu punya semua menu, jadi daftar izinnya diisi
        // penuh supaya tetap benar bila perannya diturunkan lagi nanti.
        permissions: _role == UserRole.admin
            ? AppPermission.values
            : _permissions,
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.user == null ? 'User baru' : 'Ubah user',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nik,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9./\-]')),
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: const InputDecoration(
                labelText: 'NIK',
                hintText: 'NIK karyawan',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Akun STO dikenali dari NIK saja - server tidak menyimpan nama, '
              'departemen, maupun seksi.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _team,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Belum diatur'),
                ),
                for (final tim in _pilihanTim)
                  DropdownMenuItem<String>(value: tim, child: Text('TIM $tim')),
              ],
              onChanged: (value) => setState(() => _team = value),
              decoration: const InputDecoration(
                labelText: 'Tim',
                helperText:
                    'Ikut terkirim setiap kali user ini mencatat qty. '
                    'Daftarnya diatur di Setting > Tim penghitung.',
                helperMaxLines: 3,
                prefixIcon: Icon(Icons.groups_outlined),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Peran',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            // Dibungkus scroll horizontal supaya tetap aman di layar sempit
            // atau saat ukuran font perangkat diperbesar.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(
                    value: UserRole.operator,
                    icon: Icon(Icons.badge_outlined, size: 18),
                    label: Text('Operator'),
                  ),
                  ButtonSegment(
                    value: UserRole.admin,
                    icon: Icon(Icons.shield_outlined, size: 18),
                    label: Text('Admin'),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (value) =>
                    setState(() => _role = value.first),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _role == UserRole.admin
                  ? 'Admin: bisa membuka Setting, mengelola user & event, dan '
                        'menyetujui pembatalan tag. Tidak dibatasi area.'
                  : 'Operator: menyiapkan & mencetak tag, scan tag, dan hanya '
                        'bisa mengajukan pembatalan.',
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (_role == UserRole.operator) ...[
              const Text(
                'Hak akses menu',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Text(
                'Menu yang tidak dicentang tidak muncul di halaman utama '
                'user ini. Tanpa centang sama sekali, user hanya bisa login '
                'tanpa bisa membuka menu apa pun.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              for (final izin in AppPermission.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _permissions.contains(izin),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _permissions = [..._permissions, izin];
                    } else {
                      _permissions = _permissions
                          .where((p) => p != izin)
                          .toList();
                    }
                  }),
                  title: Text(
                    izin.label,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            if (_role == UserRole.operator)
              AreaPicker(
                title: 'Area yang boleh disiapkan',
                helper: 'Part di halaman Siapkan Tag dibatasi area ini; '
                    'boleh lebih dari satu. Kosongkan bila boleh semua area.',
                options: widget.areaOptions,
                selected: _areas,
                onChanged: (value) => setState(() => _areas = value),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (value) => setState(() => _active = value),
              title: const Text('Akun aktif'),
              subtitle: const Text(
                'Nonaktifkan untuk memblokir login tanpa menghapus datanya.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text('SIMPAN USER'),
            ),
          ],
        ),
      ),
    );
  }
}
