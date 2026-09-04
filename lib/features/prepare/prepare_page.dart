import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models/sto_event.dart';
import '../../state/admin_provider.dart';
import '../../state/prepare_provider.dart';
import '../../state/session_provider.dart';
import '../../state/settings_provider.dart';

/// Menentukan berapa TAG (nomor unik) yang akan dicetak untuk part terpilih.
/// Penting: jumlah di sini bukan jumlah copy - tiap lembar punya nomor sendiri.
class PreparePage extends StatefulWidget {
  const PreparePage({super.key});

  @override
  State<PreparePage> createState() => _PreparePageState();
}

class _PreparePageState extends State<PreparePage> {
  final _qtyController = TextEditingController(
    text: '${AppConfig.defaultTagPerBatch}',
  );

  @override
  void initState() {
    super.initState();
    // Area tag mengikuti area part; bila admin mengisi area default di menu
    // Setting, nilai itu yang dipakai.
    final provider = context.read<PrepareProvider>();
    final defaultArea = context.read<SettingsProvider>().defaultArea;
    if (defaultArea.isNotEmpty) provider.setAreaOverride(defaultArea);

    // Event berjalan ditarik begitu halaman dibuka, supaya operator langsung
    // melihat event yang dipakai - bukan baru tahu saat tombol ditekan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<SessionProvider>().user;
      if (user == null) return;
      context.read<AdminProvider>().refreshActiveEvent(pengakses: user);
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _setQty(int value) {
    final provider = context.read<PrepareProvider>();
    provider.setQty(value);
    _qtyController.text = '${provider.qty}';
    _qtyController.selection =
        TextSelection.collapsed(offset: _qtyController.text.length);
  }

  /// Penanda sibuk milik layar - menyala SEBELUM `await` pertama.
  ///
  /// `provider.generating` saja tidak cukup: pembuatan tag didahului
  /// penyegaran event ke server, dan selama itu tombolnya masih hidup. Satu
  /// ketukan tambahan di jeda itu membuat batch kedua di server.
  bool _menyiapkan = false;

  Future<void> _generate() async {
    if (_menyiapkan) return;
    setState(() => _menyiapkan = true);
    try {
      await _jalankanGenerate();
    } finally {
      if (mounted) setState(() => _menyiapkan = false);
    }
  }

  Future<void> _jalankanGenerate() async {
    final provider = context.read<PrepareProvider>();
    final admin = context.read<AdminProvider>();
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    // Tag hanya boleh dibuat saat ada event STO yang sedang berjalan.
    final event = await admin.refreshActiveEvent(pengakses: user);
    if (!mounted) return;
    if (event == null) {
      AppFeedback.error(
        context,
        'Belum ada event STO yang aktif hari ini. Minta admin membukanya '
        'lewat menu Setting > Event STO.',
      );
      return;
    }

    final area = provider.areaOverride.trim().isEmpty
        ? (provider.selectedPart?.area ?? '')
        : provider.areaOverride.trim();
    if (area.isNotEmpty && !event.coversArea(area)) {
      AppFeedback.error(
        context,
        'Area $area tidak termasuk dalam event ${event.name} '
        '(${event.areaLabel}).',
      );
      return;
    }

    final ok = await provider.generate(user, eventId: event.id);
    if (!mounted) return;

    if (!ok) {
      AppFeedback.error(context, provider.error ?? 'Gagal membuat tag.');
      return;
    }
    if (provider.offlineSequence) {
      AppFeedback.info(
        context,
        'Server tidak terjangkau - nomor tag memakai urutan lokal (awalan L).',
      );
    }
    Navigator.pushNamed(context, AppRoutes.preview);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrepareProvider>();
    final part = provider.selectedPart;

    if (part == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Persiapan Tag')),
        body: const Center(child: Text('Belum ada part yang dipilih.')),
      );
    }

    // Saran 1 dan 5 dibuang: batas satu batch cuma
    // [AppConfig.maxTagPerBatch] lembar, jadi angka sekecil itu lebih cepat
    // diatur lewat tombol +/- daripada memenuhi baris saran.
    final quickQty = <int>{10, if (part.stdPack > 0) part.stdPack}
        .where((e) => e <= AppConfig.maxTagPerBatch)
        .toList()
      ..sort();

    final event = context.watch<AdminProvider>().activeEvent;

    return Scaffold(
      appBar: AppBar(title: const Text('Persiapan Tag STO')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _eventBanner(event),
          SectionCard(
            title: 'Part terpilih',
            icon: Icons.inventory_2_outlined,
            trailing: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ganti'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  part.partNumber,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  part.partName,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _detailRow('Job Number', part.jobNumber),
                _detailRow('Customer / Model', '${part.customer} / ${part.model}'),
                _detailRow('Area', part.area),
                _detailRow('Status', part.partType),
                _detailRow('Lokasi', part.location),
                if (part.stdPack > 0)
                  _detailRow('Std. Packing', '${part.stdPack} ${part.unit}'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Jumlah tag yang dicetak',
            subtitle: 'Setiap tag mendapat nomor unik (bukan salinan)',
            icon: Icons.numbers,
            child: Column(
              children: [
                Row(
                  children: [
                    _stepperButton(
                      Icons.remove,
                      () => _setQty(provider.qty - 1),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _qtyController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                          onChanged: (value) {
                            final parsed = int.tryParse(value);
                            if (parsed != null) provider.setQty(parsed);
                          },
                        ),
                      ),
                    ),
                    _stepperButton(Icons.add, () => _setQty(provider.qty + 1)),
                  ],
                ),
                // Baris saran ikut hilang bila tidak ada angka yang tersisa -
                // batas satu batch bisa membuat semua saran tersaring habis.
                if (quickQty.isNotEmpty) const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: quickQty
                      .map(
                        (value) => ChoiceChip(
                          label: Text('$value tag'),
                          selected: provider.qty == value,
                          onSelected: (_) => _setQty(value),
                          selectedColor: AppColors.primarySoft,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: provider.qty == value
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          side: const BorderSide(color: AppColors.border),
                          backgroundColor: Colors.white,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Maksimal ${AppConfig.maxTagPerBatch} tag per sesi.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nomor tag diambil dari server dan hanya bisa dicetak satu '
                    'kali. Bila salah part, gunakan tombol Batalkan di halaman '
                    'preview atau riwayat - jangan mencetak ulang.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: Color(0xFF7A5312),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
            onPressed: provider.generating || _menyiapkan || event == null
                ? null
                : _generate,
            icon: provider.generating || _menyiapkan
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.preview),
            label: Text(
              provider.generating || _menyiapkan
                  ? 'Membuat nomor tag...'
                  : 'BUAT & CETAK ${provider.qty} TAG',
            ),
          ),
        ),
      ),
    );
  }

  /// Status event STO yang sedang berjalan - penentu boleh/tidaknya
  /// membuat tag hari ini.
  Widget _eventBanner(StoEvent? event) {
    final aktif = event != null;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: aktif ? AppColors.successSoft : AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            aktif ? Icons.event_available : Icons.event_busy,
            size: 18,
            color: aktif ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              aktif
                  ? 'Event: ${event.name}  (${event.periodLabel})'
                  : 'Belum ada event STO aktif - tag tidak bisa dibuat. '
                      'Minta admin membukanya di menu Setting.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: aktif ? const Color(0xFF0E5C39) : AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.navySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.navy, size: 26),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
