import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models/app_user.dart';
import '../../data/models/print_entry.dart';
import '../../data/models/sto_event.dart';
import 'widgets/teks_berjalan.dart';
import '../../state/chat_provider.dart';
import '../../state/admin_provider.dart';
import '../../state/count_provider.dart';
import '../../state/prepare_provider.dart';
import '../../state/print_history_provider.dart';
import '../../state/printer_provider.dart';
import '../../state/session_provider.dart';

/// Pemegang kepala layar yang menempel di atas.
///
/// Tingginya tetap - tidak mengecil saat digulir. Kepala yang menyusut
/// membuat isinya berpindah-pindah tempat, dan tombol keluar termasuk yang
/// paling tidak boleh berpindah: menekannya karena salah sasaran berarti
/// sesi operator berakhir di tengah pekerjaan.
class _KepalaTetap extends SliverPersistentHeaderDelegate {
  const _KepalaTetap({required this.tinggi, required this.anak});

  final double tinggi;
  final Widget anak;

  @override
  double get minExtent => tinggi;

  @override
  double get maxExtent => tinggi;

  @override
  Widget build(BuildContext context, double geser, bool tumpangTindih) =>
      SizedBox.expand(child: anak);

  @override
  bool shouldRebuild(_KepalaTetap lama) =>
      lama.tinggi != tinggi || lama.anak != anak;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ChatProvider? _chat;
  AdminProvider? _admin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refresh();
      if (!mounted) return;
      // Beranda tetap hidup di bawah layar Siapkan/Scan yang dibuka di
      // atasnya, jadi denyut yang dinyalakan di sini ikut menyegarkan pita
      // event di layar-layar itu juga - event dibuka/ditutup dan pencetakan
      // dinyalakan/dimatikan admin dari perangkat lain.
      final user = context.read<SessionProvider>().user;
      if (user != null) _admin?.mulaiDenyutEvent(user);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chat = context.read<ChatProvider>();
    _admin = context.read<AdminProvider>();
  }

  @override
  void dispose() {
    _chat?.hentikanDenyutDaftar();
    _admin?.hentikanDenyutEvent();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Identitas disegarkan lebih dulu: perubahan izin oleh admin harus
    // langsung terasa di menu, tanpa menunggu login berikutnya.
    await context.read<SessionProvider>().refresh();
    if (!mounted || context.read<SessionProvider>().user == null) return;

    await context.read<CountProvider>().load(
      user: context.read<SessionProvider>().user,
    );
    if (!mounted || context.read<SessionProvider>().user == null) return;

    // Event berjalan ditarik dari server di sini, bukan menunggu operator
    // membuka menu Siapkan. Splash berjalan SEBELUM login, jadi saat itu
    // belum ada NIK yang bisa dipakai bertanya - akibatnya event baru muncul
    // setelah masuk menu, dan operator mengira eventnya belum dibuka.
    await context.read<AdminProvider>().refreshActiveEvent(
          pengakses: context.read<SessionProvider>().user,
        );
    if (!mounted || context.read<SessionProvider>().user == null) return;

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
      // Badge pesan ikut disegarkan di sini - dan denyut berkala dimulai
      // agar bubble notifikasi pesan di beranda selalu terbarui secara realtime.
      final chat = context.read<ChatProvider>();
      await chat.muatThreads(user);
      if (!mounted) return;
      chat.mulaiDenyutDaftar(user);
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
    context.read<ChatProvider>().reset();
    await context.read<SessionProvider>().logout();
    if (!mounted) return;
    context.read<PrepareProvider>().resetAll();
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    final isAdmin = user?.isAdmin ?? false;
    final admin = context.watch<AdminProvider>();
    final hasActiveEvent = admin.hasActiveEvent;
    final counts = context.watch<CountProvider>();
    final printer = context.watch<PrinterProvider>();
    final cetak = context.watch<PrintHistoryProvider>().history;
    final summary = counts.summary;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            // Menempel di atas saat digulir. Tombol keluar ada di kepala ini,
            // dan pada handheld yang dipakai bergantian antar-shift, orang
            // yang mau keluar seharusnya tidak perlu menggulir ke atas dulu
            // untuk mencarinya.
            SliverPersistentHeader(
              pinned: true,
              delegate: _KepalaTetap(
                tinggi: _tinggiKepala(context),
                anak: _header(
                  user?.name ?? '-',
                  user?.nik ?? '-',
                  user?.role.label ?? '-',
                  user?.areaLabel ?? '-',
                  printer,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Event ditaruh di atas ringkasan: tanpa event yang
                  // berjalan, angka apa pun di bawahnya tidak akan bertambah
                  // hari ini - itu yang perlu diketahui lebih dulu.
                  _pitaEvent(admin.eventDisorot),
                  const SizedBox(height: 10),
                  _summaryCard(summary, cetak, counts, user),
                  const SizedBox(height: 12),
                  // Kartu aksi (Prepare, Scan, Batal STO & Tag OK) hanya
                  // ditampilkan saat ada event STO yang sedang aktif.
                  if (hasActiveEvent) ...[
                    _actionRow(user),
                    if (user?.punyaTagOk ?? false) ...[
                      const SizedBox(height: 10),
                      _actionRowTagOk(user),
                    ],
                  ] else ...[
                    _tidakAdaEventCard(isAdmin),
                  ],
                  // Jarak sedikit lebih lebar sebelum Riwayat & Setting:
                  // keduanya bukan aksi lapangan, jadi dipisahkan dari
                  // deretan kartu kerja supaya tidak tertekan tanpa sengaja.
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '${AppConfig.appName} v1.1.0',
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

  // ------------------------------------------------- ukuran kepala layar
  //
  // Angka-angka ini dipakai DUA kali: oleh _header saat menggambar, dan oleh
  // _tinggiKepala saat memberi tahu sliver berapa tinggi yang harus
  // disediakan. Karena kepala ini menempel, sliver menuntut angka pasti - dan
  // begitu keduanya ditulis terpisah, satu perubahan kecil pada tata letak
  // membuatnya berselisih dan isinya meluber. Itu sudah terjadi dua kali.
  static const double _kepalaAtas = 8;
  static const double _kepalaBawah = 10;
  static const double _kepalaLogo = 46;

  static const TextStyle _gayaNama = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
  static const TextStyle _gayaPeran = TextStyle(
    fontSize: 11.5,
    color: Colors.white70,
  );
  static const TextStyle _gayaArea = TextStyle(
    fontSize: 11,
    color: Colors.white60,
  );

  /// Tinggi kepala layar, diukur dari teks yang benar-benar dipakai.
  ///
  /// Diukur, bukan ditebak: tinggi baris bergantung pada font bawaan sistem,
  /// gaya turunan dari tema, dan setelan ukuran huruf pemakainya. Tebakan
  /// angka mati sudah dua kali meleset di H10.
  double _tinggiKepala(BuildContext context) {
    final mq = MediaQuery.of(context);

    // Gaya dasar dari tema ikut disertakan - kalau tema memasang tinggi baris
    // atau jenis huruf sendiri, mengukur dengan TextStyle telanjang akan
    // menghasilkan angka yang lebih pendek daripada yang digambar.
    final dasar = DefaultTextStyle.of(context).style;

    double tinggiBaris(TextStyle gaya) {
      final pelukis = TextPainter(
        // Huruf berkaki-atas dan berkaki-bawah sekaligus, supaya yang terukur
        // tinggi baris penuh - bukan tinggi huruf yang kebetulan pendek.
        text: TextSpan(text: 'Ag', style: dasar.merge(gaya)),
        maxLines: 1,
        textScaler: mq.textScaler,
        textDirection: TextDirection.ltr,
      )..layout();
      return pelukis.height;
    }

    final tinggiTeks = tinggiBaris(_gayaNama) +
        tinggiBaris(_gayaPeran) +
        tinggiBaris(_gayaArea);

    // Logo jadi batas bawah: pada setelan huruf terkecil, teksnya lebih
    // pendek dari logo dan kepala akan terlihat gepeng.
    final isi = tinggiTeks > _kepalaLogo ? tinggiTeks : _kepalaLogo;

    // Sisa sedikit di luar hasil ukuran. Perangkat uji (H10, ukuran huruf
    // sistem 1,15x) menggambar barisnya beberapa piksel lebih tinggi daripada
    // yang dilaporkan TextPainter, dan sebabnya belum tertelusuri. Sisa ini
    // membuat FittedBox di bawah tidak perlu mengecilkan teks pada pemakaian
    // biasa - ia tetap ada sebagai pengaman kalau selisihnya lebih besar di
    // perangkat lain.
    const sisa = 10.0;

    return mq.padding.top + _kepalaAtas + isi + _kepalaBawah + sisa;
  }

  Widget _header(
    String name,
    String nik,
    String peran,
    String area,
    PrinterProvider printer,
  ) {
    return Container(
      // Jarak atas mengikuti bilah status perangkat, bukan angka mati -
      // tingginya berbeda antara handheld dan HP pribadi bertakik.
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + _kepalaAtas,
        16,
        _kepalaBawah,
      ),
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
            width: _kepalaLogo,
            height: _kepalaLogo,
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
            // Jaring pengaman terakhir: kalau tinggi hasil ukuran meleset
            // sekali pun, teksnya mengecil sedikit - bukan memunculkan pita
            // kuning-hitam "overflow" di depan operator. Pada keadaan normal
            // BoxFit.scaleDown tidak mengubah apa pun.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, style: _gayaNama),
                  Text(
                    // Akun server memakai NIK sebagai nama, jadi
                    // menuliskannya dua kali hanya bikin ramai.
                    name == nik ? peran : 'NIK $nik  -  $peran',
                    maxLines: 1,
                    style: _gayaPeran,
                  ),
                  Text(area, maxLines: 1, style: _gayaArea),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _printerIndicator(printer),
          const SizedBox(width: 10),
          _logoutButton(),
        ],
      ),
    );
  }

  /// Tombol keluar dengan aksen merah dan ikon shutdown (power_settings_new).
  Widget _logoutButton() {
    return Tooltip(
      message: 'Keluar',
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(7.5),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFF87171).withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: const Icon(
            Icons.power_settings_new,
            size: 19,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// Indikator printer di kepala layar: menampilkan label Printer dan
  /// status Terhubung / Tidak terhubung. Ketuk untuk mencoba menyambung lagi.
  Widget _printerIndicator(PrinterProvider printer) {
    final connected = printer.isConnected;
    final busy = printer.busy;
    final statusText = busy
        ? 'Menyambung...'
        : (connected ? 'Terhubung' : 'Tidak terhubung');

    final tooltip = connected
        ? 'Printer tersambung (${printer.statusLabel})'
        : (printer.sebabGagal ?? 'Printer belum tersambung - ketuk untuk coba lagi');

    return RepaintBoundary(
      child: Tooltip(
        message: tooltip,
        child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (connected || busy) ? null : () => printer.cobaLagi(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: connected
                    ? const Color(0xFF4ADE80).withValues(alpha: 0.55)
                    : const Color(0xFFFBBF24).withValues(alpha: 0.55),
                width: 1.1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connected ? Icons.print : Icons.print_disabled,
                  size: 17,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Printer',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: connected
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFFFBBF24),
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 3),
                        if (busy)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          Icon(
                            connected ? Icons.check_circle : Icons.refresh,
                            size: 11,
                            color: connected
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFFFBBF24),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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

  /// Kartu pemberitahuan saat tidak ada event STO yang sedang aktif berjalan.
  Widget _tidakAdaEventCard(bool isAdmin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.dangerSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_busy,
              size: 26,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tidak Ada Event STO Aktif',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isAdmin
                ? 'Semua Fitur disembunyikan karena belum ada event aktif. Buka menu Setting > Event untuk memulai event.'
                : 'Belum ada event STO yang aktif berjalan.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openThenRefresh(AppRoutes.adminEvents),
              icon: const Icon(Icons.event, size: 17),
              label: const Text('Buka Menu Event STO'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Keadaan event STO hari ini, sebagai pita satu baris.
  ///
  /// Dulu ini kartu setinggi tiga baris. Di layar handheld, tinggi itu cukup
  /// mendorong satu baris menu turun ke bawah layar - dan operator yang
  /// terburu-buru menggulir untuk mencari tombol yang seharusnya terlihat
  /// sejak awal. Keterangannya sama lengkapnya, hanya berjalan mendatar.
  Widget _pitaEvent(StoEvent? event) {
    final (warna, latar, ikon, teks) = switch (event) {
      null => (
          AppColors.danger,
          AppColors.dangerSoft,
          Icons.event_busy,
          'Belum ada event STO yang berjalan - tag belum bisa dibuat. '
              'Minta admin membukanya lewat Setting > Event.',
        ),
      final StoEvent e => switch (e.jadwalPada(DateTime.now())) {
          // Event berjalan, tapi pencetakan bisa saja ditutup admin. Keduanya
          // harus terbaca berbeda: pita hijau bertuliskan "Berlangsung" di
          // atas tombol cetak yang mati membuat operator menyangka
          // aplikasinya rusak, lalu ia mencabut-sambung printer yang sehat.
          JadwalEvent.berjalan when !e.bolehCetak => (
              AppColors.warning,
              AppColors.warningSoft,
              Icons.print_disabled,
              '${e.name}  -  ${e.periodLabel}  -  ${e.areaLabel}  -  '
                  'pencetakan tag ditutup admin, hasil hitung tetap bisa '
                  'dikirim',
            ),
          JadwalEvent.berjalan => (
              AppColors.success,
              AppColors.successSoft,
              Icons.event_available,
              '${e.name}  -  ${e.periodLabel}  -  ${e.areaLabel}  -  '
                  '${e.jadwalLabel()}',
            ),
          JadwalEvent.akanDatang => (
              AppColors.info,
              AppColors.navySoft,
              Icons.schedule,
              '${e.name}  -  ${e.periodLabel}  -  ${e.jadwalLabel()}  -  '
                  'tag belum bisa dibuat pada periode ini',
            ),
          JadwalEvent.terlewat => (
              AppColors.danger,
              AppColors.dangerSoft,
              Icons.history_toggle_off,
              '${e.name}  -  ${e.periodLabel}  -  ${e.jadwalLabel()}  -  '
                  'tag belum bisa dibuat pada periode ini',
            ),
        },
    };

    return RepaintBoundary(
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: latar,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(ikon, size: 15, color: warna),
            const SizedBox(width: 8),
            Expanded(
              child: TeksBerjalan(
                teks: teks,
                gaya: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: warna,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(
    Map<String, int> summary,
    PrintHistory cetak,
    CountProvider counts,
    AppUser? user,
  ) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      title: 'Ringkasan hari ini',
      // Tidak ada lagi tombol sinkron di sini: hasil scan dan keadaan cetak
      // dikirim ke server begitu terjadi, jadi angka di kartu ini memang
      // sudah yang terbaru - tombol sinkron hanya menyiratkan sebaliknya.
      //
      // Nama event juga TIDAK ditulis di sini. Keterangannya sudah lengkap
      // pada pita di atas; mengulangnya hanya memakan satu baris lagi pada
      // layar yang justru sedang dihemat.
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
        padding: const EdgeInsets.symmetric(vertical: 9),
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
        // Tinggi kartu ini dipangkas setelah diukur di H10: dua baris kartu
        // aksi memakan hampir sepertiga layar, dan itu yang mendorong menu
        // Pesan/Riwayat turun ke bawah lipatan.
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 6),
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
        padding: const EdgeInsets.symmetric(vertical: 13),
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
            const SizedBox(height: 6),
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
