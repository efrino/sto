import 'package:flutter/material.dart';

import '../../data/models/sto_tag.dart';
import '../theme/app_colors.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;
  final bool dense;

  factory StatusChip.tag(TagStatus status, {bool dense = false}) {
    switch (status) {
      case TagStatus.draft:
        return StatusChip(
          label: status.label,
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.edit_note,
          dense: dense,
        );
      case TagStatus.printed:
        return StatusChip(
          label: status.label,
          color: AppColors.success,
          background: AppColors.successSoft,
          icon: Icons.check_circle,
          dense: dense,
        );
      case TagStatus.pendingCancel:
        return StatusChip(
          label: status.label,
          color: AppColors.info,
          background: AppColors.infoSoft,
          icon: Icons.hourglass_top,
          dense: dense,
        );
      case TagStatus.cancelled:
        return StatusChip(
          label: status.label,
          color: AppColors.danger,
          background: AppColors.dangerSoft,
          icon: Icons.cancel,
          dense: dense,
        );
    }
  }

  factory StatusChip.sync(SyncStatus status, {bool dense = true}) {
    switch (status) {
      case SyncStatus.synced:
        return StatusChip(
          label: status.label,
          color: AppColors.info,
          background: AppColors.infoSoft,
          icon: Icons.cloud_done,
          dense: dense,
        );
      case SyncStatus.pending:
        return StatusChip(
          label: status.label,
          color: AppColors.textSecondary,
          background: AppColors.navySoft,
          icon: Icons.cloud_upload_outlined,
          dense: dense,
        );
      case SyncStatus.failed:
        return StatusChip(
          label: status.label,
          color: AppColors.danger,
          background: AppColors.dangerSoft,
          icon: Icons.cloud_off,
          dense: dense,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10 : 11.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
