import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/app_user.dart';
import '../../data/models/print_entry.dart';
import '../../data/models/sto_count.dart';
import '../../state/count_provider.dart';
import '../../state/print_history_provider.dart';
import '../../state/printer_provider.dart';
import '../../state/session_provider.dart';

/// Tombol sinkron riwayat scan - dipakai AppBar halaman Riwayat.
class ScanHistorySyncButton extends StatelessWidget {
  const ScanHistorySyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final counts = context.watch<CountProvider>();
    return IconButton(
      tooltip: 'Sinkronkan ke server',
      onPressed: counts.syncing
          ? null
          : () async {
              await counts.sync();
              if (!context.mounted) return;
              AppFeedback.info(
                context,
                counts.message ?? 'Sinkronisasi selesai.',
              );
              counts.clearMessage();
            },
      icon: counts.syncing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Badge(
              isLabelVisible: counts.pendingSync > 0,
              label: Text('${counts.pendingSync}'),
              child: const Icon(Icons.sync),
            ),
    );
  }
}

/// Saringan keadaan pada riwayat tag STO.
///
/// Keadaannya datang dari dua sumber - cetak (`print-history`) dan hitung
/// (`scan-history`) - jadi tiap saringan menyebut sendiri izin yang
/// mensyaratkannya. Chip yang izinnya tidak dipegang user tidak ditampilkan.
enum SaringanSto {
  semua('Semua', null),
  belumCetak('Belum cetak', AppPermission.prepare),
  gagal('Gagal cetak', AppPermission.prepare),
  discan('Sudah discan', AppPermission.scan),
  pembatalan('Pembatalan', AppPermission.cancel);

  const SaringanSto(this.label, this.izin);

  final String label;

  /// Izin yang harus dipegang user agar saringan ini masuk akal baginya;
  /// null = selalu tampil.
  final AppPermission? izin;

  /// Saringan yang boleh dilihat [user].
  static List<SaringanSto> untuk(AppUser? user) {
    if (user == null) return const [];
    return values
        .where((s) => s.izin == null || user.can(s.izin!))
        .toList(growable: false);
  }
}

/// Satu baris riwayat STO - entah kejadian cetak atau hasil hitung.
///
/// Keduanya disatukan supaya urutan waktunya benar-benar menyambung: tag yang
/// dicetak pagi lalu dihitung siang tampil berurutan, bukan terpisah di dua
/// tab yang harus dibandingkan sendiri oleh pembacanya.
class BarisRiwayatSto {
  const BarisRiwayatSto.cetak(PrintEntry this.cetak) : hitung = null;
  const BarisRiwayatSto.hitung(StoCount this.hitung) : cetak = null;

  final PrintEntry? cetak;
  final StoCount? hitung;

  String get tagNo => cetak?.tagNo ?? hitung!.tagNo;

  /// Waktu yang dipakai mengurutkan - kejadian terakhir pada baris itu.
  DateTime get waktu => cetak != null
      ? (cetak!.printedAt ?? cetak!.createdAt)
      : (hitung!.updatedAt ?? hitung!.countedAt);

  bool cocok(SaringanSto saringan) => switch (saringan) {
        SaringanSto.semua => true,
        SaringanSto.belumCetak => cetak != null &&
            !cetak!.canceled &&
            !cetak!.cancelDiajukan &&
            cetak!.state == PrintState.draft,
        SaringanSto.gagal => cetak != null &&
            !cetak!.canceled &&
            !cetak!.cancelDiajukan &&
            cetak!.state == PrintState.error,
        SaringanSto.discan => hitung != null,
        SaringanSto.pembatalan =>
          cetak != null && (cetak!.canceled || cetak!.cancelDiajukan),
      };

