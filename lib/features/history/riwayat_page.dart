import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/empty_state.dart';
import '../../data/models/app_user.dart';
import '../../state/session_provider.dart';
import 'sto_history_page.dart';
import 'tag_ok_history_page.dart';

/// Satu isi riwayat beserta identitasnya di tab bar.
class RiwayatTab {
  const RiwayatTab({
    required this.label,
    required this.icon,
    required this.judul,
    required this.isi,
    this.aksi = const [],
  });

  /// Teks pendek pada tab.
  final String label;
  final IconData icon;

  /// Judul AppBar saat isi ini berdiri sendiri (tanpa tab).
  final String judul;
  final Widget isi;

  /// Tombol AppBar yang hanya masuk akal untuk isi ini.
  final List<Widget> aksi;
}

/// Riwayat yang menyesuaikan hak akses user.
///
/// Isinya mengikuti izin yang diberikan admin, bukan peran: satu izin berarti
/// satu isi langsung tampil tanpa tab, dua izin berarti dua tab. Operator yang
/// cuma memegang "prepare" tidak perlu melihat tab scan yang tidak bisa ia
/// pakai, dan sebaliknya.
class RiwayatPage extends StatelessWidget {
  const RiwayatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    final daftar = tabsUntuk(user);

    if (daftar.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Riwayat')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Tidak ada riwayat untuk akun ini',
          message: 'Riwayat mengikuti hak akses. Minta admin memberi izin '
              'menu tag STO atau Tag OK lewat Setting > User.',
        ),
      );
    }

    if (daftar.length == 1) {
      final satu = daftar.first;
      return Scaffold(
        appBar: AppBar(title: Text(satu.judul), actions: satu.aksi),
        body: satu.isi,
      );
    }

    return DefaultTabController(
      length: daftar.length,
      child: Builder(
        builder: (context) {
          final aktif = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: aktif,
            // Tombol AppBar ikut berganti mengikuti tab yang sedang dibuka -
            // tombol sinkron scan tidak ada gunanya di tab cetak.
            builder: (context, _) => Scaffold(
              appBar: AppBar(
                title: const Text('Riwayat'),
                actions: daftar[aktif.index].aksi,
                bottom: TabBar(
                  tabs: [
                    for (final r in daftar)
                      Tab(icon: Icon(r.icon, size: 18), text: r.label),
                  ],
                ),
              ),
              body: TabBarView(
                children: [for (final r in daftar) r.isi],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Isi riwayat yang berhak dilihat [user] - satu izin satu isi.
  ///
  /// Dipisah dari `build` supaya pemetaan izin-ke-tab bisa diuji tanpa
  /// menjalankan seluruh halaman beserta provider-nya.
  @visibleForTesting
  static List<RiwayatTab> tabsUntuk(AppUser? user) {
    if (user == null) return const [];

    return [
      // Cetak, scan, dan pembatalan adalah kejadian pada tag yang sama, jadi
      // ketiganya satu daftar dengan saringan - bukan tiga tab yang harus
      // dibandingkan sendiri oleh pembacanya. Isinya tetap mengikuti izin.
      if (user.canPrepare || user.canScan || user.canCancel)
        RiwayatTab(
          label: 'STO',
          icon: Icons.receipt_long_outlined,
          judul: 'Riwayat Tag STO',
          isi: const StoHistoryView(),
          // Tombol sinkron hanya berguna bagi yang mencatat hasil hitung.
          aksi: user.canScan ? const [ScanHistorySyncButton()] : const [],
        ),
      // Tag OK punya tabnya sendiri: barisnya bukan tag STO, dan menyatukan
      // keduanya dalam satu daftar justru menyulitkan penelusuran selisih.
      if (user.punyaTagOk)
        const RiwayatTab(
          label: 'Tag OK',
          icon: Icons.local_offer_outlined,
          judul: 'Riwayat Tag OK',
          isi: TagOkHistoryView(),
        ),
    ];
  }
}
