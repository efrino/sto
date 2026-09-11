import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/tag_ok.dart';
import '../../state/session_provider.dart';
import '../../state/tag_ok_provider.dart';

/// Saringan keadaan Tag OK pada riwayat.
///
/// Keadaannya tidak berdiri di satu kolom - "siap dihitung" ada di
/// `scan_open`, sedangkan "dibatalkan" ada di `is_canceled` - jadi tiap
/// saringan menerjemahkan dirinya sendiri ke parameter server.
enum SaringanTagOk {
  semua('Semua', null, null),
  siap('Siap dihitung', true, 0),
  selesai('Sudah dihitung', false, 0),
  pengajuan('Pengajuan batal', null, 2),
  batal('Dibatalkan', null, 1);

  const SaringanTagOk(this.label, this.terbuka, this.kodeBatal);

  final String label;
  final bool? terbuka;
  final int? kodeBatal;
}

/// Riwayat Tag OK - satu tab pada halaman Riwayat.
///
/// Isinya diambil langsung dari server tiap kali saringan berubah; tidak ada
/// salinan lokal, karena satu tag OK dipindai bergantian oleh beberapa
/// handheld dan keadaan yang tersimpan di sini akan cepat menyesatkan.
class TagOkHistoryView extends StatefulWidget {
  const TagOkHistoryView({super.key});

  @override
  State<TagOkHistoryView> createState() => _TagOkHistoryViewState();
}

class _TagOkHistoryViewState extends State<TagOkHistoryView> {
  final _cari = TextEditingController();
  final _debouncer = Debouncer();
  SaringanTagOk _saringan = SaringanTagOk.semua;

