import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models/sto_tag.dart';
import '../../services/printer/bluetooth_settings.dart';
import '../../services/printer/printer_service.dart';
import '../../state/printer_provider.dart';
import '../../state/session_provider.dart';

/// Memilih printer internal MPOS 332 dan menguji hasil cetak.
class PrinterSetupPage extends StatefulWidget {
  const PrinterSetupPage({super.key});

  @override
  State<PrinterSetupPage> createState() => _PrinterSetupPageState();
}

class _PrinterSetupPageState extends State<PrinterSetupPage> {
  bool _testing = false;
  bool _mengujiJarak = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final printer = context.read<PrinterProvider>();
      final user = context.read<SessionProvider>().user;
      printer
        ..nikPembaca = user?.nik
        ..refreshDevices();
      // Setelan jarak milik bersama - ditarik ulang tiap halaman dibuka
      // supaya perubahan admin dari HT lain langsung berlaku di sini.
      printer.muatSetelanServer();
    });
  }

  /// Menyimpan setelan jarak ke server. Server yang menolak non-admin, tetapi
  /// tombolnya pun hanya ditampilkan untuk admin supaya tidak menjebak.
  Future<void> _simpanSetelan() async {
    final printer = context.read<PrinterProvider>();
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    setState(() => _menyimpanSetelan = true);
    try {
      await printer.simpanSetelanServer(user.nik);
      if (!mounted) return;
      AppFeedback.success(
        context,
        'Setelan printer disimpan di server - berlaku untuk semua handheld.',
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _menyimpanSetelan = false);
    }
  }

  bool _menyimpanSetelan = false;

  Future<void> _connect(PrinterDevice device) async {
    final printer = context.read<PrinterProvider>();
    final ok = await printer.connect(device);
    if (!mounted) return;
    if (ok) {
      AppFeedback.success(context, 'Tersambung ke ${device.name}.');
    } else {
      await _laporkanGagal(printer.error ?? 'Gagal menyambung.');
    }
  }

  /// Bluetooth yang mati punya jalan keluarnya sendiri: antar operator ke
  /// setelannya, jangan cuma menampilkan pesan gagal.
  Future<void> _laporkanGagal(String pesan) async {
    if (!pesan.toLowerCase().contains('bluetooth perangkat sedang mati')) {
      AppFeedback.error(context, pesan);
      return;
    }

    final buka = await AppFeedback.confirm(
      context,
      title: 'Bluetooth mati',
      message: pesan,
      confirmLabel: 'Buka setelan',
      cancelLabel: 'Nanti',
    );
    if (buka) await BluetoothSettings.buka();
  }

  /// Menguji jarak sobek tanpa mencetak tag utuh - operator bisa
  /// mengetuk berkali-kali sambil menyobek kertas, tanpa memboroskan
  /// kertas untuk seluruh isi tag.
  Future<void> _ujiJarak() async {
    final printer = context.read<PrinterProvider>();
    if (!printer.isConnected) {
      AppFeedback.error(context, 'Sambungkan printer terlebih dahulu.');
      return;
    }

    setState(() => _mengujiJarak = true);
    try {
      await printer.testFeed(printer.feedDots, gapDots: printer.gapDots);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _mengujiJarak = false);
    }
  }

  /// Cetak contoh tag (nomor TEST) untuk memastikan layout & kertas benar.
  /// Contoh ini tidak disimpan ke database sehingga tidak mengganggu nomor asli.
  Future<void> _testPrint() async {
    final printer = context.read<PrinterProvider>();
    final user = context.read<SessionProvider>().user;
    if (!printer.isConnected) {
      AppFeedback.error(context, 'Sambungkan printer terlebih dahulu.');
      return;
    }

    setState(() => _testing = true);
    try {
      final sample = StoTag(
        tagNo: 'TEST-000000',
        sequence: 0,
        batchId: 'TEST',
        partNumber: '53801-BZ010',
        jobNumber: 'JOB-TEST',
        partName: 'CONTOH CETAK TAG STO',
        customer: 'ADM',
        model: 'AYLA',
        area: 'WAREHOUSE 1',
        location: 'RAK A-01',
        createdBy: user?.nik ?? '-',
        createdAt: DateTime.now(),
        note: 'Contoh - bukan tag resmi',
      );
      await printer.printTag(sample);
      if (!mounted) return;
      AppFeedback.success(context, 'Contoh tag terkirim ke printer.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterProvider>();
    final user = context.watch<SessionProvider>().user;

    // Setelan printer berlaku untuk SEMUA handheld (tersimpan di server),
    // jadi hanya admin yang boleh masuk. Operator tidak kehilangan apa pun:
    // printer disambungkan sendiri sebelum mencetak.
    if (user == null || !user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Printer')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Khusus admin',
          message: 'Setelan printer berlaku untuk semua handheld, jadi hanya '
              'admin yang boleh mengubahnya. Printer tetap tersambung sendiri '
              'saat Anda mencetak.',
          actionLabel: 'Kembali',
          onAction: () => Navigator.pop(context),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer'),
        actions: [
          IconButton(
            tooltip: 'Cari ulang',
            onPressed: printer.busy ? null : printer.refreshDevices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SectionCard(
            title: 'Status',
            icon: Icons.info_outline,
            child: Row(
              children: [
                Icon(
                  printer.isConnected ? Icons.check_circle : Icons.error_outline,
                  color: printer.isConnected
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    printer.statusLabel,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (printer.isConnected)
                  TextButton(
                    onPressed: printer.disconnect,
                    child: const Text('Putuskan'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Printer terpasang (bonded)',
            subtitle:
                'Printer internal MPOS 332 biasanya bernama InnerPrinter / BluePrint',
            icon: Icons.bluetooth_searching,
            child: printer.busy && printer.devices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : printer.devices.isEmpty
                    ? EmptyState(
                        icon: Icons.print_disabled,
                        title: 'Printer tidak ditemukan',
                        message: printer.error ??
                            'Pastikan Bluetooth aktif dan printer internal sudah '
                                'ter-pairing di Setelan Android.',
                        actionLabel: 'Cari ulang',
                        onAction: printer.refreshDevices,
                      )
                    : Column(
                        children: printer.devices
                            .map((device) => _deviceTile(printer, device))
                            .toList(),
                      ),
          ),
          const SizedBox(height: 14),
          _jarakSobekCard(printer),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _testing || !printer.isConnected ? null : _testPrint,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long),
            label: Text(_testing ? 'Mencetak contoh...' : 'CETAK CONTOH TAG'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: printer.selected == null
                ? null
                : () async {
                    await printer.forgetPrinter();
                    if (!context.mounted) return;
                    AppFeedback.info(context, 'Printer tersimpan dilupakan.');
                  },
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Lupakan printer tersimpan'),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catatan MPOS 332',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Printer internal diakses sebagai perangkat Bluetooth ESC/POS. '
                  'Bila daftar kosong: aktifkan Bluetooth, pair printer internal '
                  'lewat Setelan Android, lalu tekan Cari ulang. Untuk perangkat '
                  'yang memakai SDK khusus, implementasi baru cukup ditambahkan '
                  'pada PrinterService tanpa mengubah halaman lain.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kalibrasi dot-ke-mm berbeda antar printer klon, jadi jarak sobeknya
  /// diatur di sini - bukan konstanta tetap - dan bisa diuji berkali-kali
  /// lewat [_ujiJarak] tanpa mencetak tag utuh.
  /// Dua jarak yang berbeda urusannya, jadi disetel terpisah.
  ///
  /// Kalibrasi dot-ke-mm berbeda antar printer klon, dan sebagian printer
  /// sudah memajukan kertasnya sendiri di akhir cetakan - karena itu nilainya
  /// diatur di sini, bukan dipatok di kode, dan bisa diuji berkali-kali tanpa
  /// mencetak tag utuh.
  Widget _jarakSobekCard(PrinterProvider printer) {
    // Setelan ini dipakai bersama, jadi hanya admin yang boleh mengubahnya -
    // operator yang menggeser slider di HT-nya sendiri hanya akan membuat
    // hasil cetak antar orang berbeda-beda.
    final admin = context.watch<SessionProvider>().user?.isAdmin ?? false;
    return SectionCard(
      title: 'Jarak kertas',
      subtitle: admin
          ? 'Berlaku untuk SEMUA handheld - atur lalu simpan ke server'
          : 'Diatur admin di server; di sini hanya bisa dilihat',
      icon: Icons.straighten,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sliderJarak(
            label: 'Antar tag (jarak gunting)',
            aktif: admin,
            dots: printer.gapDots,
            onChanged: printer.setGapDots,
          ),
          const SizedBox(height: 4),
          _sliderJarak(
            label: 'Tambahan di akhir cetakan',
            aktif: admin,
            dots: printer.feedDots,
            onChanged: printer.setFeedDots,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'Printer handheld ini sudah memajukan kertas sendiri saat '
              'cetakan berhenti. Isi 0 mm bila ekor tag terasa kepanjangan; '
              'naikkan hanya bila baris terakhir tidak lewat bibir sobek.',
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (admin)
                TextButton.icon(
                  onPressed: _menyimpanSetelan ? null : _simpanSetelan,
                  icon: _menyimpanSetelan
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: const Text('Simpan ke server'),
                ),
              TextButton.icon(
              onPressed: _mengujiJarak || !printer.isConnected
                  ? null
                  : _ujiJarak,
              icon: _mengujiJarak
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print, size: 16),
              label: const Text('Uji jarak ini'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sliderJarak({
    required String label,
    required int dots,
    required ValueChanged<int> onChanged,
    bool aktif = true,
  }) {
    // 8 titik = 1 mm. Yang benar-benar dijalankan printer adalah baris
    // kosong, jadi jumlah barisnya ikut ditampilkan supaya operator tahu
    // pembulatannya - printer ini mengabaikan perintah maju per titik.
    final mm = (dots / 8).toStringAsFixed(1);
    final baris = (dots / dotsPerLine).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label  -  $baris baris',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: dots.toDouble(),
                max: 120,
                divisions: 30,
                label: '$mm mm',
                onChanged: aktif ? (value) => onChanged(value.round()) : null,
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '$mm mm',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _deviceTile(PrinterProvider printer, PrinterDevice device) {
    final selected = printer.selected?.address == device.address;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        device.isBuiltIn ? Icons.print : Icons.bluetooth,
        color: device.isBuiltIn ? AppColors.primary : AppColors.navy,
      ),
      title: Text(device.name),
      subtitle: Text(
        '${device.address}${device.isBuiltIn ? '  -  printer internal' : ''}',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: selected && printer.isConnected
          ? const Icon(Icons.check_circle, color: AppColors.success)
          : TextButton(
              onPressed: printer.busy ? null : () => _connect(device),
              child: const Text('Sambungkan'),
            ),
      onTap: printer.busy ? null : () => _connect(device),
    );
  }
}
