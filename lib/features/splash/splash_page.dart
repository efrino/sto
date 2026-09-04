import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../state/admin_provider.dart';
import '../../state/printer_provider.dart';
import '../../state/session_provider.dart';
import '../../state/settings_provider.dart';

/// Layar pembuka: memuat setting, sesi tersimpan, dan mencoba menyambungkan
/// printer internal sebelum masuk ke halaman utama.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String _status = 'Menyiapkan aplikasi...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final session = context.read<SessionProvider>();
    final settings = context.read<SettingsProvider>();
    final printer = context.read<PrinterProvider>();

    await settings.bootstrap();
    if (!mounted) return;

    setState(() => _status = 'Memeriksa sesi login...');
    await session.bootstrap();
    if (!mounted) return;

    setState(() => _status = 'Menyiapkan data STO...');
    // Menyemai admin bawaan + periode contoh bila perangkat masih kosong,
    // supaya tidak ada perangkat yang terkunci tanpa admin/event.
    // User sesi ikut dikirim supaya event & area ditarik dari server sejak
    // awal - operator pun butuh event berjalan untuk menyiapkan tag.
    await context.read<AdminProvider>().load(
          seedCreatedBy: session.user?.nik ?? 'SYSTEM',
          admin: session.user,
        );
    if (!mounted) return;

    setState(() => _status = 'Menyiapkan printer...');
    await printer.bootstrap();
    if (!mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      session.status == SessionStatus.authenticated
          ? AppRoutes.home
          : AppRoutes.login,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Image.asset('assets/images/logo-maj.png', height: 78),
            const SizedBox(height: 26),
            const Text(
              AppConfig.appName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Cetak Tag STO - Blueprint MPOS 332',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const Spacer(),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 14),
            Text(
              _status,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 34),
            const Text(
              '${AppConfig.companyName} - ${AppConfig.departement}',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}
