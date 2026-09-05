import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/debouncer.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/part_item.dart';
import '../../state/prepare_provider.dart';
import '../../state/session_provider.dart';

/// Pencarian Job / Part Number.
/// Sumber data: cache lokal (sqflite) supaya tetap cepat & bisa offline.
class PartSearchPage extends StatefulWidget {
  const PartSearchPage({super.key});

  @override
  State<PartSearchPage> createState() => _PartSearchPageState();
}

class _PartSearchPageState extends State<PartSearchPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PrepareProvider>();
      final user = context.read<SessionProvider>().user;
      // Daftar part dibatasi area yang diberikan admin ke user ini.
      if (user != null) provider.applyPermissions(user);
      provider.bootstrapSearch();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Pemicu lazy load saat mendekati 200px dari dasar list
    if (maxScroll - currentScroll <= 200) {
      context.read<PrepareProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debouncer.run(() {
      if (!mounted) return;
      context.read<PrepareProvider>().search(value);
    });
  }

  void _openPart(PartItem part) {
    context.read<PrepareProvider>().selectPart(part);
    Navigator.pushNamed(context, AppRoutes.prepare);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrepareProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari Job / Part Number'),
        actions: [
          IconButton(
            tooltip: 'Perbarui master part',
            onPressed: provider.searching ? null : provider.refreshMaster,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      // Hanya kotak cari dan hasilnya. Tiga pita keterangan sebelumnya
      // (batas hasil, keadaan cache, pencarian terakhir) memakan sepertiga
      // layar handheld tanpa membantu operator menemukan partnya.
      body: Column(
        children: [
          _searchBar(provider),
          _areaFilter(provider),
          Expanded(child: _results(provider)),
        ],
      ),
    );
  }

  Widget _searchBar(PrepareProvider provider) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        textCapitalization: TextCapitalization.characters,
        onChanged: _onChanged,
        onSubmitted: (value) => provider.search(value),
        decoration: InputDecoration(
          hintText: 'Ketik part number, job, atau nama part',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: provider.searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        provider.search('');
                        setState(() {});
                      },
                    ),
        ),
      ),
    );
  }

  /// Saringan area.
  ///
  /// Diminta lapangan: satu operator bisa dipercaya beberapa area, dan nomor
  /// part antar area bisa mirip. Tanpa saringan, part dari area lain ikut
  /// muncul di hasil pencarian dan tag terlanjur tercetak atas nama area yang
  /// salah - sedangkan nomor tag yang sudah dibuat tidak bisa ditarik kembali.
  ///
  /// Hanya ditampilkan bila memang ada pilihan: operator satu area tidak perlu
  /// diberi baris yang isinya cuma satu tombol.
  Widget _areaFilter(PrepareProvider provider) {
    final pilihan = provider.areaPilihan;
    if (pilihan.length < 2) return const SizedBox.shrink();

    Widget chip(String label, String nilai) {
      final terpilih = provider.areaFilter == nilai;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: terpilih,
          onSelected: (_) => provider.setAreaFilter(nilai),
          selectedColor: AppColors.primarySoft,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: terpilih ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Text(
              'Area',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chip('Semua', ''),
                  for (final area in pilihan) chip(area, area),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pemisah daftar area (dipakai di beberapa teks).
  static const String sep = ', ';

  Widget _results(PrepareProvider provider) {
    if (provider.searching && provider.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Part tidak ditemukan',
        message: provider.cacheInfo.isEmpty
            ? 'Master part belum ada di perangkat ini. Tekan tombol unduh di '
                'kanan atas untuk menariknya dari server - yang diunduh hanya '
                'area yang menjadi izin Anda.'
            : provider.areaFilter.isNotEmpty
                // Saringan area diperiksa lebih dulu: ini sebab yang paling
                // mungkin, dan satu-satunya yang bisa dibereskan operator
                // sendiri saat itu juga.
                ? 'Tidak ada part yang cocok di area ${provider.areaFilter}. '
                    'Pilih "Semua" di baris area untuk mencari di seluruh '
                    'area Anda.'
                : provider.allowedAreas.isEmpty
                    ? 'Coba kata kunci lain, misalnya sebagian nomor part '
                        'atau nama part.'
                    : 'Tidak ada part yang cocok di area Anda '
                        '(${provider.allowedAreas.join(sep)}). Minta admin '
                        'menambah area bila memang diperlukan.',
        actionLabel: 'Perbarui master part',
        onAction: provider.refreshMaster,
      );
    }

    final itemCount = provider.results.length + (provider.hasMore ? 1 : 0);

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= provider.results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        return _partTile(provider.results[index]);
      },
    );
  }

  Widget _partTile(PartItem part) {
    return InkWell(
      onTap: () => _openPart(part),
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
                    part.partNumber,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    part.jobNumber,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              part.partName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Area ditulis di tiap baris, bukan hanya di halaman
                // berikutnya: kalau operator memakai saringan "Semua",
                // inilah satu-satunya penanda part ini milik area mana.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.navySoft,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    part.area,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                _tag(Icons.factory_outlined, '${part.customer} / ${part.model}'),
                const SizedBox(width: 10),
                _tag(Icons.place_outlined, part.location),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
