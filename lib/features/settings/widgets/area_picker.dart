import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Pemilih area (banyak pilihan) untuk izin user maupun cakupan event.
///
/// Daftar pilihan diambil dari master part; admin juga boleh mengetik area
/// baru bila ada area yang belum pernah muncul di master.
class AreaPicker extends StatefulWidget {
  const AreaPicker({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.helper,
    this.bolehTambahManual = false,
  });

  final String title;
  final String? helper;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  /// Mengizinkan mengetik area di luar daftar.
  ///
  /// Default mati: area STO hanya lima (IFRM, PRESS, IFPP, WELD, IFPD) dan
  /// nilainya dipakai apa adanya untuk menyaring part. Salah ketik satu huruf
  /// - mis. "WELDING" - membuat daftar part operator kosong tanpa pesan
  /// kesalahan apa pun, jadi lebih baik tidak bisa diketik sama sekali.
  final bool bolehTambahManual;

  @override
  State<AreaPicker> createState() => _AreaPickerState();
}

class _AreaPickerState extends State<AreaPicker> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(String area) {
    final next = List<String>.from(widget.selected);
    if (next.contains(area)) {
      next.remove(area);
    } else {
      next.add(area);
    }
    widget.onChanged(next);
  }

  void _addManual() {
    final area = _controller.text.trim().toUpperCase();
    if (area.isEmpty || widget.selected.contains(area)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.selected, area]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Urutan sengaja mengikuti `options` (urutan tetap area STO), lalu
    // area lama yang sudah terlanjur tersimpan menyusul di belakang.
    final options = <String>{...widget.options, ...widget.selected}.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (widget.helper != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.helper!,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (options.isEmpty)
          const Text(
            'Belum ada daftar area.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((area) {
              final aktif = widget.selected.contains(area);
              return FilterChip(
                label: Text(area),
                selected: aktif,
                onSelected: (_) => _toggle(area),
                selectedColor: AppColors.primarySoft,
                checkmarkColor: AppColors.primary,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: aktif ? AppColors.primary : AppColors.textSecondary,
                ),
              );
            }).toList(),
          ),
        if (widget.bolehTambahManual) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'tambah area lain',
                    prefixIcon: Icon(Icons.add_location_alt_outlined),
                  ),
                  onSubmitted: (_) => _addManual(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: _addManual,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 46),
                  ),
                  child: const Text('TAMBAH'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
