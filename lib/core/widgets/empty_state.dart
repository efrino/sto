import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Tetap di tengah selama ruangnya cukup, dan berubah jadi bisa digulung
    // begitu ruangnya menyempit - mis. saat keyboard naik di halaman pencarian
    // (tinggi sisa pernah cuma 221px, sementara isinya butuh 265px).
    return LayoutBuilder(
      builder: (context, constraints) {
        final tinggi = constraints.maxHeight;
        final minimal = tinggi.isFinite
            ? (tinggi - 64).clamp(0.0, tinggi)
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimal),
            child: _isi(),
          ),
        );
      },
    );
  }

  Widget _isi() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: AppColors.navySoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 38, color: AppColors.navy),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: 220,
            child: OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}
