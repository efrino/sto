import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../state/device_provider.dart';
import '../../state/session_provider.dart';

/// Login memakai NIK (mengikuti pola aplikasi MAJ lainnya).
/// Kolom password disiapkan tapi opsional - tinggal diaktifkan saat API siap.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nikController = TextEditingController();
  final _nikFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Identitas perangkat ditampilkan supaya operator tahu ia sedang memakai
    // perangkat yang mana saat melapor ke admin.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<DeviceProvider>().load(),
    );
  }

  @override
  void dispose() {
    _nikController.dispose();
    _nikFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final session = context.read<SessionProvider>();
    final ok = await session.login(_nikController.text.trim());
    if (!mounted) return;

    if (ok) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else {
      AppFeedback.error(context, session.error ?? 'Login gagal.');
      session.clearError();
    }
  }

  /// Nomor aset perangkat, bila admin sudah memberikannya.
  ///
  /// ANDROID_ID sengaja TIDAK ditampilkan di layar ini - itu kunci teknis
  /// pemasangan NIK di server, dan layar login terbuka bagi siapa pun yang
  /// memegang handheld. Admin tetap bisa melihatnya lengkap setelah masuk,
  /// lewat Setting > Perangkat & pairing.
  ///
  /// Nomor asetnya sendiri bukan rahasia: stikernya tertempel di badan
  /// perangkat, dan justru itu yang disebut operator saat melapor ke admin.
  String _perangkatLabel(BuildContext context) {
    final current = context.watch<DeviceProvider>().current;
    if (current != null && current.terdaftar) {
      return 'Perangkat ${current.assetName}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset('assets/images/logo-maj.png', height: 64),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Masuk',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gunakan NIK karyawan untuk mulai persiapan STO.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 26),
                TextFormField(
                  controller: _nikController,
                  focusNode: _nikFocus,
                  autofocus: true,
                  // NIK bisa berupa angka (11223344) maupun beralfabet (A.10525),
                  // jadi keyboard teks biasa dan hanya huruf/angka/titik/strip.
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9./\-]')),
                    LengthLimitingTextInputFormatter(20),
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) => newValue.copyWith(
                        text: newValue.text.toUpperCase(),
                      ),
                    ),
                  ],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'NIK',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'NIK wajib diisi';
                    if (v.length < 3) return 'NIK terlalu pendek';
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 26),
                ElevatedButton.icon(
                  onPressed: session.isBusy ? null : _submit,
                  icon: session.isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login),
                  label: Text(session.isBusy ? 'Memproses...' : 'MASUK'),
                ),
                // TIDAK ADA keterangan aturan login di sini.
                //
                // Sebelumnya layar ini menjelaskan bahwa operator dikunci ke
                // perangkat, di mana admin mengaturnya (Setting > Perangkat),
                // dan bahwa ADMIN BEBAS LOGIN DI PERANGKAT MANA PUN. Kalimat
                // terakhir itu justru menunjuk jalan masuk: siapa pun yang
                // memegang handheld tahu bahwa cukup satu NIK admin untuk
                // lolos dari penguncian perangkat. Aturannya tetap berlaku;
                // yang tidak perlu adalah mengumumkannya sebelum login.
                const SizedBox(height: 24),
                if (_perangkatLabel(context).isNotEmpty) ...[
                  Center(
                    child: Text(
                      _perangkatLabel(context),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const Center(
                  child: Text(
                    '${AppConfig.companyName}\n${AppConfig.plantName} - ${AppConfig.departement}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
