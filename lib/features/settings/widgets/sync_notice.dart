import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Pemberitahuan kecil bahwa isi halaman datang dari cache perangkat, bukan
/// dari server. Sengaja tidak berupa dialog: admin tetap boleh bekerja, cuma
/// perlu tahu angkanya mungkin ketinggalan.
class SyncNotice extends StatelessWidget {
  const SyncNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: Color(0xFF7A5312),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
