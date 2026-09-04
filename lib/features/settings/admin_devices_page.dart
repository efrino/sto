import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models/app_user.dart';
import '../../data/models/sto_device.dart';
import '../../state/admin_provider.dart';
import '../../state/device_provider.dart';
import '../../state/session_provider.dart';
import 'widgets/sync_notice.dart';

/// Pendaftaran perangkat & pemasangan NIK (khusus admin).
///
/// Kunci pemasangan memakai ANDROID_ID, bukan MAC address - Android tidak
/// lagi mengizinkan aplikasi membaca MAC/serial. Admin memberi nomor aset
/// perusahaan (mis. 016-HSS-TBN) agar mudah dikenali di lapangan.
class AdminDevicesPage extends StatefulWidget {
  const AdminDevicesPage({super.key});

  @override
  State<AdminDevicesPage> createState() => _AdminDevicesPageState();
}

class _AdminDevicesPageState extends State<AdminDevicesPage> {
  /// NIK yang terpasang per perangkat, menurut server (`user-list?id_device`).
  ///
  /// Tidak diambil dari catatan lokal: pemasangan bisa diubah admin dari HT
  /// lain, jadi satu-satunya jawaban yang benar adalah jawaban server.
  final Map<int, List<AppUser>> _pengguna = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<SessionProvider>().user;
      context.read<DeviceProvider>().load(
        registeredBy: user?.nik ?? 'SYSTEM',
        admin: user,
      );
      context.read<AdminProvider>().load();
    });
  }

  Future<void> _muatPengguna() async {
    final devices = context.read<DeviceProvider>();
    final hasil = <int, List<AppUser>>{};
    for (final d in devices.devices) {
      final id = d.serverId;
      if (id == null) continue;
      hasil[id] = await devices.penggunaPerangkat(id);
    }
    if (!mounted) return;
    setState(() {
      _pengguna
        ..clear()
        ..addAll(hasil);
    });
  }

  Future<void> _editAssetName(StoDevice device) async {
    final controller = TextEditingController(text: device.assetName);
    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nomor aset perangkat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9.\-/ ]')),
            LengthLimitingTextInputFormatter(20),
          ],
          decoration: const InputDecoration(
            hintText: 'contoh: 016-HSS-TBN',
            helperText: 'Nomor aset perusahaan yang tertempel di perangkat',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (hasil == null || !mounted) return;

    final devices = context.read<DeviceProvider>();
    await devices.setAssetName(device, hasil);
    if (!mounted) return;
    AppFeedback.info(context, devices.message ?? 'Tersimpan.');
    devices.clearMessage();
  }

  Future<void> _pair(StoDevice device) async {
    final admin = context.read<AdminProvider>();
    final kandidat = admin.users.where((u) => !device.allows(u.nik)).toList();

    final pilihan = await showModalBottomSheet<AppUser>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _PilihNik(users: kandidat, device: device),
    );
    if (pilihan == null || !mounted) return;

    final devices = context.read<DeviceProvider>();
    final lain = await devices.otherDevicesWith(pilihan.nik, device.deviceId);
    if (!mounted) return;

    if (lain.isNotEmpty) {
      final lanjut = await AppFeedback.confirm(
        context,
        title: 'NIK sudah terpasang di perangkat lain',
        message: '${pilihan.nik} masih terpasang pada '
            '${lain.map((d) => d.label).join(", ")}. Pasang juga di sini?',
        confirmLabel: 'Pasang juga',
      );
      if (!lanjut || !mounted) return;
    }

    await devices.pair(device, pilihan.nik);
    if (!mounted) return;
    AppFeedback.success(context, devices.message ?? 'Tersimpan.');
    devices.clearMessage();
    await _muatPengguna();
  }

  Future<void> _unpair(StoDevice device, String nik) async {
    final ok = await AppFeedback.confirm(
      context,
      title: 'Lepas pemasangan?',
      message: 'NIK $nik tidak akan bisa login lagi di perangkat '
          '${device.label}.',
      confirmLabel: 'Lepas',
      destructive: true,
    );
    if (!ok || !mounted) return;

    final devices = context.read<DeviceProvider>();
    await devices.unpair(device, nik);
    if (!mounted) return;
    AppFeedback.info(context, devices.message ?? 'Selesai.');
    devices.clearMessage();
    await _muatPengguna();
  }

  Future<void> _unpairAll(StoDevice device) async {
    final ok = await AppFeedback.confirm(
      context,
      title: 'Lepas semua NIK?',
      message: 'Dipakai saat event STO selesai: seluruh NIK '
          '(${device.nikLabel}) dilepas dari ${device.label} sehingga '
          'perangkat tidak bisa dipakai login sampai dipasangkan lagi.',
      confirmLabel: 'Lepas semua',
      destructive: true,
    );
    if (!ok || !mounted) return;

    final devices = context.read<DeviceProvider>();
    await devices.unpairAll(device);
    if (!mounted) return;
    AppFeedback.info(context, devices.message ?? 'Selesai.');
    devices.clearMessage();
    await _muatPengguna();
  }

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<DeviceProvider>();
    // Daftar NIK menyusul setelah daftar perangkat terbaca.
    if (!devices.loading && _pengguna.length != devices.devices.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _muatPengguna());
    }
    final identity = devices.identity;
    final current = devices.current;

    return Scaffold(
      appBar: AppBar(title: const Text('Perangkat & Pairing')),
      body: devices.loading && current == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (devices.peringatanSinkron != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SyncNotice(message: devices.peringatanSinkron!),
                  ),
                SectionCard(
                  title: 'Perangkat ini',
                  subtitle: identity == null
                      ? null
                      : '${identity.model} - Android ${identity.androidVersion}',
                  icon: Icons.smartphone,
                  child: current == null
                      ? const Text('Identitas perangkat belum terbaca.')
                      : _kartuPerangkat(current, ini: true),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Perangkat terdaftar',
                  subtitle: 'Daftar perangkat dan NIK terpasangnya dari server',
                  icon: Icons.devices_other,
                  child: Column(
                    children: [
                      for (final device in devices.devices
                          .where((d) => d.deviceId != current?.deviceId)) ...[
                        _kartuPerangkat(device, ini: false),
                        const Divider(height: 24),
                      ],
                      if (devices.devices.length <= 1)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Belum ada perangkat lain. Perangkat baru otomatis '
                            'muncul di sini setelah admin login di perangkat '
                            'tersebut.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.infoSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Kunci pemasangan memakai ANDROID_ID, bukan MAC address: '
                    'sejak Android 6/10 aplikasi biasa tidak boleh membaca MAC '
                    'maupun nomor seri. ANDROID_ID tetap sama setelah restart '
                    'dan install ulang, dan berubah hanya bila perangkat '
                    'di-factory reset.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<String> _nikPerangkat(StoDevice device) {
    final id = device.serverId;
    if (id == null) return device.niks; // belum terdaftar di server
    return (_pengguna[id] ?? const <AppUser>[]).map((u) => u.nik).toList();
  }

  String _nikLabel(StoDevice device) {
    final daftar = _nikPerangkat(device);
    return daftar.isEmpty ? 'Belum dipasangkan' : daftar.join(', ');
  }

  /// Menghapus perangkat lain dari server. Server menahan dengan `confirm`
  /// selama masih ada user yang memakainya; penegasannya diminta di sini.
  Future<void> _hapusPerangkat(StoDevice device) async {
    final serverId = device.serverId;
    if (serverId == null) return;

    final devices = context.read<DeviceProvider>();
    final terpasang = _nikPerangkat(device);

    final ok = await AppFeedback.confirm(
      context,
      title: 'Hapus ${device.label}?',
      message: terpasang.isEmpty
          ? 'Perangkat ini dihapus dari daftar server.'
          : 'Perangkat ini masih dipakai ${terpasang.length} NIK '
              '(${terpasang.join(', ')}). Akunnya TIDAK dihapus, tapi '
              'pemasangan perangkatnya dilepas sehingga mereka tidak bisa '
              'login sampai dipasangkan lagi.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;

    await devices.deleteServerDevice(serverId, force: terpasang.isNotEmpty);
    if (!mounted) return;
    AppFeedback.info(context, devices.message ?? 'Selesai.');
    devices.clearMessage();
    await _muatPengguna();
  }

  Widget _kartuPerangkat(StoDevice device, {required bool ini}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                device.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: device.terdaftar
                      ? AppColors.navy
                      : AppColors.textSecondary,
                ),
              ),
            ),
            if (ini)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'PERANGKAT INI',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${device.model}  -  ID ${device.deviceId}',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        if (device.lastSeenAt != null)
          Text(
            'Terakhir dipakai ${Formatters.relative(device.lastSeenAt)}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        const SizedBox(height: 10),
        Text(
          'NIK terpasang: ${_nikLabel(device)}',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (_nikPerangkat(device).isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _nikPerangkat(device)
                .map(
                  (nik) => InputChip(
                    label: Text(nik),
                    onDeleted: () => _unpair(device, nik),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _editAssetName(device),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: Text(device.terdaftar ? 'Ubah nomor aset' : 'Beri nomor aset'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
            ElevatedButton.icon(
              onPressed: () => _pair(device),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Pasang NIK'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
            if (!ini && device.serverId != null)
              OutlinedButton.icon(
                onPressed: () => _hapusPerangkat(device),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hapus perangkat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.dangerSoft),
                  minimumSize: const Size(0, 40),
                ),
              ),
            if (_nikPerangkat(device).isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _unpairAll(device),
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Lepas semua'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.dangerSoft),
                  minimumSize: const Size(0, 40),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: device.active,
          onChanged: (value) async {
            final devices = context.read<DeviceProvider>();
            await devices.setActive(device, value);
            if (!mounted) return;
            AppFeedback.info(context, devices.message ?? 'Selesai.');
            devices.clearMessage();
          },
          title: const Text('Perangkat aktif'),
          subtitle: const Text(
            'Nonaktifkan untuk memblokir semua login di perangkat ini.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _PilihNik extends StatelessWidget {
  const _PilihNik({required this.users, required this.device});

  final List<AppUser> users;
  final StoDevice device;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: users.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Semua user sudah terpasang di perangkat ini, atau daftar user '
                'masih kosong (tambahkan lewat Setting > User).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            )
          : ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    'Pasang NIK ke ${device.label}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                for (final user in users)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: user.isAdmin
                          ? AppColors.primarySoft
                          : AppColors.navySoft,
                      child: Text(
                        user.initials,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color:
                              user.isAdmin ? AppColors.primary : AppColors.navy,
                        ),
                      ),
                    ),
                    title: Text(user.name),
                    subtitle: Text(
                      '${user.nik}  -  ${user.role.label}'
                      '${user.hasTeam ? ' - ${user.team}' : ''}',
                    ),
                    onTap: () => Navigator.pop(context, user),
                  ),
              ],
            ),
    );
  }
}
