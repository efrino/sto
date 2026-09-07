import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Kotak cari untuk daftar di halaman Setting.
///
/// Penyaringannya di perangkat, bukan di server: daftar user, perangkat, dan
/// event hanya puluhan baris dan sudah terambil semua saat halaman dibuka -
/// menanyakan ulang ke server untuk tiap huruf yang diketik hanya membuat
/// hasilnya terlambat muncul.
class KotakCari extends StatelessWidget {
  const KotakCari({
    super.key,
    required this.controller,
    required this.petunjuk,
    required this.onUbah,
    this.jumlah,
    this.dari,
  });

  final TextEditingController controller;
  final String petunjuk;
  final ValueChanged<String> onUbah;

  /// Jumlah baris yang lolos saringan; null berarti tidak ditampilkan.
  final int? jumlah;

  /// Jumlah seluruh baris sebelum disaring.
  final int? dari;

  @override
  Widget build(BuildContext context) {
    final menyaring = controller.text.trim().isNotEmpty;

    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: petunjuk,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: !menyaring
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        controller.clear();
                        onUbah('');
                      },
                    ),
            ),
            onChanged: onUbah,
          ),
          // Jumlah hasil hanya ditulis saat menyaring - saat tidak menyaring,
          // angkanya cuma mengulang apa yang sudah terlihat di daftar.
          if (menyaring && jumlah != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                dari == null
                    ? '$jumlah hasil'
                    : '$jumlah dari $dari baris',
                style: const TextStyle(fontSize: 11.5, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}
