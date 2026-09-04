import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models/app_user.dart';
import '../../data/models/print_entry.dart';
import '../../state/chat_provider.dart';
import '../../state/count_provider.dart';
import '../../state/prepare_provider.dart';
import '../../state/print_history_provider.dart';
import '../../state/printer_provider.dart';
import '../../state/session_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    // Identitas disegarkan lebih dulu: perubahan izin oleh admin harus
    // langsung terasa di menu, tanpa menunggu login berikutnya.
    await context.read<SessionProvider>().refresh();
    if (!mounted) return;

    await context.read<CountProvider>().load(
      user: context.read<SessionProvider>().user,
    );
    if (!mounted) return;

    // Angka cetak diambil dari server supaya sama dengan yang dilihat admin,
    // termasuk tag yang dicetak dari perangkat lain.
    final user = context.read<SessionProvider>().user;
    if (user != null) {
      final printer = context.read<PrinterProvider>();
      // Setelan jarak milik bersama - ditarik ulang di sini juga supaya
      // handheld yang baru login langsung memakai angka yang sama, tanpa
      // harus membuka Setting > Printer lebih dulu.
      printer.nikPembaca = user.nik;
      await printer.muatSetelanServer();
      if (!mounted) return;
      await context.read<PrintHistoryProvider>().load(user, limit: 200);
      if (!mounted) return;
      // Badge pesan ikut disegarkan di sini - tanpa notifikasi sistem, beranda
      // adalah tempat pertama orang tahu ada pesan baru.
      await context.read<ChatProvider>().muatThreads(user);
    }
  }

  /// Ringkasan hari ini ikut diperbarui setelah kembali dari halaman yang
  /// bisa mengubah status tag (scan / riwayat).
  Future<void> _openThenRefresh(String route) async {
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _logout() async {
    final ok = await AppFeedback.confirm(
      context,
      title: 'Keluar aplikasi?',
      message:
          'Data tag yang belum tersinkron tetap tersimpan di perangkat ini.',
      confirmLabel: 'Keluar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<SessionProvider>().logout();
    if (!mounted) return;
    context.read<PrepareProvider>().resetAll();
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    final isAdmin = user?.isAdmin ?? false;
    final counts = context.watch<CountProvider>();
    final printer = context.watch<PrinterProvider>();
    final cetak = context.watch<PrintHistoryProvider>().history;
    final summary = counts.summary;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _header(
                user?.name ?? '-',
                user?.nik ?? '-',
                user?.role.label ?? '-',
                user?.areaLabel ?? '-',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _printerCard(printer),
                  const SizedBox(height: 14),
                  _summaryCard(summary, cetak, counts, user),
                  const SizedBox(height: 14),
                  // Kartu aksi dibuat setara bentuknya, dan hanya yang
                  // haknya diberikan admin yang ditampilkan.
                  _actionRow(user),
                  const SizedBox(height: 12),
                  // Tag OK memakai bentuk kartu yang sama dengan tag STO -
                  // aksinya memang sejenis. Yang membedakan hanya warnanya
                  // (navy) dan keterangan kecil di bawah judul, supaya
                  // operator tidak salah masuk menu saat terburu-buru.
                  if (user?.punyaTagOk ?? false) ...[
                    const SizedBox(height: 12),
                    _actionRowTagOk(user),
                  ],
                  // Jarak lebih lebar sebelum Riwayat & Setting: keduanya
                  // bukan aksi lapangan, jadi dipisahkan dari deretan kartu
                  // kerja supaya tidak tertekan tanpa sengaja.
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _menuTile(
                          icon: Icons.forum_outlined,
                          label: 'Pesan',
                          // Badge di sini satu-satunya penanda pesan baru:
                          // tidak ada notifikasi sistem, jadi jumlahnya harus
                          // terlihat begitu beranda dibuka.
                          badge: context.watch<ChatProvider>().belumDibaca,
                          onTap: () => _openThenRefresh(AppRoutes.chat),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _menuTile(
                          icon: Icons.history,
                          // Satu pintu saja: isinya (cetak / scan /
                          // pembatalan) mengikuti izin user.
                          label: 'Riwayat',
                          onTap: () => _openThenRefresh(AppRoutes.history),
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _menuTile(
                            icon: Icons.settings_outlined,
                            label: 'Setting',
                            onTap: () => _openThenRefresh(AppRoutes.settings),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      '${AppConfig.appName} v1.0.0',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String name, String nik, String peran, String area) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 52, 16, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // Garis merah tipis di sisi logo - identitas perusahaan tetap
              // hadir tanpa membuat kepala layar terbaca sebagai peringatan.
              border: Border(
                left: BorderSide(color: AppColors.accent, width: 4),
              ),
            ),
            padding: const EdgeInsets.all(6),
            child: Image.asset('assets/images/icon-maj.png'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  // Akun server memakai NIK sebagai nama, jadi menuliskannya
                  // dua kali hanya bikin ramai.
                  name == nik ? peran : 'NIK $nik  -  $peran',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
                Text(
                  area,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Keluar',
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _printerCard(PrinterProvider printer) {
    final connected = printer.isConnected;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: connected ? AppColors.successSoft : AppColors.warningSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              connected ? Icons.print : Icons.print_disabled,
              color: connected ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Printer',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  printer.statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          // Tidak ada tombol setelan di sini: printer disetel admin lewat
          // Setting, dan angkanya berlaku untuk semua handheld. Yang
          // dibutuhkan operator di halaman utama hanya tahu printernya siap
          // atau tidak.
          Icon(
            connected ? Icons.check_circle : Icons.error_outline,
            size: 20,
            color: connected ? AppColors.success : AppColors.warning,
          ),
        ],
      ),
    );
  }

  /// Baris kartu aksi sesuai hak akses user.
  Widget _actionRow(AppUser? user) {
    final kartu = <Widget>[
      if (user?.canPrepare ?? false)
        _actionCard(
          icon: Icons.qr_code_2,
          title: 'Siapkan',
          onTap: () => _openThenRefresh(AppRoutes.search),
        ),
      if (user?.canScan ?? false)
        _actionCard(
          icon: Icons.qr_code_scanner,
          title: 'Scan',
          onTap: () => _openThenRefresh(AppRoutes.scan),
        ),
      if (user?.canCancel ?? false)
        _actionCard(
          icon: Icons.block,
          title: 'Batal',
          onTap: () => _openThenRefresh(AppRoutes.cancel),
        ),
    ];

    if (kartu.isEmpty) {
      return SectionCard(
        padding: const EdgeInsets.all(16),
        child: const Text(
          'Belum ada hak akses menu untuk NIK ini. Minta admin mengaturnya '
          'lewat Setting > User.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < kartu.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: kartu[i]),
        ],
      ],
    );
  }

  /// Baris kartu Tag OK - izinnya dipisah dari tag STO.
  Widget _actionRowTagOk(AppUser? user) {
    final kartu = <Widget>[
      if (user?.canPrepareOk ?? false)
        _actionCard(
          icon: Icons.playlist_add_check,
          title: 'Siapkan',
          subtitle: 'Tag OK',
          warna: _tagOkWarna,
          onTap: () => _openThenRefresh(AppRoutes.siapkanTagOk),
        ),
      if (user?.canScanOk ?? false)
        _actionCard(
          icon: Icons.inventory_2_outlined,
          title: 'Scan',
          subtitle: 'Tag OK',
          warna: _tagOkWarna,
          onTap: () => _openThenRefresh(AppRoutes.scanTagOk),
        ),
      if (user?.canCancelOk ?? false)
        _actionCard(
          icon: Icons.block,
          title: 'Batal',
          subtitle: 'Tag OK',
          warna: _tagOkWarna,
          onTap: () => _openThenRefresh(AppRoutes.batalTagOk),
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < kartu.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: kartu[i]),
        ],
      ],
    );
  }

  /// Warna kartu Tag OK - navy, sekeluarga dengan biru utama tapi cukup
  /// berbeda untuk dikenali sekilas.
  static const List<Color> _tagOkWarna = [
    AppColors.navy,
    Color(0xFF0B1B33),
  ];

  Widget _summaryCard(
    Map<String, int> summary,
    PrintHistory cetak,
    CountProvider counts,
    AppUser? user,
  ) {
    return SectionCard(
      title: 'Ringkasan hari ini',
      // Tidak ada lagi tombol sinkron di sini: hasil scan dan keadaan cetak
      // dikirim ke server begitu terjadi, jadi angka di kartu ini memang
      // sudah yang terbaru - tombol sinkron hanya menyiratkan sebaliknya.
      subtitle: 'Langsung dari server',
      icon: Icons.insights,
      child: Row(
        children: [
          // Angka yang ditampilkan mengikuti hak akses: yang tidak dipegang
          // user tidak perlu muncul supaya kartunya tetap ringkas.
          if (user?.canScan ?? false)
            _stat(
              'Tag discan',
              summary['scan'] ?? 0,
              AppColors.navy,
              AppColors.navySoft,
            ),
          if (user?.canPrepare ?? false)
            _stat(
              'Tag dicetak',
              cetak.printed,
              AppColors.success,
              AppColors.successSoft,
            ),
          // Hanya muncul bila memang ada yang tertinggal - kartunya tetap
          // ringkas saat semuanya beres.
          if ((user?.canPrepare ?? false) && cetak.menunggu > 0)
            _stat(
              'Belum keluar',
              cetak.menunggu,
              AppColors.warning,
              AppColors.warningSoft,
            ),
          if (user?.canCancel ?? false)
            _stat(
              'Tag batal',
              summary['cancel'] ?? 0,
              AppColors.danger,
              AppColors.dangerSoft,
            ),
          // Tanpa satu pun izin, angka apa pun tidak berarti - yang berguna
          // justru memberitahu apa yang harus dilakukan.
          if (!(user?.canScan ?? false) &&
              !(user?.canPrepare ?? false) &&
              !(user?.canCancel ?? false))
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  'Akun ini belum diberi akses menu. Minta admin '
                  'mengaturnya lewat Setting > User & Izin.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color, Color background) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu aksi utama - dipakai dua kali dengan bentuk identik.
  Widget _actionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String subtitle = 'Tag STO',
    List<Color> warna = const [AppColors.primary, AppColors.primaryDark],
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: warna,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 34),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            badge > 0
                ? Badge(
                    label: Text('$badge'),
                    backgroundColor: AppColors.accent,
                    child: Icon(icon, color: AppColors.navy, size: 26),
                  )
                : Icon(icon, color: AppColors.navy, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