  /// Penyegaran berkala.
  ///
  /// Satu Tag OK dipindai bergantian oleh beberapa handheld: yang menyiapkan
  /// belum tentu yang menghitung. Tanpa ini, daftar berhenti di keadaan saat
  /// layar dibuka dan operator tidak tahu rekannya sudah menutup tag.
  static const Duration _selangSegar = Duration(seconds: 12);
  Timer? _segar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
    _segar = Timer.periodic(_selangSegar, (_) => _segarkanDiam());
  }

  @override
  void dispose() {
    _segar?.cancel();
    _cari.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  /// Provider disimpan sejak dependensi terpasang - timer bisa berdenyut saat
  /// widget sudah dilepas dari pohon, dan `context.read` di saat itu melempar.
  SessionProvider? _sesi;
  TagOkProvider? _tagok;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sesi = context.read<SessionProvider>();
    _tagok = context.read<TagOkProvider>();
  }

  Future<void> _segarkanDiam() async {
    if (!mounted) return;
    final user = _sesi?.user;
    if (user == null) return;

    await _tagok?.segarkanRiwayat(
          user,
          terbuka: _saringan.terbuka,
          batal: _saringan.kodeBatal,
          keyword: _cari.text.trim(),
          hanyaMilikSaya: !user.isAdmin,
        );
  }

  Future<void> _muat() async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    await context.read<TagOkProvider>().muatRiwayat(
          user,
          terbuka: _saringan.terbuka,
          batal: _saringan.kodeBatal,
          keyword: _cari.text.trim(),
          // Admin melihat seluruh area; operator hanya tag yang ia sentuh,
          // sama seperti riwayat scan.
          hanyaMilikSaya: !user.isAdmin,
        );
  }

  @override
  Widget build(BuildContext context) {
    final tagok = context.watch<TagOkProvider>();

    return Column(
      children: [
        Container(
          color: AppColors.primary,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: TextField(
            controller: _cari,
            decoration: const InputDecoration(
              hintText: 'Cari nomor tag OK / part / job',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => _debouncer.run(() {
              if (mounted) _muat();
            }),
          ),
        ),
        _saringanChips(),
        Expanded(child: _list(tagok)),
      ],
    );
  }

  Widget _saringanChips() {
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            for (final s in SaringanTagOk.values) ...[
              ChoiceChip(
                label: Text(s.label),
                selected: _saringan == s,
                onSelected: (_) {
                  setState(() => _saringan = s);
                  _muat();
                },
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

  Widget _list(TagOkProvider tagok) {
    if (tagok.memuat && tagok.riwayat.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tagok.riwayat.isEmpty) {
      return EmptyState(
        icon: Icons.local_offer_outlined,
        title: 'Belum ada Tag OK',
        message: _saringan == SaringanTagOk.semua
            ? 'Tag OK yang disiapkan, dihitung, atau dibatalkan akan tampil '
                'di sini.'
            : 'Tidak ada Tag OK dengan keadaan "${_saringan.label}". Coba '
                'pilih Semua.',
      );
    }

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: tagok.riwayat.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final t = tagok.riwayat[i];
          return RepaintBoundary(
            key: ValueKey('tagok_${t.idTagOk}'),
            child: _tile(t),
          );
        },
      ),
    );
  }

  Widget _tile(TagOk tag) {
    final (warna, latar) = warnaKeadaan(tag);

    return InkWell(
      onTap: () => _detail(tag),
      borderRadius: BorderRadius.circular(14),
      child: Container(
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
                  tag.idTagOk,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: latar,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tag.keadaan,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: warna,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${tag.partNumber}  -  ${tag.area}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _jejak(tag),
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ------------------------------------------------------------ detail
  /// Rincian satu Tag OK, beserta jalan untuk mengoreksi hasil hitungnya.
  Future<void> _detail(TagOk tag) async {
    final user = context.read<SessionProvider>().user;

    // Aturannya sama dengan tag STO: yang mencatat angkanya yang boleh
    // mengubahnya. Admin ikut boleh, karena dialah yang membereskan selisih
    // ketika pencatatnya sudah pulang.
    final miliknya = user != null &&
        (user.isAdmin ||
            tag.scannedBy.trim().toUpperCase() == user.nik.toUpperCase());
    final bisaDiubah = tag.sudahDihitung && tag.bisaDiproses && miliknya;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tag.idTagOk,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Text(
                    tag.keadaan,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (tag.qtyScan != null)
                _rinci('Qty hitung', '${tag.qtyScan} pcs', tebal: true),
              if (tag.qtyKbn.trim().isNotEmpty)
                _rinci('Qty kanban', '${tag.qtyKbn} pcs'),
              if (tag.selisih != null && tag.selisih != 0)
                _rinci('Selisih', '${tag.selisih! > 0 ? '+' : ''}'
                    '${tag.selisih}'),
              _rinci('Part number', tag.partNumber),
              _rinci('Job number', tag.jobNumber),
              _rinci('Area', tag.area),
              if (tag.process.trim().isNotEmpty)
                _rinci('Proses', tag.process),
              if (tag.customer.trim().isNotEmpty)
                _rinci('Customer', tag.customer),
              if (tag.openedAt != null)
                _rinci('Disiapkan',
                    '${tag.openedBy} - ${Formatters.dateTime(tag.openedAt!)}'),
              if (tag.scannedAt != null)
                _rinci('Dihitung',
                    '${tag.scannedBy} - ${Formatters.dateTime(tag.scannedAt!)}'),
              if (tag.canceledAt != null)
                _rinci(tag.dibatalkan ? 'Dibatalkan' : 'Diajukan batal',
                    '${tag.namaPembatal} - '
                    '${Formatters.dateTime(tag.canceledAt!)}'),
              if (tag.cancelReason.trim().isNotEmpty)
                _rinci('Alasan', tag.cancelReason),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: bisaDiubah
                      ? () {
                          Navigator.pop(sheet);
                          _ubahQty(tag);
                        }
                      : null,
                  icon: const Icon(Icons.edit, size: 18),
                  label: Text(_labelUbah(tag, miliknya)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kenapa tombol koreksinya mati - supaya operator tidak menebak.
  static String _labelUbah(TagOk tag, bool miliknya) {
    if (!tag.bisaDiproses) return 'Tag sedang dalam pembatalan';
    if (!tag.sudahDihitung) return 'Belum ada angka untuk dikoreksi';
    if (!miliknya) {
      return 'Hanya ${tag.scannedBy} yang boleh mengubah';
    }
    return 'Ubah qty';
  }

  Widget _rinci(String nama, String isi, {bool tebal = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(
                nama,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                isi.trim().isEmpty ? '-' : isi,
                style: TextStyle(
                  fontSize: tebal ? 14.5 : 12.5,
                  fontWeight: tebal ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  /// Koreksi angka Tag OK - dikirim lewat endpoint hitung yang sama, jadi
  /// server tetap yang memutuskan boleh atau tidaknya.
  Future<void> _ubahQty(TagOk tag) async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final angka = await showDialog<int>(
      context: context,
      builder: (dialog) => _UbahQtyTagOkDialog(tag: tag),
    );

    if (angka == null || !mounted) return;

    final tagok = context.read<TagOkProvider>();
    final berhasil = await tagok.hitung(user, tag.idTagOk, angka);
    if (!mounted) return;

    if (berhasil) {
      AppFeedback.success(context, tagok.pesan ?? 'Qty diubah.');
      await _muat();
    } else {
      AppFeedback.error(context, tagok.error ?? 'Qty gagal diubah.');
    }
  }

  /// Jejak singkat siapa melakukan apa - itu yang dicari saat menelusuri
  /// selisih, bukan sekadar keadaan akhirnya.
  String _jejak(TagOk tag) {
    final baris = <String>[];

    if (tag.openedAt != null) {
      baris.add('Disiapkan ${tag.openedBy} - '
          '${Formatters.dateTime(tag.openedAt!)}');
    }
    if (tag.scannedAt != null) {
      final selisih = tag.selisih;
      final beda = (selisih == null || selisih == 0)
          ? ''
          : (selisih > 0 ? '  (+$selisih)' : '  ($selisih)');
      baris.add('Dihitung ${tag.scannedBy} - ${tag.qtyScan} pcs'
          '${tag.qtyKbn.isEmpty ? '' : ' dari ${tag.qtyKbn} kanban'}$beda');
    }
    if (tag.canceledAt != null) {
      baris.add('${tag.dibatalkan ? 'Dibatalkan' : 'Diajukan batal'} '
          '${tag.namaPembatal} - ${Formatters.dateTime(tag.canceledAt!)}'
          '${tag.cancelReason.isEmpty ? '' : '\n${tag.cancelReason}'}');
    }

    if (baris.isEmpty) return 'Belum ada aktivitas pada tag ini.';
    return baris.join('\n');
  }

  /// Warna keadaan - dipisah supaya bisa diuji tanpa membangun halaman.
  @visibleForTesting
  static (Color, Color) warnaKeadaan(TagOk tag) {
    if (tag.dibatalkan) return (AppColors.danger, AppColors.dangerSoft);
    if (tag.menungguKeputusan) {
      return (AppColors.warning, AppColors.warningSoft);
    }
    if (tag.sudahDihitung) return (AppColors.success, AppColors.successSoft);
    if (tag.terbuka) return (AppColors.navy, AppColors.navySoft);
    return (AppColors.textSecondary, AppColors.background);
  }
}

class _UbahQtyTagOkDialog extends StatefulWidget {
  const _UbahQtyTagOkDialog({required this.tag});
  final TagOk tag;

  @override
  State<_UbahQtyTagOkDialog> createState() => _UbahQtyTagOkDialogState();
}

class _UbahQtyTagOkDialogState extends State<_UbahQtyTagOkDialog> {
  late final TextEditingController _kolom;

  @override
  void initState() {
    super.initState();
    _kolom = TextEditingController(text: '${widget.tag.qtyScan ?? 0}');
  }

  @override
  void dispose() {
    _kolom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.tag;
    return AlertDialog(
      title: Text('Ubah qty ${tag.idTagOk}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tersimpan sekarang: ${tag.qtyScan} pcs (dicatat ${tag.scannedBy}).',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kolom,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Qty baru',
                suffixText: 'pcs',
              ),
              onSubmitted: (v) => Navigator.pop(context, int.tryParse(v.trim())),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(_kolom.text.trim())),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

