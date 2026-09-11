import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/di/dependencies.dart';
import 'core/utils/pesan_galat.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Penangkal crash global: tangkap error framework dan unhandled async error
  // agar aplikasi tidak mendadak force-close di lapangan.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled Async Error: $error\n$stack');
    // Kembalikan true agar Flutter menganggap error sudah ditangani dan
    // tidak mematikan proses aplikasi.
    return true;
  };

  // Tampilan darurat ramah pengguna bila terjadi galat rendering widget
  // alih-alih layar merah yang mengintimidasi operator.
  ErrorWidget.builder = (details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 36),
              const SizedBox(height: 8),
              const Text(
                'Terjadi kendala tampilan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // Disapu jadi kalimat manusia - jejak "RenderFlex overflowed"
                // atau "Null check operator" tidak membantu operator, dan
                // membuatnya menyangka datanya rusak.
                PesanGalat.manusiawi(details.exceptionAsString()),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Perangkat MPOS dipakai berdiri - kunci orientasi portrait.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await initializeDateFormatting('id');

  // Kegagalan di sini - biasanya database perangkat yang tidak bisa
  // dibuka/dimigrasi - dulu berarti layar putih tanpa penjelasan, dan
  // handheld itu mati total sampai ada yang menghapus datanya secara manual.
  // Sekarang operator melihat sebabnya dan tahu langkah berikutnya.
  final AppDependencies deps;
  try {
    deps = await AppDependencies.bootstrap();
  } catch (e, stack) {
    debugPrint('Bootstrap gagal: $e');
    debugPrint('$stack');
    runApp(_LayarGagalMulai(sebab: PesanGalat.manusiawi(e)));
    return;
  }

  runApp(StoPrepApp(deps: deps));
}

/// Ditampilkan hanya bila aplikasi tidak bisa menyiapkan dirinya sama sekali.
class _LayarGagalMulai extends StatelessWidget {
  const _LayarGagalMulai({required this.sebab});

  final String sebab;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFDC2626),
                  size: 44,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Aplikasi tidak bisa dimulai',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sebab,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Tutup aplikasi lalu buka lagi. Bila tetap gagal, buka '
                  'Setelan > Aplikasi > STO > Hapus data, lalu buka kembali - '
                  'semua data ada di server dan akan terbaca lagi setelah '
                  'login.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Color(0xFF1E293B),
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