  /// Menyusun daftar gabungan, terbaru lebih dulu.
  ///
  /// Isinya mengikuti izin: baris cetak hanya untuk yang berhak menyiapkan
  /// atau membatalkan, baris hitung hanya untuk yang berhak scan. Tanpa itu
  /// operator melihat kejadian dari pekerjaan yang bukan bagiannya.
  static List<BarisRiwayatSto> gabung({
    required AppUser? user,
    required List<PrintEntry> cetak,
    required List<StoCount> hitung,
  }) {
    if (user == null) return const [];

    final baris = <BarisRiwayatSto>[
      if (user.canPrepare || user.canCancel)
        for (final e in cetak)
          // Yang hanya berhak membatalkan cukup melihat baris pembatalannya,
          // bukan seluruh riwayat cetak orang lain.
          if (user.canPrepare || e.canceled || e.cancelDiajukan)
            BarisRiwayatSto.cetak(e),
      if (user.canScan)
        for (final c in hitung) BarisRiwayatSto.hitung(c),
    ];

    baris.sort((a, b) => b.waktu.compareTo(a.waktu));
    return baris;
  }
}

/// Riwayat tag STO dalam satu daftar.
///
/// Sebelumnya cetak, scan, dan pembatalan berdiri sebagai tiga tab terpisah -
/// padahal ketiganya kejadian pada tag yang sama. Menyatukannya membuat satu
/// tag bisa ditelusuri dari dibuat sampai dihitung tanpa berpindah tab, sama
/// seperti riwayat Tag OK.
class StoHistoryView extends StatefulWidget {
  const StoHistoryView({super.key});

  @override
  State<StoHistoryView> createState() => _StoHistoryViewState();
}

class _StoHistoryViewState extends State<StoHistoryView> {
  final _cari = TextEditingController();
  final _debounce = Debouncer();
  SaringanSto _saringan = SaringanSto.semua;

  /// Cetak ulang otomatis dijalankan sekali per kunjungan - bukan tiap kali
  /// layar dibangun ulang.
  bool _sudahCobaOtomatis = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  @override
  void dispose() {
    _cari.dispose();
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    // Kedua sumber ditarik menurut izin: menanyakan riwayat cetak untuk user
    // yang tidak berhak menyiapkan hanya menambah beban server.
    if (user.canPrepare || user.canCancel) {
      await context.read<PrintHistoryProvider>().load(user);
    }
    if (!mounted) return;
    if (user.canScan) {
      await context.read<CountProvider>().load(user: user);
    }
    if (!mounted || _sudahCobaOtomatis || !user.canPrepare) return;

    // Tag yang tertinggal dicetak sendiri begitu printer normal - operator
    // tidak perlu mengingat mana yang belum keluar.
    _sudahCobaOtomatis = true;
    final riwayat = context.read<PrintHistoryProvider>();
    final jumlah = await riwayat.cetakUlangOtomatis(
      context.read<PrinterProvider>(),
      user,
    );
    if (!mounted || jumlah == 0) return;
    AppFeedback.success(context, '$jumlah tag tertinggal dicetak ulang.');
  }

  void _terapkanCari(String nilai) {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    // Pencarian dikirim ke server, jadi yang tercari SELURUH riwayat - bukan
    // hanya baris yang kebetulan sudah terambil.
    if (user.canPrepare || user.canCancel) {
      context.read<PrintHistoryProvider>().setKeyword(user, nilai);
    }
    if (user.canScan) {
      context.read<CountProvider>().setKeyword(nilai);
    }
    setState(() {});
  }

  Future<void> _cetakUlang() async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final riwayat = context.read<PrintHistoryProvider>();
    final printer = context.read<PrinterProvider>();

