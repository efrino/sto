import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/chat_message.dart';
import '../../state/chat_provider.dart';
import '../../state/session_provider.dart';

/// Daftar percakapan.
///
/// Operator hanya punya dua: Admin dan Pengumuman. Admin melihat seluruh utas
/// operator - semua admin membaca kotak masuk yang sama, karena di lapangan
/// yang dibutuhkan operator adalah jawabannya datang, bukan jawabannya datang
/// dari admin tertentu.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  Future<void> _muat() async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;
    await context.read<ChatProvider>().muatThreads(user);
  }

  Future<void> _buka(ChatThread thread) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPage(thread: thread),
      ),
    );
    if (!mounted) return;
    // Daftar disegarkan setelah kembali: jumlah belum dibaca berubah, dan
    // mungkin ada pesan baru pada utas lain.
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final user = context.watch<SessionProvider>().user;
    final admin = user?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Pesan')),
      body: RefreshIndicator(
        onRefresh: _muat,
        child: chat.memuat && chat.threads.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : chat.threads.isEmpty
                ? ListView(
                    children: const [
                      EmptyState(
                        icon: Icons.forum_outlined,
                        title: 'Belum ada percakapan',
                        message: 'Kirim pesan ke admin bila ada yang perlu '
                            'ditanyakan saat STO berjalan.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: chat.threads.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: 72,
                      color: AppColors.border,
                    ),
                    itemBuilder: (context, i) => _baris(
                      chat.threads[i],
                      user?.nik ?? '',
                      admin: admin,
                    ),
                  ),
      ),
    );
  }

  /// Lencana peran - bentuknya sama dengan yang dipakai di dalam percakapan.
  Widget _lencanaPeran(bool admin) => _ChatRoomPageState._lencana(admin);

  Widget _baris(ChatThread t, String nik, {required bool admin}) {
    final judul = t.judulUntuk(nik);
    final kosong = t.lastId == 0;

    return ListTile(
      onTap: () => _buka(t),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: t.broadcast ? AppColors.accentSoft : AppColors.navySoft,
        child: Icon(
          t.broadcast ? Icons.campaign_outlined : Icons.person_outline,
          color: t.broadcast ? AppColors.accent : AppColors.navy,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              judul,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
          // Admin melihat banyak utas berisi NIK saja; peran pemiliknya
          // ditandai supaya utas rekan admin tidak tertukar dengan utas
          // operator yang sedang menunggu jawaban.
          if (admin && t.labelPeran.isNotEmpty) ...[
            const SizedBox(width: 6),
            _lencanaPeran(t.pemilikAdmin),
          ],
        ],
      ),
      subtitle: Text(
        kosong
            ? (t.broadcast
                ? 'Belum ada pengumuman'
                : 'Belum ada pesan')
            : '${t.lastFrom == nik ? 'Anda: ' : ''}${t.lastBody}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          color: kosong ? AppColors.textMuted : AppColors.textSecondary,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (t.lastAt != null)
            Text(
              Formatters.ringkas(t.lastAt!),
              style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            ),
          if (t.belumDibaca > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${t.belumDibaca}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Satu percakapan - gelembung pesan dan kotak tulis.
class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({super.key, required this.thread});

  final ChatThread thread;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _tulis = TextEditingController();
  final _gulir = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<SessionProvider>().user;
      if (user == null) return;
      await context.read<ChatProvider>().bukaUtas(user, widget.thread.thread);
      _keBawah();
    });
  }

  @override
  void dispose() {
    // Denyut penyegar dihentikan begitu layarnya ditinggalkan.
    context.read<ChatProvider>().tutupUtas();
    _tulis.dispose();
    _gulir.dispose();
    super.dispose();
  }

  void _keBawah() {
    if (!_gulir.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_gulir.hasClients) return;
      _gulir.jumpTo(_gulir.position.maxScrollExtent);
    });
  }

  Future<void> _kirim() async {
    final user = context.read<SessionProvider>().user;
    final isi = _tulis.text.trim();
    if (user == null || isi.isEmpty) return;

    final chat = context.read<ChatProvider>();
    // Kotak dikosongkan lebih dulu supaya terasa cepat; bila server menolak,
    // isinya dikembalikan agar tidak perlu mengetik ulang.
    _tulis.clear();
    await chat.kirim(user, isi);
    if (!mounted) return;

    if (chat.error != null) {
      _tulis.text = isi;
      AppFeedback.error(context, chat.error!);
      chat.bersihkanPesan();
      return;
    }
    _keBawah();
  }

  /// Admin membisukan pengirim yang menyalahgunakan kotak pesan.
  Future<void> _bisukan() async {
    final user = context.read<SessionProvider>().user;
    if (user == null) return;

    final menit = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Bisukan ${widget.thread.thread}?'),
        children: [
          for (final pilihan in const {
            '15 menit': 15,
            '1 jam': 60,
            '1 hari': 1440,
            'Lepas pembisuan': 0,
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, pilihan.value),
              child: Text(pilihan.key),
            ),
        ],
      ),
    );
    if (menit == null || !mounted) return;

    final chat = context.read<ChatProvider>();
    final ok = await chat.bisukan(user, widget.thread.thread, menit);
    if (!mounted) return;

    if (ok) {
      AppFeedback.success(
        context,
        menit == 0
            ? 'Pembisuan dilepas.'
            : '${widget.thread.thread} dibisukan $menit menit.',
      );
    } else {
      AppFeedback.error(context, chat.error ?? 'Gagal mengubah pembisuan.');
      chat.bersihkanPesan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final user = context.watch<SessionProvider>().user;
    final nik = user?.nik ?? '';
    final admin = user?.isAdmin ?? false;

    // Pengumuman hanya bisa ditulis admin; operator membacanya saja.
    final bolehMenulis = !widget.thread.broadcast || admin;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.thread.judulUntuk(nik)),
        actions: [
          if (admin && !widget.thread.broadcast)
            IconButton(
              tooltip: 'Bisukan pengirim',
              onPressed: _bisukan,
              icon: const Icon(Icons.volume_off_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chat.memuat && chat.pesan.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : chat.pesan.isEmpty
                    ? EmptyState(
                        icon: widget.thread.broadcast
                            ? Icons.campaign_outlined
                            : Icons.chat_bubble_outline,
                        title: widget.thread.broadcast
                            ? 'Belum ada pengumuman'
                            : 'Belum ada pesan',
                        message: bolehMenulis
                            ? 'Tulis pesan pertama di kotak bawah.'
                            : 'Pengumuman dari admin akan muncul di sini.',
                      )
                    : ListView.builder(
                        controller: _gulir,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        itemCount: chat.pesan.length,
                        itemBuilder: (context, i) =>
                            _gelembung(chat.pesan[i], nik),
                      ),
          ),
          if (bolehMenulis) _kotakTulis(chat) else _catatanBaca(),
        ],
      ),
    );
  }

  Widget _gelembung(ChatMessage m, String nik) {
    final milikSaya = m.fromNik == nik;

    return Align(
      alignment: milikSaya ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: milikSaya ? AppColors.primarySoft : Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(milikSaya ? 14 : 4),
            bottomRight: Radius.circular(milikSaya ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // NIK pengirim hanya ditulis untuk pesan orang lain - pada utas
            // admin, yang membalas bisa berganti-ganti orang.
            if (!milikSaya)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.fromNik,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  // Operator hanya melihat NIK asing saat dibalas; penanda ini
                  // yang memberitahunya bahwa jawaban itu datang dari orang
                  // yang berwenang.
                  if (m.dariAdmin) ...[
                    const SizedBox(width: 6),
                    _ChatRoomPageState._lencana(true),
                  ],
                ],
              ),
            Text(
              m.body,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 2),
            Text(
              Formatters.ringkas(m.createdAt),
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kotakTulis(ChatProvider chat) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _tulis,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: widget.thread.broadcast
                      ? 'Tulis pengumuman untuk semua'
                      : 'Tulis pesan',
                ),
                onSubmitted: (_) => _kirim(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: chat.mengirim ? null : _kirim,
              icon: chat.mengirim
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  /// Lencana peran pengirim/pemilik utas.
  static Widget _lencana(bool admin) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: admin ? AppColors.accentSoft : AppColors.navySoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          admin ? 'ADMIN' : 'OPERATOR',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: admin ? AppColors.accent : AppColors.navy,
          ),
        ),
      );

  Widget _catatanBaca() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: AppColors.background,
        child: const Text(
          'Hanya admin yang bisa menulis pengumuman.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
}
