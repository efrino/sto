import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Dialog alasan pembatalan (mispart dsb).
/// Mengembalikan alasan yang dipilih, atau null bila operator batal.
class CancelReasonDialog extends StatefulWidget {
  const CancelReasonDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Batalkan Tag',
  });

  final String title;
  final String message;

  /// Teks tombol konfirmasi - berbeda antara membatalkan tag yang gagal cetak
  /// dan mengajukan pembatalan tag yang sudah tersebar.
  final String confirmLabel;

  static const List<String> reasons = [
    'Mispart - part tidak sesuai',
    'Salah job number',
    'Salah area / lokasi',
    'Salah jumlah tag',
    'Kertas rusak / hasil cetak tidak terbaca',
  ];

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Batalkan Tag',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => CancelReasonDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<CancelReasonDialog> {
  String? _selected;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String? get _result {
    if (_selected == null) return null;
    if (_selected == 'lainnya') {
      final text = _otherController.text.trim();
      return text.isEmpty ? null : text;
    }
    return _selected;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (value) => setState(() => _selected = value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...CancelReasonDialog.reasons.map(
                    (reason) => RadioListTile<String>(
                      value: reason,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(reason, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const RadioListTile<String>(
                    value: 'lainnya',
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Lainnya', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            if (_selected == 'lainnya')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  controller: _otherController,
                  autofocus: true,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    hintText: 'Tulis alasan',
                    counterText: '',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Kembali',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _result == null
              ? null
              : () => Navigator.pop(context, _result),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