    if (!printer.isConnected && !await printer.ensureReady()) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        'Printer belum siap. Sambungkan dulu lewat Setting > Printer.',
      );
      return;
    }

    final jumlah = await riwayat.cetakUlang(printer, user);
    if (!mounted) return;

    if (jumlah > 0) {
      AppFeedback.success(context, riwayat.message ?? 'Cetak ulang selesai.');
    } else {
      AppFeedback.error(context, riwayat.error ?? 'Tidak ada yang dicetak.');
    }
    riwayat.clearMessage();
  }

  /// Admin membatalkan tag yang tetap tidak keluar dari printer.
  Future<void> _batalkan(PrintEntry entry) async {
    final user = context.read<SessionProvider>().user;
    if (user == null || !user.isAdmin) return;

    final ok = await AppFeedback.confirm(
      context,
      title: 'Batalkan ${entry.tagNo}?',
      message: 'Tag ini belum keluar dari printer. Setelah dibatalkan, '
          'nomornya tidak bisa dipakai lagi dan tidak akan dicetak ulang.',
      confirmLabel: 'Batalkan tag',
      destructive: true,
    );
    if (!ok || !mounted) return;

    final riwayat = context.read<PrintHistoryProvider>();
    final berhasil = await riwayat.batalkan(
      entry,
      user,
      entry.errorMessage.isEmpty ? 'Tidak tercetak' : entry.errorMessage,
    );
    if (!mounted) return;

    if (berhasil) {
      AppFeedback.success(context, riwayat.message ?? 'Tag dibatalkan.');
    } else {
      AppFeedback.error(context, riwayat.error ?? 'Gagal membatalkan tag.');
    }
    riwayat.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    final cetak = context.watch<PrintHistoryProvider>();
    final counts = context.watch<CountProvider>();
    final admin = user?.isAdmin ?? false;

    final semua = BarisRiwayatSto.gabung(
      user: user,
      cetak: cetak.entries,
      hitung: counts.history,
    );
    final tampil = semua.where((b) => b.cocok(_saringan)).toList();
    final memuat = (cetak.loading || counts.loading) && semua.isEmpty;

    return Column(
      children: [
        Container(
          color: AppColors.primary,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: TextField(
            controller: _cari,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Cari nomor tag / part / material',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _cari.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _cari.clear();
                        _terapkanCari('');
                      },
                    ),
            ),
            onChanged: (nilai) => _debounce.run(() => _terapkanCari(nilai)),
            onSubmitted: _terapkanCari,
          ),
        ),
        _chips(user, semua),
        Expanded(
          child: memuat
              ? const Center(child: CircularProgressIndicator())
              : _daftar(tampil, cetak, admin),
        ),
      ],
    );
  }

  Widget _chips(AppUser? user, List<BarisRiwayatSto> semua) {
    final pilihan = SaringanSto.untuk(user);
    if (pilihan.length <= 1) return const SizedBox(height: 4);

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            for (final s in pilihan) ...[
              ChoiceChip(
                label: Text(
                  '${s.label} (${semua.where((b) => b.cocok(s)).length})',
                ),
                selected: _saringan == s,
                onSelected: (_) => setState(() => _saringan = s),
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _saringan == s
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                selectedColor: AppColors.primarySoft,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _daftar(
    List<BarisRiwayatSto> baris,
    PrintHistoryProvider cetak,
    bool admin,
  ) {
    final tertinggal = cetak.history.menunggu;

    if (baris.isEmpty) {
      return RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          children: [
            if (cetak.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _peringatan(cetak.error!),
              ),
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: _saringan == SaringanSto.semua
                  ? 'Belum ada riwayat tag STO'
                  : 'Tidak ada tag dengan keadaan "${_saringan.label}"',
              message: _saringan == SaringanSto.semua
                  ? 'Tag yang dicetak, dihitung, atau dibatalkan akan muncul '
                      'di sini beserta keadaannya.'
                  : 'Coba pilih Semua untuk melihat kejadian lain pada tag.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        // Dua sisipan di atas daftar: peringatan koneksi dan kartu tag
        // tertinggal - keduanya hanya muncul saat memang ada isinya.
        itemCount: baris.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return cetak.error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _peringatan(cetak.error!),
                  );
          }
          if (i == 1) {
            return tertinggal == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _kartuTertinggal(cetak),
                  );
          }

          final b = baris[i - 2];
          return b.cetak != null
              ? _barisCetak(b.cetak!, admin: admin)
              : _barisHitung(b.hitung!);
        },
      ),
    );
  }

  Widget _kartuTertinggal(PrintHistoryProvider riwayat) {
    final jumlah = riwayat.history.menunggu;
    return SectionCard(
      title: '$jumlah tag belum keluar dari printer',
      subtitle: 'Dicetak ulang otomatis saat printer normal; bila tetap '
          'tertinggal, admin bisa membatalkannya.',
      icon: Icons.warning_amber_rounded,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: riwayat.mencetak ? null : _cetakUlang,
          icon: riwayat.mencetak
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print, size: 18),
          label:
              Text(riwayat.mencetak ? 'Mencetak...' : 'Cetak ulang sekarang'),
        ),
      ),
    );
  }

  Widget _peringatan(String pesan) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pesan,
                style: const TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ),
          ],
        ),
      );

  // ------------------------------------------------------- baris cetak
  Widget _barisCetak(PrintEntry entry, {required bool admin}) {
    final (warna, latar, label) = switch (entry) {
      _ when entry.canceled => (
          AppColors.textSecondary,
          AppColors.border,
          'DIBATALKAN'
        ),
      // Pengajuan didahulukan dari keadaan cetak: yang perlu diketahui
      // operator lebih dulu adalah tag ini menunggu putusan admin.
      _ when entry.cancelDiajukan => (
          AppColors.navy,
          AppColors.navySoft,
          'DIAJUKAN BATAL'
        ),
      _ when entry.state == PrintState.printed => (
          AppColors.success,
          AppColors.successSoft,
          'TERCETAK'
        ),
      _ when entry.state == PrintState.error => (
          AppColors.danger,
          AppColors.dangerSoft,
          'GAGAL CETAK'
        ),
      _ => (AppColors.warning, AppColors.warningSoft, 'BELUM CETAK'),
    };

    final keterangan = (entry.canceled || entry.cancelDiajukan)
        ? entry.cancelReason
        : entry.errorMessage;

    // Waktu ditulis ringkas: jam saja bila hari ini. Tanggal lengkap di tiap
    // baris hanya memenuhi kartu tanpa menambah keterangan.
    final waktu = entry.printedAt == null
        ? 'dibuat ${Formatters.ringkas(entry.createdAt)}'
        : 'cetak ${Formatters.ringkas(entry.printedAt!)}';

    return _kartu(
      warna: warna,
      children: [
        _judul(entry.tagNo, label, warna, latar),
        const SizedBox(height: 3),
        Text(
          entry.partName.isEmpty ? '-' : entry.partName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (entry.partNumber.isNotEmpty) entry.partNumber,
            if (entry.area.isNotEmpty) entry.area,
            waktu,
          ].join('  -  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        if (keterangan.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: latar,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              entry.cancelDiajukan && entry.cancelRequestedBy.isNotEmpty
                  ? '$keterangan  -  diajukan ${entry.cancelRequestedBy}'
                  : keterangan,
              style: TextStyle(fontSize: 11, height: 1.35, color: warna),
            ),
          ),
        ],
        if (admin && entry.perluCetak) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _batalkan(entry),
              icon: const Icon(Icons.block, size: 15),
              label: const Text('Batalkan tag'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.dangerSoft),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------ baris hitung
  Widget _barisHitung(StoCount count) {
    return _kartu(
      warna: AppColors.success,
      children: [
        _judul(
          count.tagNo,
          '${count.qty} ${count.unit}',
          AppColors.success,
          AppColors.successSoft,
        ),
        const SizedBox(height: 3),
        Text(
          count.partName.isEmpty ? '-' : count.partName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (count.partNumber.isNotEmpty) count.partNumber,
            if (count.jobNumber.isNotEmpty) count.jobNumber,
          ].join('  -  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.groups_outlined,
                size: 13, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '${count.team} - ${count.nik}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.schedule, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              Formatters.relative(count.updatedAt ?? count.countedAt),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const Spacer(),
            StatusChip.sync(count.syncStatus),
          ],
        ),
        if (count.pernahDikoreksi)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Angka pernah dikoreksi pencatatnya.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.info,
              ),
            ),
          ),
      ],
    );
  }

  /// Kerangka kartu dengan pita warna di kiri - dipakai kedua jenis baris
  /// supaya daftar gabungannya terbaca sebagai satu daftar, bukan dua yang
  /// kebetulan bersebelahan.
  Widget _kartu({required Color warna, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: warna,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _judul(String tagNo, String label, Color warna, Color latar) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            tagNo,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: latar,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: warna,
            ),
          ),
        ),
      ],
    );
  }
}
