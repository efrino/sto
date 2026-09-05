import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/di/dependencies.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/scan_code.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models/tag_ok.dart';
import '../../state/session_provider.dart';
import '../../state/tag_ok_provider.dart';
import '../history/widgets/cancel_dialog.dart';
import '../scan/widgets/tag_scanner.dart';

/// Langkah yang dijalankan halaman Tag OK.
enum TagOkMode {
  siapkan('Siapkan Tag OK', 'Pindai Tag OK untuk disiapkan'),
  hitung('Scan Tag OK', 'Pindai Tag OK untuk dihitung'),
  batal('Batal Tag OK', 'Pindai Tag OK yang akan dibatalkan');

  const TagOkMode(this.judul, this.petunjuk);
  final String judul;
  final String petunjuk;
}

/// Tiga langkah Tag OK memakai satu halaman.
///
/// Alurnya sama - pindai, ambil datanya, lalu putuskan - hanya keputusannya
/// yang berbeda: [TagOkMode.siapkan] menandai tag siap dihitung,
/// [TagOkMode.hitung] mengisi qty fisiknya, dan [TagOkMode.batal] mengajukan
/// pembatalan. Menyatukannya membuat ketiga menu tidak mungkin berbeda
/// perilaku saat kode yang sama dipindai.
class TagOkPage extends StatefulWidget {
  const TagOkPage({super.key, required this.mode});

  final TagOkMode mode;

  @override
  State<TagOkPage> createState() => _TagOkPageState();
}

class _TagOkPageState extends State<TagOkPage> {
  final GlobalKey<TagScannerState> _scannerKey = GlobalKey<TagScannerState>();
  final _qty = TextEditingController();
  bool _menangani = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pindai(String kode) async {
    if (_menangani) return;
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    setState(() => _menangani = true);
    final tagok = context.read<TagOkProvider>();
    final sound = context.read<AppDependencies>().sound;

    try {
      final tag = await tagok.cari(
        user,
        kode,
        bolehDariProduksi: widget.mode == TagOkMode.siapkan,
      );
      if (!mounted) return;

      if (tag == null) {
        await sound.error();
        if (!mounted) return;
        AppFeedback.error(context, tagok.error ?? 'Tag OK tidak ditemukan.');
        tagok.bersihkanPesan();
        return;
      }

      // Qty kanban jadi angka awal - penghitung tinggal mengubahnya bila
      // isinya ternyata berbeda, dan itu justru selisih yang dicari saat STO.
      _qty.text = '${tag.qtyScan ?? tag.kanban ?? ''}';
      await sound.success();
    } finally {
      if (mounted) setState(() => _menangani = false);
    }
  }

  Future<void> _setujui(TagOk tag) async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final tagok = context.read<TagOkProvider>();
    final ok = await tagok.siapkan(user, tag.idTagOk);
    if (!mounted) return;

