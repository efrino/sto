import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/section_card.dart';
import '../../services/printer/bluetooth_printer_service.dart';
import '../../services/printer/mock_printer_service.dart';
import '../../state/admin_provider.dart';
import '../../state/printer_provider.dart';
import '../../state/session_provider.dart';
import '../../state/settings_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().bootstrap();
      final user = context.read<SessionProvider>().user;
      context.read<AdminProvider>().load(
        seedCreatedBy: user?.nik ?? 'SYSTEM',
        admin: user,
      );
    });
  }

  Future<void> _editBaseUrl(SettingsProvider settings) async {
    final terpilih = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Alamat server',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Pilih sesuai jaringan handheld: HTTP untuk jaringan pabrik, '
                'HTTPS bila lewat internet.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            for (final e in AppConfig.serverPilihan.entries)
              ListTile(
                title: Text(e.key),
                subtitle: Text(
                  e.value,
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: settings.baseUrl == e.value
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, e.value),
              ),
          ],
        ),
      ),
    );
    if (terpilih == null || !mounted) return;

    await settings.setBaseUrl(terpilih);
    if (!mounted) return;
    AppFeedback.success(context, 'Alamat server disimpan.');
  }


  Future<void> _togglePrinterSimulation(
    SettingsProvider settings,
    PrinterProvider printer,
    bool value,
  ) async {
    await settings.setPrinterSimulation(value);
    await printer.forgetPrinter();
    printer.swapService(
      value ? MockPrinterService() : BluetoothPrinterService(),
    );
    if (!mounted) return;
    AppFeedback.info(
      context,
      value
          ? 'Mode simulasi aktif - hasil cetak hanya ditulis ke log.'
          : 'Mode printer nyata aktif. Pilih ulang printer di menu Printer.',
    );
  }

  Future<void> _seedDemo(SettingsProvider settings) async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final ok = await AppFeedback.confirm(
      context,
      title: 'Buat data contoh?',
      message:
          'Menambah 8 tag uji coba bernomor awalan DEMO (3 sudah dicetak, '
          '2 draft, 2 dibatalkan, 1 tercetak menunggu sinkron). Data ini hanya '
          'tersimpan di perangkat dan bisa dihapus lewat "Hapus seluruh data lokal".',
      confirmLabel: 'Buat',
    );
    if (!ok || !mounted) return;

    await settings.seedDemoData(user);
    if (!mounted) return;
    AppFeedback.info(context, settings.message ?? 'Selesai.');
    settings.clearMessage();
  }

  Future<void> _wipe(SettingsProvider settings) async {
    final ok = await AppFeedback.confirm(
      context,
      title: 'Hapus seluruh data lokal?',
      message:
          'Riwayat tag yang belum tersinkron akan ikut hilang dan tidak bisa '
          'dikembalikan. Pastikan sudah menekan Sinkron lebih dulu.',
      confirmLabel: 'Hapus semua',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await settings.wipeLocalData();
    if (!mounted) return;
    AppFeedback.info(context, settings.message ?? 'Data lokal dihapus.');
    settings.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final printer = context.watch<PrinterProvider>();
    final user = context.watch<SessionProvider>().user;

    // Menu ini milik admin, termasuk setelan printer: angkanya tersimpan di
    // server dan berlaku untuk semua handheld.
    if (user == null || !user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setting')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Khusus admin',
          message: 'Pengaturan server, event STO, user, dan printer hanya '
              'bisa diubah admin. Printer tetap tersambung sendiri saat Anda '
              'mencetak.',
          actionLabel: 'Kembali',
          onAction: () => Navigator.pop(context),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Setting')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SectionCard(
            title: 'Pengelolaan STO',
            subtitle: 'Periode pelaksanaan dan hak akses operator',
            icon: Icons.admin_panel_settings_outlined,
            child: Column(
              children: [
                _tile(
                  icon: Icons.event_note_outlined,
                  title: 'Event STO',
                  subtitle: _eventSubtitle(context),
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.adminEvents),
                ),
                const Divider(height: 20),
                _tile(
                  icon: Icons.group_outlined,
                  title: 'User & izin area',
                  subtitle: 'Tambah operator, atur peran, tim, dan areanya',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.adminUsers),
                ),

                const Divider(height: 20),
                _tile(
                  icon: Icons.smartphone,
                  title: 'Perangkat & pairing',
                  subtitle: 'Pasang NIK ke perangkat, lepas saat event selesai',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.adminDevices),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Server & API',
            subtitle: 'Endpoint STO sudah aktif; matikan simulasi untuk memakainya',
            icon: Icons.dns_outlined,
            child: Column(
              children: [
                _tile(
                  icon: Icons.link,
                  title: 'Alamat server',
                  subtitle: AppConfig.serverPilihan.entries
                      .where((e) => e.value == settings.baseUrl)
                      .map((e) => '${e.key}\n${e.value}')
                      .firstOrNull ??
                      settings.baseUrl,
                  onTap: () => _editBaseUrl(settings),
                ),
                const Divider(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.useMock,
                  onChanged: (value) async {
                    await settings.setUseMock(value);
                    if (!context.mounted) return;
                    AppFeedback.info(
                      context,
                      value
                          ? 'Aplikasi memakai data simulasi.'
                          : 'Aplikasi memanggil API server.',
                    );
                  },
                  title: const Text('Gunakan data simulasi'),
                  subtitle: const Text(
                    'Matikan setelah endpoint STO Preparation tersedia.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Printer',
            subtitle: 'Blueprint MPOS 332 (printer internal)',
            icon: Icons.print_outlined,
            child: Column(
              children: [
                _tile(
                  icon: Icons.bluetooth,
                  title: 'Pilih / sambungkan printer',
                  subtitle: printer.statusLabel,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.printerSetup),
                ),
                const Divider(height: 20),
                _tile(
                  icon: Icons.straighten,
                  title: 'Ukuran kertas',
                  subtitle: printer.paperSize.label,
                  onTap: () async {
                    final selected = await showModalBottomSheet<PaperSize>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: PaperSize.values
                              .map(
                                (size) => ListTile(
                                  title: Text(size.label),
                                  trailing: printer.paperSize == size
                                      ? const Icon(
                                          Icons.check,
                                          color: AppColors.primary,
                                        )
                                      : null,
                                  onTap: () => Navigator.pop(ctx, size),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    );
                    if (selected != null) await printer.setPaperSize(selected);
                  },
                ),
                const Divider(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: printer.autoConnect,
                  onChanged: printer.setAutoConnect,
                  title: const Text('Sambung otomatis saat aplikasi dibuka'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.printerSimulation,
                  onChanged: (value) =>
                      _togglePrinterSimulation(settings, printer, value),
                  title: const Text('Mode simulasi printer'),
                  subtitle: const Text(
                    'Untuk emulator / HP tanpa printer internal.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Data & Cache',
            icon: Icons.storage_outlined,
            child: Column(
              children: [
                _tile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Master part tersimpan',
                  subtitle:
                      '${settings.cacheInfo.count} part - diperbarui ${Formatters.relative(settings.cacheInfo.lastSyncedAt)}',
                  trailing: settings.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, color: AppColors.navy),
                  onTap: settings.busy
                      ? null
                      : () async {
                          await settings.refreshMasterCache();
                          if (!context.mounted) return;
                          AppFeedback.info(
                            context,
                            settings.message ?? 'Selesai.',
                          );
                          settings.clearMessage();
                        },
                ),
                const Divider(height: 20),
                _tile(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Hapus cache master part',
                  subtitle: 'Riwayat tag tetap aman',
                  onTap: () async {
                    await settings.clearPartCache();
                    if (!context.mounted) return;
                    AppFeedback.info(context, settings.message ?? 'Selesai.');
                    settings.clearMessage();
                  },
                ),
                if (settings.useMock) ...[
                  const Divider(height: 20),
                  _tile(
                    icon: Icons.science_outlined,
                    title: 'Isi data contoh',
                    subtitle:
                        'Riwayat tag uji coba (cetak / draft / batal), awalan DEMO',
                    trailing: settings.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, color: AppColors.navy),
                    onTap: settings.busy ? null : () => _seedDemo(settings),
                  ),
                ],
                const Divider(height: 20),
                _tile(
                  icon: Icons.delete_forever_outlined,
                  title: 'Hapus seluruh data lokal',
                  subtitle: 'Termasuk riwayat tag',
                  color: AppColors.danger,
                  onTap: () => _wipe(settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Lainnya',
            icon: Icons.tune,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.soundEnabled,
                  onChanged: settings.setSoundEnabled,
                  title: const Text('Bunyi & getar saat cetak'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text(
              '${AppConfig.appName} v1.0.0\n${AppConfig.companyName} - ${AppConfig.departement}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ringkasan event aktif untuk ditampilkan pada menu.
  String _eventSubtitle(BuildContext context) {
    final event = context.watch<AdminProvider>().activeEvent;
    if (event == null) return 'Belum ada event aktif - operator tidak bisa cetak';
    return '${event.name} (${event.periodLabel})';
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color color = AppColors.navy,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: trailing ??
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
