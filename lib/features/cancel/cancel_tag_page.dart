import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/di/dependencies.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/pengajuan_batal.dart';
import '../../data/models/sto_tag.dart';
import '../../state/cancel_provider.dart';
import '../../state/session_provider.dart';
import '../history/widgets/cancel_dialog.dart';
import '../scan/widgets/tag_scanner.dart';

/// Kotak menu "Batal Tag".
///
/// - Operator: scan tag (miliknya maupun cetakan orang lain) lalu mengajukan
///   pembatalan disertai alasan.
/// Tab PENGAJUAN hanya ada untuk admin: itu kotak masuk keputusan, bukan
/// daftar pantauan. Operator mengajukan lewat tab scan, lalu melihat hasilnya
/// di menu Riwayat.
///
/// - Admin: scan untuk membatalkan langsung, plus daftar pengajuan yang
///   menunggu keputusan.
class CancelTagPage extends StatefulWidget {
  const CancelTagPage({super.key});

  @override
  State<CancelTagPage> createState() => _CancelTagPageState();
}

class _CancelTagPageState extends State<CancelTagPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<TagScannerState> _scannerKey = GlobalKey<TagScannerState>();
  late final TabController _tabs;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Daftar pengajuan hanya dipakai admin - tidak perlu ditarik untuk
      // operator yang memang tidak punya tabnya.
      final user = context.read<SessionProvider>().user;
      if (user?.isAdmin ?? false) {
        context.read<CancelProvider>().load(admin: user);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String tagNo) async {
    if (_handling) return;
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    setState(() => _handling = true);
    final cancels = context.read<CancelProvider>();
    final deps = context.read<AppDependencies>();
    await deps.sound.beep();

    // Tag milik perangkat lain ikut diambil detailnya lebih dulu.
    final tag = await cancels.resolve(tagNo);
    if (!mounted) return;

    await _scannerKey.currentState?.pauseCamera();
    if (!mounted) return;

    if (tag == null) {
      await deps.sound.error();
      if (!mounted) return;
      AppFeedback.error(context, 'Tag $tagNo tidak ditemukan.');
    } else {
      await _showSheet(tag);
    }
    if (!mounted) return;

    await _scannerKey.currentState?.resumeCamera();
    if (!mounted) return;
    setState(() => _handling = false);
    _scannerKey.currentState?.armWedge();
  }

  Future<void> _showSheet(StoTag tag) {
    // Semua pembatalan - siapa pun yang scan, termasuk admin - masuk ke
    // daftar pengajuan dulu, supaya jejak persetujuannya selalu ada.
    final bisa = tag.canRequestCancel;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tag.tagNo,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                StatusChip.tag(tag.status),
              ],
            ),
            const SizedBox(height: 12),
            _row('Part / Job', '${tag.partNumber}  -  ${tag.jobNumber}'),
            _row('Nama', tag.partName),
            _row('Area', tag.area),
            _row('Dicetak oleh', tag.createdBy),
            if (tag.printedAt != null)
              _row('Waktu cetak', Formatters.dateTime(tag.printedAt!)),
            if (tag.isPendingCancel) ...[
              _row('Diajukan oleh', tag.cancelRequestedBy ?? '-'),
              _row('Alasan', tag.cancelReason ?? '-'),
            ],
            const SizedBox(height: 18),
            if (bisa)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _prosesPembatalan(tag);
                  },
                  icon: const Icon(Icons.outbox),
                  label: const Text('AJUKAN PEMBATALAN'),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _pesanStatus(tag),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Color(0xFF7A5312),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _pesanStatus(StoTag tag) {
    switch (tag.status) {
      case TagStatus.cancelled:
        return 'Tag ini sudah dibatalkan, tidak perlu tindakan lagi.';
      case TagStatus.pendingCancel:
        return 'Pembatalan tag ini sudah diajukan dan menunggu keputusan admin.';
      case TagStatus.draft:
        return 'Tag ini tercatat belum keluar dari printer.';
      case TagStatus.printed:
        return 'Tag ini tidak bisa diajukan pembatalannya.';
    }
  }

  Future<void> _prosesPembatalan(StoTag tag) async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final reason = await CancelReasonDialog.show(
      context,
      title: 'Ajukan pembatalan?',
      confirmLabel: 'Ajukan',
      message: user.isAdmin
          ? 'Pengajuan pembatalan ${tag.tagNo} masuk ke tab Pengajuan. '
              'Anda tinggal menyetujuinya di sana - alurnya sengaja sama '
              'untuk semua orang agar jejaknya lengkap.'
          : 'Pengajuan pembatalan ${tag.tagNo} dikirim ke admin. Tag tetap '
              'sah sampai admin menyetujui.',
    );
    if (reason == null || !mounted) return;

    final cancels = context.read<CancelProvider>();
    final ok = await cancels.requestCancel(tag, reason, user);
    if (!mounted) return;

    if (ok) {
      AppFeedback.success(context, cancels.message ?? 'Selesai.');
      // Operator tidak punya tab Pengajuan - tidak ada yang perlu dituju.
      if (user.isAdmin) _tabs.animateTo(1);
    } else {
      AppFeedback.error(context, cancels.message ?? 'Gagal memproses tag.');
    }
    cancels.clearMessage();
  }

  Future<void> _approve(PengajuanBatal pengajuan) async {
    final tag = pengajuan.tag;
    final user = context.read<SessionProvider>().user;
    if (user == null || !user.isAdmin) return;

    // Tag yang sudah dihitung punya akibat yang berbeda: angka hasil hitung
    // ikut hilang. Itu disebutkan di pertanyaannya, bukan hanya di kartu.
    final rincianTim = pengajuan.hitungan
        .map((h) => 'tim ${h.tim} ${h.nik}')
        .join(', ');

    final akibat = pengajuan.sudahDihitung
        ? '\n\nTag ini SUDAH DIHITUNG (${pengajuan.totalQty} pcs oleh '
            '$rincianTim). Angka itu ikut hilang dari perhitungan STO.'
        : pengajuan.sudahDicetak
            ? '\n\nLembarnya sudah tercetak - pastikan kertasnya ditarik '
                'dari lapangan supaya tidak ikut dihitung.'
            : '';

    final ok = await AppFeedback.confirm(
      context,
      title: 'Setujui pembatalan?',
      message: 'Tag ${tag.tagNo} akan dibatalkan. Alasan: '
          '${tag.cancelReason ?? '-'} (diajukan '
          '${tag.cancelRequestedBy ?? '-'}).$akibat',
      confirmLabel: 'Setujui',
      destructive: true,
    );
    if (!ok || !mounted) return;

    final cancels = context.read<CancelProvider>();
    await cancels.approve(tag, user);
    if (!mounted) return;
    AppFeedback.info(context, cancels.message ?? 'Selesai.');
    cancels.clearMessage();
  }

  Future<void> _reject(StoTag tag) async {
    final user = context.read<SessionProvider>().user;
    if (user == null || !user.isAdmin) return;

    final ok = await AppFeedback.confirm(
      context,
      title: 'Tolak pengajuan?',
      message: 'Tag ${tag.tagNo} kembali berstatus SUDAH CETAK dan tetap '
          'dihitung saat STO.',
      confirmLabel: 'Tolak',
    );
    if (!ok || !mounted) return;

    final cancels = context.read<CancelProvider>();
    await cancels.reject(tag, user);
    if (!mounted) return;
    AppFeedback.info(context, cancels.message ?? 'Selesai.');
    cancels.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    final admin = user?.isAdmin ?? false;
    final cancels = context.watch<CancelProvider>();

    final pemindai = TagScanner(
      key: _scannerKey,
      busy: _handling || cancels.busy,
      hint: 'Scan tag untuk diajukan pembatalannya',
      onCode: _handleCode,
    );

    // Kotak masuk keputusan hanya milik admin. Operator cukup mengajukan;
    // hasilnya dilihat di menu Riwayat, tempat keadaan tiap tag memang sudah
    // ditampilkan lengkap dengan alasannya.
    if (!admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Batal Tag')),
        body: Column(
          children: [
            _petunjukOperator(),
            Expanded(child: pemindai),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batal Tag'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'SCAN TAG'),
            Tab(
              text: cancels.pending.isEmpty
                  ? 'PENGAJUAN'
                  : 'PENGAJUAN (${cancels.pending.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          pemindai,
          _daftarPengajuan(cancels, admin),
        ],
      ),
    );
  }

  /// Menerangkan ke mana hasil pengajuan bisa dilihat, supaya operator tidak
  /// mencari-cari tab yang memang bukan haknya.
  Widget _petunjukOperator() => Container(
        width: double.infinity,
        color: AppColors.navySoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 15, color: AppColors.navy),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pengajuan diputuskan admin. Statusnya bisa dilihat di menu '
                'Riwayat.',
                style: TextStyle(fontSize: 11.5, color: AppColors.navy),
              ),
            ),
          ],
        ),
      );


  /// Jejak tag: sudah tercetak atau belum, dan sudah dihitung siapa.
  ///
  /// Ini yang membedakan keputusan pembatalan. Membatalkan tag yang BELUM
  /// tercetak hampir tanpa akibat; membatalkan tag yang SUDAH DIHITUNG berarti
  /// angka hasil hitung tim itu ikut hilang dari perhitungan STO - dan itu
  /// harus terlihat admin sebelum ia menekan Setujui.
  Widget _jejakTag(PengajuanBatal pengajuan) {
    final (warna, latar, ikon) = pengajuan.sudahDihitung
        ? (AppColors.danger, AppColors.dangerSoft, Icons.warning_amber_rounded)
        : pengajuan.sudahDicetak
            ? (AppColors.navy, AppColors.navySoft, Icons.print_outlined)
            : (AppColors.textSecondary, AppColors.border,
                Icons.print_disabled_outlined);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 15, color: warna),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pengajuan.ringkasan,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: warna,
                  ),
                ),
              ),
            ],
          ),
          if (pengajuan.dicetakPada != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 21),
              child: Text(
                'Dicetak ${Formatters.dateTime(pengajuan.dicetakPada!)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          for (final h in pengajuan.hitungan)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 21),
              child: Text(
                'Tim ${h.tim} - ${h.nik} - ${h.qty} pcs'
                '${h.waktu == null ? '' : ' - ${Formatters.dateTime(h.waktu!)}'}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: warna,
                ),
              ),
            ),
          if (pengajuan.sudahDihitung)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 21),
              child: Text(
                'Menyetujui berarti angka hasil hitung di atas ikut hilang '
                'dari perhitungan STO.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: AppColors.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _daftarPengajuan(CancelProvider cancels, bool admin) {
    if (cancels.loading && cancels.pending.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cancels.pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: cancels.load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 60),
            Icon(Icons.inbox_outlined, size: 48, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'Tidak ada pengajuan pembatalan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: cancels.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: cancels.pending.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final pengajuan = cancels.pending[index];
          final tag = pengajuan.tag;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tag.tagNo,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    StatusChip.tag(tag.status, dense: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${tag.partNumber}  -  ${tag.jobNumber}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Alasan: ${tag.cancelReason ?? '-'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Diajukan ${tag.cancelRequestedBy ?? '-'} - '
                  '${Formatters.relative(tag.cancelRequestedAt)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                _jejakTag(pengajuan),
                if (admin) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _reject(tag),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Tolak'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 42),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            minimumSize: const Size(0, 42),
                          ),
                          onPressed: () => _approve(pengajuan),
                          icon: const Icon(Icons.verified, size: 18),
                          label: const Text('Setujui'),
                        ),
                      ),
                    ],
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Menunggu keputusan admin.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: AppColors.info,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
