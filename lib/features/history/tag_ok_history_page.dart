import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/formatters.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  @override
  void dispose() {
    _cari.dispose();
    _debouncer.dispose();
    super.dispose();
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
        itemBuilder: (context, i) => _tile(tagok.riwayat[i]),
      ),
    );
  }

  Widget _tile(TagOk tag) {
    final (warna, latar) = warnaKeadaan(tag);

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
    );
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
          '${tag.canceledBy} - ${Formatters.dateTime(tag.canceledAt!)}'
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
