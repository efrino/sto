import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Helper notifikasi & dialog konfirmasi supaya gaya pesan seragam.
class AppFeedback {
  AppFeedback._();

  static void success(BuildContext context, String message) =>
      _show(context, message, AppColors.success, Icons.check_circle);

  static void error(BuildContext context, String message) =>
      _show(context, message, AppColors.danger, Icons.error_outline);

  static void info(BuildContext context, String message) =>
      _show(context, message, AppColors.navy, Icons.info_outline);

  static void _show(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
  ) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 13.5, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Dialog konfirmasi (mis. batalkan tag, hapus data lokal).
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Ya, lanjutkan',
    String cancelLabel = 'Batal',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelLabel,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  destructive ? AppColors.danger : AppColors.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
