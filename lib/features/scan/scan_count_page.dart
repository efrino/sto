import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/di/dependencies.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../data/models/app_user.dart';
import '../../data/models/sto_count.dart';
import '../../data/repositories/count_repository.dart';
import '../../state/count_provider.dart';
import '../../state/session_provider.dart';
import 'widgets/tag_scanner.dart';

/// Scan tag STO untuk MENGHITUNG isinya.
///
/// Alur: scan QR -> ambil detail part (lokal atau server) -> operator mengisi
/// qty -> tersimpan sebagai hasil hitung tim tersebut dan diantrekan sebagai
/// POST { nik, tag_no, tim, qty }.
class ScanCountPage extends StatefulWidget {
  const ScanCountPage({super.key});

  @override
  State<ScanCountPage> createState() => _ScanCountPageState();
}

class _ScanCountPageState extends State<ScanCountPage> {
  final GlobalKey<TagScannerState> _scannerKey = GlobalKey<TagScannerState>();
  bool _handling = false;

  Future<void> _handleCode(String tagNo) async {
    if (_handling) return;
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    setState(() => _handling = true);
    final counts = context.read<CountProvider>();
    final deps = context.read<AppDependencies>();
    await HapticFeedback.mediumImpact();
    await deps.sound.beep();

    if (!user.hasTeam) {
      if (!mounted) return;
      setState(() => _handling = false);
      AppFeedback.error(
        context,
        'Tim untuk NIK ${user.nik} belum diatur admin (Setting > User).',
      );
      return;
    }

    final tag = await counts.lookup(tagNo, user: user);
    if (!mounted) return;

    if (tag == null) {
      setState(() => _handling = false);
      await deps.sound.error();
      if (!mounted) return;
      AppFeedback.error(context, 'Tag $tagNo tidak ditemukan.');
      return;
    }

    // Tag yang dibatalkan / sedang diajukan batal tidak boleh dihitung.
    if (!tag.bolehDihitung) {
      setState(() => _handling = false);
      await deps.sound.error();
      if (!mounted) return;
      AppFeedback.error(context, tag.alasanTidakBolehDihitung);
      return;
    }

    final milikTim = await counts.myTeamCount(tag.tagNo, user);
    final timLain = await counts.otherTeamCounts(tag.tagNo, user);
    if (!mounted) return;

    await _scannerKey.currentState?.pauseCamera();
    if (!mounted) return;

    await _showForm(tag: tag, user: user, existing: milikTim, others: timLain);
    if (!mounted) return;

    await _scannerKey.currentState?.resumeCamera();
    if (!mounted) return;
    setState(() => _handling = false);
    _scannerKey.currentState?.armWedge();
  }

  Future<void> _showForm({
    required ScannedTag tag,
    required AppUser user,
    required StoCount? existing,
    required List<StoCount> others,
  }) {
    // Koreksi hanya boleh oleh pencatat yang sama (aturan satu tim satu angka).
    final terkunci = existing != null && existing.nik != user.nik;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => _CountForm(
        tag: tag,
        user: user,
        existing: existing,
        others: others,
        locked: terkunci,
        onSubmit: (qty) async {
          Navigator.pop(sheetContext);
          await _submit(tag, user, qty);
        },
      ),
    );
  }

  Future<void> _submit(ScannedTag tag, AppUser user, int qty) async {
    final counts = context.read<CountProvider>();
    final deps = context.read<AppDependencies>();

    final saved = await counts.submit(tag: tag, user: user, qty: qty);
    if (!mounted) return;

    if (saved != null) {
      await deps.sound.success();
      if (!mounted) return;
      AppFeedback.success(context, counts.message ?? 'Qty tersimpan.');
    } else {
      await deps.sound.error();
      if (!mounted) return;
      AppFeedback.error(context, counts.message ?? 'Gagal menyimpan qty.');
    }
    counts.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Tag STO')),
      body: TagScanner(
        key: _scannerKey,
        busy: _handling,
        hint: user == null
            ? ''
            : '${user.teamLabel} - arahkan kamera ke QR tag',
        onCode: _handleCode,
      ),
    );
  }
}

class _CountForm extends StatefulWidget {
  const _CountForm({
    required this.tag,
    required this.user,
    required this.existing,
    required this.others,
    required this.locked,
    required this.onSubmit,
  });

  final ScannedTag tag;
  final AppUser user;
  final StoCount? existing;
  final List<StoCount> others;
  final bool locked;
  final Future<void> Function(int qty) onSubmit;

  @override
  State<_CountForm> createState() => _CountFormState();
}

class _CountFormState extends State<_CountForm> {
  late final TextEditingController _qty;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: widget.existing == null ? '' : '${widget.existing!.qty}',
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.tag;
    final existing = widget.existing;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              tag.tagNo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tag.fromServer
                  ? 'Detail dari server - tag dicetak ${tag.printedBy}'
                  : 'Tag dicetak di perangkat ini oleh ${tag.printedBy}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _row('Part / Job', '${tag.partNumber}  -  ${tag.jobNumber}'),
            _row('Nama', tag.partName),
            _row('Area', tag.area),
            _row('Status part', tag.partType),
            _row('Tim Anda', widget.user.teamLabel),
            if (widget.others.isNotEmpty)
              _row(
                'Tim lain',
                widget.others
                    .map((c) => '${c.team}: ${c.qty} ${c.unit}')
                    .join(' | '),
              ),
            const SizedBox(height: 16),
            if (widget.locked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Tag ini sudah dihitung ${existing!.nik} dari tim yang sama '
                  '(${existing.qty} ${existing.unit}). Koreksi hanya boleh '
                  'dilakukan oleh pencatatnya.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Color(0xFF7A5312),
                  ),
                ),
              )
            else ...[
              if (existing != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Sudah pernah Anda catat ${existing.qty} ${existing.unit} '
                    '(${Formatters.dateTime(existing.updatedAt ?? existing.countedAt)}). '
                    'Isi angka baru untuk mengoreksi.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.info,
                    ),
                  ),
                ),
              TextField(
                controller: _qty,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
                decoration: InputDecoration(
                  labelText: 'Qty hasil hitung',
                  suffixText: tag.unit,
                  prefixIcon: const Icon(Icons.calculate_outlined),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save),
                label: Text(
                  existing == null ? 'SIMPAN QTY' : 'PERBARUI QTY',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _submit() {
    final qty = int.tryParse(_qty.text.trim());
    if (qty == null) {
      AppFeedback.error(context, 'Qty belum diisi.');
      return;
    }
    widget.onSubmit(qty);
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
