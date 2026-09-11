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
import '../home/widgets/teks_berjalan.dart';

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

  bool get _isQtyInvalid {
    final teks = _qtyController.text.trim();
    if (teks.isEmpty) return true;
    final val = int.tryParse(teks);
    return val == null || val <= 0;
  }

  void _setQty(int value) {
    final clamped = value.clamp(1, AppConfig.maxTagPerBatch);
    final provider = context.read<PrepareProvider>();
    provider.setQty(clamped);
    _qtyController.text = '$clamped';
    _qtyController.selection =
        TextSelection.collapsed(offset: _qtyController.text.length);
    setState(() {});
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

    // Pengaman: Jumlah tag tidak boleh kosong, 0, atau negatif.
    if (_isQtyInvalid) {
      AppFeedback.error(
        context,
        'Total TAG kosong / 0 / negatif. Isi jumlah tag yang valid (minimal 1).',
      );
      return;
    }

    // Area part berbeda dari area yang sedang disaring operator - ditanya
    // lebih dulu, SEBELUM nomor tag diminta ke server.
    //
    // Operator yang dipercaya beberapa area mencari dengan saringan satu
    // area, lalu mengetuk part dari daftar "Semua" atau dari hasil sebelum
    // saringannya diganti. Tag yang terlanjur dibuat tidak bisa ditarik
    // kembali - satu-satunya jalan adalah pengajuan pembatalan ke admin.
    if (!await _areaSesuaiSaringan(provider)) return;

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
      // Pencetakan yang ditutup admin bukan kegagalan - disampaikan sebagai
      // keterangan, dan keadaan event langsung ditarik ulang supaya pita di
      // atas layar serta tombolnya ikut menyesuaikan tanpa operator harus
      // keluar-masuk menu.
      final ditutup = provider.cetakDitutup;
      if (ditutup != null) {
        provider.bersihkanCetakDitutup();
        await admin.refreshActiveEvent(pengakses: user);
        if (!mounted) return;
        AppFeedback.info(context, ditutup);
        return;
      }

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

  /// true bila boleh diteruskan: areanya memang sama, tidak ada saringan
  /// yang dipasang, atau operator sudah menegaskan bahwa ini disengaja.
  Future<bool> _areaSesuaiSaringan(PrepareProvider provider) async {
    final saringan = provider.areaFilter.trim().toUpperCase();
    final areaPart = (provider.selectedPart?.area ?? '').trim().toUpperCase();
    if (saringan.isEmpty || areaPart.isEmpty || saringan == areaPart) {
      return true;
    }

    final lanjut = await AppFeedback.confirm(
      context,
      title: 'Area part berbeda',
      message: 'Part ${provider.selectedPart?.partNumber} berada di area '
          '$areaPart, sedangkan saringan Anda $saringan. Tag akan dicetak '
          'atas nama area $areaPart dan nomornya tidak bisa ditarik kembali - '
          'pembatalan harus lewat pengajuan ke admin. Lanjutkan?',
      confirmLabel: 'Ya, cetak $areaPart',
      destructive: true,
    );
    return lanjut && mounted;
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

    final admin = context.watch<AdminProvider>();
    final activeEvent = admin.activeEvent;
    final eventDisorot = admin.eventDisorot;

    // Izin cetak dipegang event, terpisah dari status buka/tutupnya: menjelang
    // akhir pelaksanaan, admin menghentikan pencetakan tag baru sementara
    // hasil hitung masih terus masuk.
    final bolehCetak = activeEvent != null && activeEvent.bolehCetak;

    return Scaffold(
      appBar: AppBar(title: const Text('Persiapan Tag STO')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _eventBanner(eventDisorot),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            title: 'Jumlah tag yang dicetak',
            icon: Icons.numbers,
            child: Column(
              children: [
                Row(
                  children: [
                    _stepperButton(
                      Icons.remove,
                      (!_isQtyInvalid && provider.qty > 1)
                          ? () => _setQty(provider.qty - 1)
                          : null,
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
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                          decoration: InputDecoration(
                            errorText: _isQtyInvalid
                                ? 'Total TAG kosong / 0 / negatif'
                                : null,
                            errorStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onChanged: (value) {
                            final parsed = int.tryParse(value);
                            if (parsed != null) {
                              if (parsed > AppConfig.maxTagPerBatch) {
                                _qtyController.text =
                                    '${AppConfig.maxTagPerBatch}';
                                _qtyController.selection =
                                    TextSelection.collapsed(
                                  offset: _qtyController.text.length,
                                );
                                provider.setQty(AppConfig.maxTagPerBatch);
                              } else if (parsed > 0) {
                                provider.setQty(parsed);
                              }
                            }
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    _stepperButton(
                      Icons.add,
                      (!_isQtyInvalid && provider.qty < AppConfig.maxTagPerBatch)
                          ? () => _setQty(provider.qty + 1)
                          : () => _setQty(1),
                    ),
                  ],
                ),
                // Baris saran ikut hilang bila tidak ada angka yang tersisa -
                // batas satu batch bisa membuat semua saran tersaring habis.
                if (quickQty.isNotEmpty) const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: quickQty
                      .map(
                        (value) => ChoiceChip(
                          label: Text('$value tag'),
                          selected: !_isQtyInvalid && provider.qty == value,
                          onSelected: (_) => _setQty(value),
                          selectedColor: AppColors.primarySoft,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: (!_isQtyInvalid && provider.qty == value)
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          side: const BorderSide(color: AppColors.border),
                          backgroundColor: Colors.white,
                        ),
                      )
                      .toList(),
                ),
                // Batas ${AppConfig.maxTagPerBatch} tag per sesi tidak lagi
                // ditulis di sini: angkanya tetap dijaga PrepareProvider yang
                // menjepit nilainya, jadi operator tidak bisa melewatinya -
                // sebaris kalimat yang hanya benar sekali seumur pemakaian
                // tidak sebanding dengan tinggi yang dimakannya.
              ],
            ),
          ),
          // Kotak keterangan panjang di sini sudah dibuang. Isinya -
          // nomor tag hanya bisa dicetak sekali, pembatalan lewat
          // preview/riwayat - tetap muncul di halaman preview, tepat
          // sebelum tagnya benar-benar keluar. Di layar ini ia hanya
          // memakan tinggi dan mendorong tombol cetak ke bawah lipatan.
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
            onPressed: provider.generating ||
                    _menyiapkan ||
                    !bolehCetak ||
                    _isQtyInvalid
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
                  : _isQtyInvalid
                      ? 'JUMLAH TAG TIDAK VALID'
                      : bolehCetak
                          ? 'BUAT & CETAK ${provider.qty} TAG'
                          // Tombol mati tanpa keterangan selalu terbaca sebagai
                          // kerusakan. Sebabnya ditulis di tombolnya sendiri,
                          // bukan disembunyikan di pita atas layar.
                          : activeEvent == null
                              ? 'BELUM ADA EVENT BERJALAN'
                              : 'PENCETAKAN TAG SEDANG DITUTUP',
            ),
          ),
        ),
      ),
    );
  }

  /// Boleh cetak atau tidak - satu pertanyaan yang dijawab pita ini.
  ///
  /// Di beranda pita event menyebut nama, periode, dan jadwalnya. Di layar
  /// ini semua itu tidak menolong: operator sudah berdiri di depan rak dengan
  /// part di tangan, dan yang perlu ia tahu cuma apakah tombol cetaknya akan
  /// bekerja. Nama event-nya tetap disebut di ekor kalimat sebagai penunjuk
  /// kalau ternyata tidak boleh - itu yang ditanyakan admin saat ia melapor.
  Widget _eventBanner(StoEvent? event) {
    final (warna, latar, ikon, teks) = switch (event) {
      null => (
          AppColors.danger,
          AppColors.dangerSoft,
          Icons.block,
          'BELUM BOLEH CETAK - belum ada event STO yang berjalan. Minta admin '
              'membukanya lewat Setting > Event.',
        ),
      final StoEvent e => switch (e.jadwalPada(DateTime.now())) {
          JadwalEvent.berjalan when !e.bolehCetak => (
              AppColors.warning,
              AppColors.warningSoft,
              Icons.print_disabled,
              'BELUM BOLEH CETAK - pencetakan tag ditutup admin. Hasil hitung '
                  'tetap bisa dikirim.  (event ${e.name})',
            ),
          JadwalEvent.berjalan => (
              AppColors.success,
              AppColors.successSoft,
              Icons.print,
              'BOLEH CETAK  -  ${e.name}  -  ${e.areaLabel}',
            ),
          JadwalEvent.akanDatang => (
              AppColors.info,
              AppColors.navySoft,
              Icons.schedule,
              'BELUM BOLEH CETAK - event ${e.name} ${e.jadwalLabel().toLowerCase()} '
                  '(${e.periodLabel}).',
            ),
          JadwalEvent.terlewat => (
              AppColors.danger,
              AppColors.dangerSoft,
              Icons.history_toggle_off,
              'BELUM BOLEH CETAK - event ${e.name} ${e.jadwalLabel().toLowerCase()} '
                  '(${e.periodLabel}).',
            ),
        },
    };

    return Container(
      height: 34,
      margin: const EdgeInsets.only(bottom: 14),
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
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback? onTap) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        // 44 masih di atas ukuran sasaran sentuh yang dianjurkan (48 dp
        // termasuk jarak antarnya), jadi tetap nyaman ditekan bersarung
        // tangan sambil menghemat tinggi.
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: disabled
              ? AppColors.border.withValues(alpha: 0.3)
              : AppColors.navySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: disabled ? AppColors.textMuted : AppColors.navy,
          size: 22,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
