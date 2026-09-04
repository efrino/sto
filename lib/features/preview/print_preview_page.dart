import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/di/dependencies.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/sto_tag.dart';
import '../../state/cancel_provider.dart';
import '../../state/prepare_provider.dart';
import '../../state/print_history_provider.dart';
import '../../state/printer_provider.dart';
import '../../state/session_provider.dart';
import '../history/widgets/cancel_dialog.dart';
import 'widgets/label_paper.dart';

/// Preview hasil cetak sebelum tag benar-benar keluar dari printer.
///
/// Aturan yang dijaga halaman ini:
/// - operator melihat dulu tiap lembar (geser kiri/kanan),
/// - tag yang sudah tercetak tidak bisa dicetak lagi (tombol mati + watermark),
/// - salah part / mispart dibatalkan lewat tombol Batalkan, bukan cetak ulang.
class PrintPreviewPage extends StatefulWidget {
  const PrintPreviewPage({super.key});

  @override
  State<PrintPreviewPage> createState() => _PrintPreviewPageState();
}

class _PrintPreviewPageState extends State<PrintPreviewPage> {
  final _pageController = PageController(viewportFraction: 0.88);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Cetak otomatis begitu preview terbuka: setiap nomor tag yang dibuat
    // harus benar-benar keluar dari printer, tidak boleh ada nomor menggantung.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoPrint());
  }

  Future<void> _autoPrint() async {
    final provider = context.read<PrepareProvider>();
    if (provider.autoPrinted || provider.printing || provider.pendingCount == 0) {
      return;
    }
    provider.markAutoPrinted();
    await _printAll();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<bool> _ensurePrinterReady() async {
    final printer = context.read<PrinterProvider>();
    // Cari + sambungkan printer internal secara otomatis dulu.
    if (await printer.ensureReady()) return true;

    if (!mounted) return false;

    // Halaman pengaturan printer khusus admin, jadi operator tidak diarahkan
    // ke sana - itu hanya berujung layar "khusus admin".
    final admin = context.read<SessionProvider>().user?.isAdmin ?? false;
    if (!admin) {
      AppFeedback.error(
        context,
        printer.error ??
            'Printer belum siap. Pastikan Bluetooth menyala, lalu coba cetak '
            'lagi. Bila tetap gagal, minta admin memeriksanya lewat '
            'Setting > Printer.',
      );
      return false;
    }

    final goSetup = await AppFeedback.confirm(
      context,
      title: 'Printer belum siap',
      message: printer.error ??
          'Printer belum tersambung. Buka pengaturan printer untuk memilih '
              'printer internal MPOS 332.',
      confirmLabel: 'Buka pengaturan',
    );
    if (goSetup && mounted) {
      await Navigator.pushNamed(context, AppRoutes.printerSetup);
      if (!mounted) return false;
      return context.read<PrinterProvider>().isConnected;
    }
    return false;
  }

  Future<void> _printAll() async {
    final provider = context.read<PrepareProvider>();
    final user = context.read<SessionProvider>().user;
    if (user == null) return;
    if (!await _ensurePrinterReady() || !mounted) return;

    final printer = context.read<PrinterProvider>();
    final sound = context.read<AppDependencies>().sound;

    await provider.printAll(printer, user);
    if (!mounted) return;

    if (provider.printError != null) {
      await sound.error();
      if (!mounted) return;
      AppFeedback.error(context, provider.printError!);
      provider.clearPrintError();
    } else {
      await sound.success();
      if (!mounted) return;
      AppFeedback.success(
        context,
        '${provider.printedCount} tag berhasil dicetak.',
      );
    }

    await _periksaHasilCetak(provider);
    await _segarkanRiwayat();
  }

  /// Menarik ulang riwayat cetak dari server setelah satu sesi cetak selesai.
  ///
  /// Keadaan cetak dikirim lewat outbox (lihat PrepareProvider), jadi tanpa
  /// penarikan ulang ini angka di Riwayat masih memakai jawaban server yang
  /// lama - tag yang barusan dicetak tetap terlihat "belum tercetak".
  Future<void> _segarkanRiwayat() async {
    if (!mounted) return;
    final user = context.read<SessionProvider>().user;
    if (user == null) return;
    await context.read<PrintHistoryProvider>().load(user, limit: 200);
  }

  /// Memeriksa hasil cetak bersama operator, lalu mengantre yang janggal ke
  /// pengajuan pembatalan.
  ///
  /// Printer handheld menahan antrean saat kertas habis: byte-nya sudah masuk
  /// (aplikasi menganggap sukses) tetapi lembarannya baru keluar setelah
  /// kertas diganti - atau tidak keluar sama sekali. Tidak ada sinyal yang
  /// bisa dibaca aplikasi untuk itu, jadi mata operator yang jadi sensornya,
  /// dan hasilnya langsung dijadikan pengajuan batal supaya tag hantu tidak
  /// ikut terhitung saat STO.
  Future<void> _periksaHasilCetak(PrepareProvider provider) async {
    if (!mounted) return;

    final tercetak =
        provider.tags.where((t) => t.status == TagStatus.printed).toList();
    if (tercetak.isEmpty) return;

    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final janggal = await showModalBottomSheet<List<StoTag>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _CeklisHasilCetak(tags: tercetak),
    );

    if (janggal == null || janggal.isEmpty || !mounted) return;

    final cancels = context.read<CancelProvider>();
    var berhasil = 0;
    for (final tag in janggal) {
      final ok = await cancels.requestCancel(
        tag,
        'Tidak keluar / tidak terbaca saat cetak (kertas habis atau antrean '
        'printer tertahan)',
        user,
      );
      if (ok) berhasil++;
      if (!mounted) return;
    }
    cancels.clearMessage();

    if (!mounted) return;
    AppFeedback.info(
      context,
      berhasil == janggal.length
          ? '$berhasil tag masuk daftar pengajuan pembatalan. Admin yang '
              'menyetujuinya di menu Batal.'
          : '$berhasil dari ${janggal.length} tag berhasil diajukan. Sisanya '
              'coba lagi lewat menu Batal.',
    );
  }

  Future<void> _printOne(StoTag tag) async {
    final provider = context.read<PrepareProvider>();
    final user = context.read<SessionProvider>().user;
    if (user == null) return;
    if (!await _ensurePrinterReady() || !mounted) return;

    final printer = context.read<PrinterProvider>();
    final sound = context.read<AppDependencies>().sound;

    final ok = await provider.printOne(printer, user, tag);
    if (!mounted) return;

    if (ok) {
      await sound.success();
      if (!mounted) return;
      AppFeedback.success(context, 'Tag ${tag.tagNo} tercetak.');
    } else {
      await sound.error();
      if (!mounted) return;
      AppFeedback.error(
        context,
        provider.printError ?? 'Tag gagal dicetak.',
      );
      provider.clearPrintError();
    }
    await _segarkanRiwayat();
  }

  /// Pembatalan seluruh batch - hanya admin. Operator yang salah part
  /// mengajukan pembatalan lewat menu Scan Tag setelah kertasnya keluar.
  Future<void> _cancelBatch() async {
    final user = context.read<SessionProvider>().user;
    if (user == null || !user.isAdmin) return;

    final provider = context.read<PrepareProvider>();
    final reason = await CancelReasonDialog.show(
      context,
      title: 'Batalkan seluruh batch?',
      message:
          'Semua tag pada batch ini (termasuk yang sudah tercetak) akan '
          'ditandai DIBATALKAN. Kertas yang sudah keluar harus dimusnahkan.',
    );
    if (reason == null || !mounted) return;

    final ok = await provider.cancelBatch(reason, user);
    if (!mounted) return;
    AppFeedback.info(
      context,
      ok ? 'Batch dibatalkan.' : 'Gagal membatalkan batch.',
    );
  }

  Future<void> _finish() async {
    final provider = context.read<PrepareProvider>();
    if (provider.pendingCount > 0) {
      final ok = await AppFeedback.confirm(
        context,
        title: 'Keluar dari preview?',
        message:
            'Masih ada ${provider.pendingCount} tag yang belum dicetak. Tag '
            'tetap tersimpan dan bisa dicetak lewat menu Riwayat.',
        confirmLabel: 'Ya, keluar',
      );
      if (!ok || !mounted) return;
    }
    provider.resetAll();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrepareProvider>();
    final printer = context.watch<PrinterProvider>();
    final user = context.watch<SessionProvider>().user;
    final tags = provider.tags;

    if (tags.isEmpty || user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preview Cetak')),
        body: const Center(child: Text('Belum ada tag yang dibuat.')),
      );
    }

    final current = tags[_index.clamp(0, tags.length - 1)];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Preview Cetak'),
          actions: [
            if (user.isAdmin)
              IconButton(
                tooltip: 'Batalkan seluruh batch (admin)',
                onPressed: provider.printing ? null : _cancelBatch,
                icon: const Icon(Icons.playlist_remove),
              ),
          ],
        ),
        body: Column(
          children: [
            _summaryBar(provider, printer.statusLabel, printer.isConnected),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: tags.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  final tag = tags[index];
                  final printing =
                      provider.printing && provider.printingIndex == index;
                  return SingleChildScrollView(
                    // Padding bawah lega supaya baris terakhir kertas tidak
                    // mepet indikator halaman / tombol cetak.
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 28),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Tag ${index + 1} dari ${tags.length}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusChip.tag(tag.status, dense: true),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          // Isi kertas tetap terlihat selama mencetak - yang
                          // ditunggu operator adalah lembarannya, bukan
                          // spinner. Indikator prosesnya ditumpuk di atasnya.
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              LabelPaper(
                                document: context
                                    .read<PrinterProvider>()
                                    .buildDocument(tag),
                                watermark: _watermarkFor(tag.status),
                                watermarkColor: tag.status == TagStatus.printed
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                              if (printing) _printingBadge(tag),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _perTagActions(tag),
                      ],
                    ),
                  );
                },
              ),
            ),
            _dots(tags.length),
          ],
        ),
        bottomNavigationBar: _bottomBar(provider, current),
      ),
    );
  }

  String? _watermarkFor(TagStatus status) {
    switch (status) {
      case TagStatus.draft:
        return null;
      case TagStatus.printed:
        return 'SUDAH DICETAK';
      case TagStatus.pendingCancel:
        return 'DIAJUKAN BATAL';
      case TagStatus.cancelled:
        return 'DIBATALKAN';
    }
  }

  /// Penanda "sedang mencetak" yang ditumpuk di atas kertas, bukan
  /// menggantikannya.
  Widget _printingBadge(StoTag tag) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Mencetak ${tag.tagNo}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBar(
    PrepareProvider provider,
    String printerStatus,
    bool connected,
  ) {
    final batch = provider.batch;
    return Container(
      width: double.infinity,
      color: AppColors.navySoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${batch?.partNumber ?? '-'}  -  ${batch?.jobNumber ?? '-'}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${provider.printedCount} tercetak - ${provider.pendingCount} belum - '
            '${provider.cancelledCount} batal  -  ${provider.paperStatus.label}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.navy),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                connected ? Icons.print : Icons.print_disabled,
                size: 14,
                color: connected ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  printerStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: connected ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
              if (provider.offlineSequence)
                const Text(
                  'nomor offline',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Hanya muncul bila ada tag yang gagal keluar dari printer - operator
  /// tidak punya tombol batal di sini (pembatalan lewat persetujuan admin).
  Widget _perTagActions(StoTag tag) {
    final provider = context.watch<PrepareProvider>();
    if (!tag.isPrintable) {
      return Text(
        tag.status == TagStatus.printed
            ? 'Tag ini sudah keluar dari printer.'
            : 'Status tag: ${tag.status.label}',
        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      );
    }

    return Column(
      children: [
        const Text(
          'Tag ini belum keluar dari printer.',
          style: TextStyle(fontSize: 12.5, color: AppColors.warning),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: provider.printing ? null : () => _printOne(tag),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Cetak lembar ini'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ],
    );
  }

  Widget _dots(int count) {
    if (count <= 1) return const SizedBox(height: 12);
    final maxDots = count > 12 ? 12 : count;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(maxDots, (i) {
          final active = i == _index % maxDots;
          return Container(
            width: active ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  Widget _bottomBar(PrepareProvider provider, StoTag current) {
    final done = provider.allDone;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: provider.printing || done ? null : _printAll,
                icon: provider.printing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print),
                label: Text(
                  provider.printing
                      ? 'MENCETAK...'
                      : done
                          ? 'SEMUA SELESAI'
                          : 'ULANGI CETAK ${provider.pendingCount} TAG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: OutlinedButton(
                onPressed: provider.printing ? null : _finish,
                child: const Text('SELESAI'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ceklis "mana yang janggal" setelah satu batch dicetak.
///
/// Sengaja tidak bisa ditutup dengan menggeser: begitu terlewat, tag yang
/// tidak keluar akan diam-diam dianggap sah sampai hari perhitungan.
class _CeklisHasilCetak extends StatefulWidget {
  const _CeklisHasilCetak({required this.tags});

  final List<StoTag> tags;

  @override
  State<_CeklisHasilCetak> createState() => _CeklisHasilCetakState();
}

class _CeklisHasilCetakState extends State<_CeklisHasilCetak> {
  final Set<String> _janggal = {};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
          const Text(
            'Periksa hasil cetak',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cocokkan ${widget.tags.length} lembar di tangan Anda dengan daftar '
            'di bawah. Centang yang TIDAK keluar atau tidak terbaca - printer '
            'menahan antrean saat kertas habis, jadi tag bisa tercatat '
            'tercetak tanpa wujud.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.tags.length,
              itemBuilder: (context, index) {
                final tag = widget.tags[index];
                final ditandai = _janggal.contains(tag.tagNo);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: ditandai,
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _janggal.add(tag.tagNo);
                    } else {
                      _janggal.remove(tag.tagNo);
                    }
                  }),
                  title: Text(
                    tag.tagNo,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${tag.partNumber}  -  ${tag.jobNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, <StoTag>[]),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Semua baik'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _janggal.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            widget.tags
                                .where((t) => _janggal.contains(t.tagNo))
                                .toList(),
                          ),
                  icon: const Icon(Icons.outbox, size: 18),
                  label: Text('Ajukan batal (${_janggal.length})'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