    if (ok) {
      AppFeedback.success(context, tagok.pesan ?? 'Tersimpan.');
      _lanjutTagBerikutnya();
    } else {
      AppFeedback.error(context, tagok.error ?? 'Gagal menyiapkan tag OK.');
    }
    tagok.bersihkanPesan();
  }

  Future<void> _simpanQty(TagOk tag) async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final qty = int.tryParse(_qty.text.trim());
    if (qty == null || qty < 0) {
      AppFeedback.error(context, 'Isi qty hasil hitung lebih dulu.');
      return;
    }

    final tagok = context.read<TagOkProvider>();
    final ok = await tagok.hitung(user, tag.idTagOk, qty);
    if (!mounted) return;

    if (ok) {
      AppFeedback.success(context, tagok.pesan ?? 'Tersimpan.');
      _lanjutTagBerikutnya();
    } else {
      AppFeedback.error(context, tagok.error ?? 'Gagal menyimpan hasil hitung.');
    }
    tagok.bersihkanPesan();
  }

  /// Membersihkan layar untuk tag berikutnya - operator memindai berturut-turut
  /// dan tidak perlu menekan apa pun di antaranya.
  void _lanjutTagBerikutnya() {
    context.read<TagOkProvider>().lepas();
    _qty.clear();
    // Pemindai dihidupkan lagi agar tag berikutnya langsung terbaca.
    _scannerKey.currentState?.armWedge();
  }

  @override
  Widget build(BuildContext context) {
    final tagok = context.watch<TagOkProvider>();
    final tag = tagok.tag;

    return Scaffold(
      appBar: AppBar(title: Text(widget.mode.judul)),
      body: Column(
        children: [
          Expanded(
            child: tag == null
                ? TagScanner(
                    key: _scannerKey,
                    busy: _menangani || tagok.sibuk,
                    hint: widget.mode.petunjuk,
                    // Tag OK dicetak sebagai barcode biasa, bukan QR.
                    formats: const [
                      BarcodeFormat.qrCode,
                      BarcodeFormat.code128,
                      BarcodeFormat.code39,
                      BarcodeFormat.ean13,
                    ],
                    normalisasi: ScanCode.extractTagOk,
                    onCode: _pindai,
                  )
                : _detail(tag, tagok),
          ),
          // Tombol keputusan ditempel di bawah layar, di luar daftar yang
          // menggulir. Sebelumnya ia ikut menggulir di bawah kartu detail -
          // di layar handheld yang pendek tombolnya jatuh di luar pandangan,
          // dan operator mengira memindai saja sudah menyiapkan tagnya.
          if (tag != null) _bilahAksi(tag, tagok),
        ],
      ),
    );
  }

  /// Bilah aksi tetap di dasar layar.
  Widget _bilahAksi(TagOk tag, TagOkProvider tagok) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _aksi(tag, tagok),
            TextButton.icon(
              onPressed: tagok.sibuk ? null : _lanjutTagBerikutnya,
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Pindai tag lain'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(TagOk tag, TagOkProvider tagok) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        SectionCard(
          title: tag.idTagOk,
          subtitle: '${tag.partNumber}  -  ${tag.jobNumber}',
          icon: Icons.local_offer_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _keadaan(tag),
              const SizedBox(height: 10),
              _baris('Area', tag.area),
              if (tag.process.isNotEmpty) _baris('Proses', tag.process),
              if (tag.line.isNotEmpty) _baris('Line', tag.line),
              if (tag.shift != null) _baris('Shift', '${tag.shift}'),
              if (tag.customer.isNotEmpty) _baris('Customer', tag.customer),
              if (tag.status.isNotEmpty) _baris('Status', tag.status),
              _baris('Qty kanban', tag.qtyKbn.isEmpty ? '-' : tag.qtyKbn),
              if (tag.openedAt != null)
                _baris(
                  'Disiapkan',
                  '${tag.openedBy} - ${Formatters.dateTime(tag.openedAt!)}',
                ),
              if (tag.canceledAt != null)
                _baris(
                  tag.dibatalkan ? 'Dibatalkan' : 'Diajukan batal',
                  '${tag.canceledBy} - ${Formatters.dateTime(tag.canceledAt!)}'
                  '${tag.cancelReason.isEmpty ? '' : ' - ${tag.cancelReason}'}',
                ),
              if (tag.scannedAt != null)
                _baris(
                  'Dihitung',
                  '${tag.scannedBy} - ${tag.qtyScan} pcs - '
                      '${Formatters.dateTime(tag.scannedAt!)}',
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Aksi yang tersedia untuk tag ini pada mode yang sedang dibuka.
  ///
  /// Tag batal - dan yang sedang diajukan batal - berhenti lebih dulu di sini:
  /// server menolaknya, jadi menampilkan tombolnya hanya menunda penolakan.
  Widget _aksi(TagOk tag, TagOkProvider tagok) {
    if (widget.mode != TagOkMode.batal && !tag.bisaDiproses) {
      return _catatan(
        tag.dibatalkan
            ? 'Tag OK ini sudah dibatalkan oleh ${tag.canceledBy}'
                '${tag.cancelReason.isEmpty ? '' : ' - ${tag.cancelReason}'}.'
            : 'Tag OK ini sedang diajukan batal oleh ${tag.canceledBy}, '
                'menunggu keputusan admin.',
        AppColors.danger,
        AppColors.dangerSoft,
      );
    }

    switch (widget.mode) {
      case TagOkMode.siapkan:
        return _aksiSiapkan(tag, tagok);
      case TagOkMode.hitung:
        return _aksiHitung(tag, tagok);
      case TagOkMode.batal:
        return _aksiBatal(tag, tagok);
    }
  }

  Widget _aksiBatal(TagOk tag, TagOkProvider tagok) {
    final admin = context.read<SessionProvider>().user?.isAdmin ?? false;

    if (tag.dibatalkan) {
      return _catatan(
        'Tag OK ini sudah dibatalkan oleh ${tag.canceledBy}'
        '${tag.cancelReason.isEmpty ? '' : ' - ${tag.cancelReason}'}.',
        AppColors.danger,
        AppColors.dangerSoft,
      );
    }

    if (tag.menungguKeputusan) {
      if (!admin) {
        return _catatan(
          'Pengajuan batal dari ${tag.canceledBy} sedang menunggu keputusan '
          'admin${tag.cancelReason.isEmpty ? '' : ' - ${tag.cancelReason}'}.',
          AppColors.warning,
          AppColors.warningSoft,
        );
      }
      // Keputusan admin: dua tombol berdampingan dan sama besar, supaya
      // "batalkan" tidak terbaca sebagai jalan yang dianjurkan.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _catatan(
            'Diajukan ${tag.canceledBy}'
            '${tag.cancelReason.isEmpty ? '' : ' - ${tag.cancelReason}'}',
            AppColors.warning,
            AppColors.warningSoft,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: tagok.sibuk ? null : () => _putuskan(tag, false),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Tolak'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: tagok.sibuk ? null : () => _putuskan(tag, true),
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Batalkan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: tagok.sibuk ? null : () => _ajukanBatal(tag),
      icon: const Icon(Icons.block),
      label: const Text('Ajukan pembatalan'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.danger,
        minimumSize: const Size.fromHeight(52),
      ),
    );
  }

  Future<void> _ajukanBatal(TagOk tag) async {
    final alasan = await CancelReasonDialog.show(
      context,
      title: 'Ajukan batal Tag OK',
      message: 'Tag ${tag.idTagOk} - ${tag.partNumber}',
      confirmLabel: 'Ajukan',
    );
    if (alasan == null || !mounted) return;

    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final tagok = context.read<TagOkProvider>();
    final ok = await tagok.ajukanBatal(user, tag.idTagOk, alasan);
    if (!mounted) return;

    if (ok) {
      AppFeedback.success(context, tagok.pesan ?? 'Pengajuan terkirim.');
      _lanjutTagBerikutnya();
    } else {
      AppFeedback.error(context, tagok.error ?? 'Gagal mengajukan pembatalan.');
    }
    tagok.bersihkanPesan();
  }

  Future<void> _putuskan(TagOk tag, bool setuju) async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    if (setuju) {
      final yakin = await AppFeedback.confirm(
        context,
        title: 'Batalkan Tag OK?',
        message: 'Tag ${tag.idTagOk} tidak bisa disiapkan atau dihitung lagi '
            'setelah dibatalkan.',
        confirmLabel: 'Batalkan',
        destructive: true,
      );
      if (!yakin || !mounted) return;
    }

    final tagok = context.read<TagOkProvider>();
    final ok = await tagok.putuskanBatal(user, tag.idTagOk, setuju);
    if (!mounted) return;

    if (ok) {
      AppFeedback.success(context, tagok.pesan ?? 'Keputusan tersimpan.');
      _lanjutTagBerikutnya();
    } else {
      AppFeedback.error(context, tagok.error ?? 'Gagal menyimpan keputusan.');
    }
    tagok.bersihkanPesan();
  }

  Widget _keadaan(TagOk tag) {
    final (warna, latar) = tag.dibatalkan
        ? (AppColors.danger, AppColors.dangerSoft)
        : tag.menungguKeputusan
            ? (AppColors.warning, AppColors.warningSoft)
            : tag.sudahDihitung
                ? (AppColors.success, AppColors.successSoft)
                : tag.terbuka
                    ? (AppColors.navy, AppColors.navySoft)
                    : (AppColors.warning, AppColors.warningSoft);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tag.keadaan,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: warna,
        ),
      ),
    );
  }

  Widget _aksiSiapkan(TagOk tag, TagOkProvider tagok) {
    if (tag.sudahDihitung) {
      return _catatan(
        'Tag ini sudah dihitung ${tag.qtyScan} pcs oleh ${tag.scannedBy}. '
        'Tidak perlu disiapkan lagi.',
        AppColors.success,
        AppColors.successSoft,
      );
    }

    return FilledButton.icon(
      onPressed: tagok.sibuk ? null : () => _setujui(tag),
      icon: const Icon(Icons.check_circle_outline),
      label: Text(tag.terbuka ? 'Setujui ulang' : 'Setujui - siap dihitung'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }

  Widget _aksiHitung(TagOk tag, TagOkProvider tagok) {
    if (tag.sudahDihitung) {
      return _catatan(
        'Tag ini sudah dihitung ${tag.qtyScan} pcs oleh ${tag.scannedBy}. '
        'Hitungan ganda tidak diterima server.',
        AppColors.success,
        AppColors.successSoft,
      );
    }
    if (!tag.terbuka) {
      return _catatan(
        'Tag ini belum disiapkan. Minta petugas membukanya lewat menu '
        'Siapkan Tag OK lebih dulu.',
        AppColors.warning,
        AppColors.warningSoft,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Qty hasil hitung fisik',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _qty,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            hintText: tag.qtyKbn.isEmpty ? '0' : tag.qtyKbn,
            suffixText: 'pcs',
          ),
          onChanged: (_) => setState(() {}),
        ),
        _selisih(tag),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: tagok.sibuk ? null : () => _simpanQty(tag),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Simpan hasil hitung'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }

  /// Selisih terhadap qty kanban ditampilkan saat mengetik - itulah angka yang
  /// dicari saat STO, dan lebih baik terlihat sebelum disimpan.
  Widget _selisih(TagOk tag) {
    final kanban = tag.kanban;
    final diisi = int.tryParse(_qty.text.trim());
    if (kanban == null || diisi == null || diisi == kanban) {
      return const SizedBox.shrink();
    }

    final beda = diisi - kanban;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        beda > 0
            ? 'Lebih $beda pcs dari kanban ($kanban)'
            : 'Kurang ${beda.abs()} pcs dari kanban ($kanban)',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.warning,
        ),
      ),
    );
  }

  Widget _catatan(String teks, Color warna, Color latar) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: latar,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          teks,
          style: TextStyle(fontSize: 12, height: 1.4, color: warna),
        ),
      );

  Widget _baris(String label, String nilai) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                nilai,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
