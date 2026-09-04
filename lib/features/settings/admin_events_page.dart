import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/sto_event.dart';
import '../../state/admin_provider.dart';
import '../../state/session_provider.dart';
import 'widgets/sync_notice.dart';
import 'widgets/area_picker.dart';

/// CRUD event STO (khusus admin). Tag hanya bisa dibuat saat ada event
/// berstatus BUKA yang tanggalnya mencakup hari ini.
class AdminEventsPage extends StatefulWidget {
  const AdminEventsPage({super.key});

  @override
  State<AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends State<AdminEventsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminProvider>().load(
        admin: context.read<SessionProvider>().user,
      ),
    );
  }

  Future<void> _openForm({StoEvent? event}) async {
    final admin = context.read<AdminProvider>();
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final hasil = await showModalBottomSheet<StoEvent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _EventForm(
        event: event,
        areaOptions: admin.areas,
        createdBy: user.nik,
      ),
    );
    if (hasil == null || !mounted) return;

    await _simpan(admin, hasil);
  }

  /// Menyimpan event, sekaligus menangani aturan "hanya satu event berjalan":
  /// server menahan permintaan yang akan membuat event kedua berjalan, dan
  /// admin yang memutuskan apakah event lama boleh ditutup.
  Future<void> _simpan(AdminProvider admin, StoEvent event) async {
    final ok = await admin.saveEvent(event);
    if (!mounted) return;

    final penegasan = admin.pesanPenegasan;
    if (!ok && penegasan != null) {
      final lanjut = await AppFeedback.confirm(
        context,
        title: 'Tutup event yang sedang berjalan?',
        message: penegasan,
        confirmLabel: 'Tutup & jadikan berjalan',
        destructive: true,
      );
      if (!mounted) return;
      admin.clearMessage();
      if (!lanjut) return;

      await admin.saveEvent(event, force: true);
      if (!mounted) return;
    }

    AppFeedback.info(context, admin.message ?? 'Tersimpan.');
    admin.clearMessage();
  }

  Future<void> _delete(StoEvent event) async {
    final admin = context.read<AdminProvider>();
    final ok = await AppFeedback.confirm(
      context,
      title: 'Hapus event?',
      message:
          'Event ${event.name} akan dihapus. Event yang sudah dipakai '
          'tag tidak bisa dihapus - tutup saja periodenya.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;

    await admin.deleteEvent(event.id);
    if (!mounted) return;
    AppFeedback.info(context, admin.message ?? 'Selesai.');
    admin.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Event STO')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('EVENT BARU'),
      ),
      body: Column(
        children: [
          if (admin.peringatanSinkron != null)
            SyncNotice(message: admin.peringatanSinkron!),
          Expanded(
            child: admin.loading && admin.events.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : admin.events.isEmpty
                ? EmptyState(
                    icon: Icons.event_note,
                    title: 'Belum ada event STO',
                    message:
                        'Buat periode STO dulu; tanpa event yang aktif, operator '
                        'tidak bisa menyiapkan tag.',
                    actionLabel: 'Buat event',
                    onAction: () => _openForm(),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: admin.events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final event = admin.events[index];
                      final aktif = event.isActiveOn(DateTime.now());
                      return _EventTile(
                        event: event,
                        aktif: aktif,
                        onEdit: () => _openForm(event: event),
                        onDelete: () => _delete(event),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.aktif,
    required this.onEdit,
    required this.onDelete,
  });

  final StoEvent event;
  final bool aktif;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: aktif ? AppColors.success : AppColors.border,
            width: aktif ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: event.isOpen
                        ? AppColors.successSoft
                        : AppColors.navySoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    aktif ? 'AKTIF' : event.status.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: event.isOpen ? AppColors.success : AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              event.periodLabel,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Area: ${event.areaLabel}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Hapus'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(0, 34),
                  ),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Ubah'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 34)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EventForm extends StatefulWidget {
  const _EventForm({
    required this.event,
    required this.areaOptions,
    required this.createdBy,
  });

  final StoEvent? event;
  final List<String> areaOptions;
  final String createdBy;

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  late final TextEditingController _nameController;
  late DateTime _start;
  late DateTime _end;
  late List<String> _areas;
  late StoEventStatus _status;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final now = DateTime.now();
    _nameController = TextEditingController(text: event?.name ?? '');
    _start = event?.startDate ?? DateTime(now.year, now.month, 1);
    _end = event?.endDate ?? DateTime(now.year, now.month + 1, 0);
    _areas = List<String>.from(event?.areas ?? const []);
    _status = event?.status ?? StoEventStatus.open;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool mulai}) async {
    final awal = mulai ? _start : _end;
    final hasil = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime(awal.year - 2),
      lastDate: DateTime(awal.year + 2),
    );
    if (hasil == null) return;
    setState(() {
      if (mulai) {
        _start = hasil;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = hasil;
      }
    });
  }

  void _submit() {
    final now = DateTime.now();
    final id =
        widget.event?.id ??
        'STO-${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    Navigator.pop(
      context,
      StoEvent(
        id: id,
        name: _nameController.text.trim(),
        startDate: _start,
        endDate: _end,
        areas: _areas,
        status: _status,
        createdBy: widget.event?.createdBy ?? widget.createdBy,
        createdAt: widget.event?.createdAt ?? now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event == null ? 'Event STO baru' : 'Ubah event STO',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nama event',
                hintText: 'contoh: STO SEPTEMBER 2026',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Mulai',
                    value: _start,
                    onTap: () => _pickDate(mulai: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Selesai',
                    value: _end,
                    onTap: () => _pickDate(mulai: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AreaPicker(
              title: 'Area yang dihitung',
              helper: 'Kosongkan bila seluruh area ikut dihitung.',
              options: widget.areaOptions,
              selected: _areas,
              onChanged: (value) => setState(() => _areas = value),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _status == StoEventStatus.open,
              onChanged: (value) => setState(
                () => _status = value
                    ? StoEventStatus.open
                    : StoEventStatus.closed,
              ),
              title: const Text('Event dibuka'),
              subtitle: const Text(
                'Tutup bila periode selesai - operator langsung tidak bisa '
                'membuat tag baru.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text('SIMPAN EVENT'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          '${value.day.toString().padLeft(2, '0')}/'
          '${value.month.toString().padLeft(2, '0')}/${value.year}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
