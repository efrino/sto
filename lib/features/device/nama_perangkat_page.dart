import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/di/dependencies.dart';
import '../../core/theme/app_colors.dart';

/// Layar pertama pada pemasangan baru: memberi nama perangkat ini.
///
/// Ditanyakan sekali, sebelum siapa pun login. Namanya dipakai saat perangkat
/// mendaftarkan dirinya ke server - dan pendaftaran itulah yang membuat
/// operator bisa langsung masuk dengan NIK-nya sendiri, tanpa admin harus
/// datang dan login lebih dulu di perangkat ini.
///
/// Nama yang bagus adalah nama yang dikenali admin di layar Setting >
/// Perangkat: "HP BUDI", "HT IFPD 02". Bukan nama sistem seperti "SM-A125F",
/// yang di daftar akan tampak sama dengan belasan perangkat lain.
class NamaPerangkatPage extends StatefulWidget {
  const NamaPerangkatPage({super.key});

  @override
  State<NamaPerangkatPage> createState() => _NamaPerangkatPageState();
}

class _NamaPerangkatPageState extends State<NamaPerangkatPage> {
  final _nama = TextEditingController();
  String _model = '';
  bool _menyimpan = false;
  String? _galat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _isiUsulan());
  }

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  /// Model perangkat dipakai sebagai keterangan, BUKAN sebagai isi kolom.
  ///
  /// Kalau kolomnya diisi otomatis, kebanyakan orang akan menekan Lanjut
  /// tanpa membacanya - dan daftar perangkat admin berisi sepuluh baris
  /// bernama sama.
  Future<void> _isiUsulan() async {
    final deps = context.read<AppDependencies>();
    final identitas = await deps.deviceRepository.identity();
    if (!mounted) return;
    setState(() => _model = identitas.model);

    final pulih = await deps.deviceRepository.pulihkanNamaDariServer();
    if (!mounted) return;
    if (pulih != null && pulih.isNotEmpty) {
      await deps.prefs.setNamaPerangkat(pulih);
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    }
  }

  Future<void> _lanjut() async {
    final nama = _nama.text.trim();
    if (nama.length < 3) {
      setState(() => _galat = 'Nama perangkat minimal 3 huruf.');
      return;
    }

    setState(() {
      _menyimpan = true;
      _galat = null;
    });

    final deps = context.read<AppDependencies>();
    await deps.prefs.setNamaPerangkat(nama.toUpperCase());
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Image.asset('assets/images/logo-maj.png', height: 62),
              ),
              const SizedBox(height: 28),
              const Text(
                'Perangkat ini belum punya nama',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Beri nama supaya admin mengenalinya di daftar perangkat. '
                'Cukup sekali, dan setelah ini Anda bisa langsung login '
                'dengan NIK sendiri.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _nama,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Nama perangkat',
                  hintText: 'mis. HP BUDI  /  HT IFPD 02',
                  errorText: _galat,
                  prefixIcon: const Icon(Icons.smartphone),
                ),
                onSubmitted: (_) => _lanjut(),
                onChanged: (_) {
                  if (_galat != null) setState(() => _galat = null);
                },
              ),
              if (_model.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Perangkat terbaca sebagai $_model',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _menyimpan ? null : _lanjut,
                  child: _menyimpan
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Lanjut ke login'),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.navySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.navy),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Satu NIK menempel pada satu perangkat. Saat Anda '
                        'login di sini, NIK Anda otomatis pindah ke perangkat '
                        'ini dan tidak bisa dipakai lagi di perangkat '
                        'sebelumnya.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  '${AppConfig.appName} v1.0.0',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
