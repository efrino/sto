import 'package:flutter_test/flutter_test.dart';
import 'package:sto_prep/data/models/chat_message.dart';

/// Kotak pesan operator - admin.
///
/// Penjagaan spam yang sesungguhnya ada di server (aturan di aplikasi bisa
/// dilewati dengan memanggil API langsung); yang diuji di sini bagian yang
/// memang milik aplikasi: pembacaan respons dan penamaan utas.
void main() {
  group('Pembacaan pesan dari server', () {
    test('pesan biasa terbaca lengkap', () {
      final m = ChatMessage.fromServer({
        'id': '12',
        'thread': 'M.9276',
        'from_nik': 'F.9964',
        'body': 'Sudah saya cek, dicetak ulang ya',
        'broadcast': 0,
        'created_at': '2026-09-04 13:42:34',
      });

      expect(m.id, 12);
      expect(m.fromNik, 'F.9964');
      expect(m.broadcast, isFalse);
      expect(m.createdAt.hour, 13);
    });

    test('pengumuman ditandai broadcast', () {
      final m = ChatMessage.fromServer({
        'id': 3,
        'thread': 'BROADCAST',
        'from_nik': 'F.9964',
        'body': 'STO area IFPP mulai jam 13.00',
        'broadcast': 1,
        'created_at': '2026-09-04 13:45:00',
      });

      expect(m.broadcast, isTrue);
      expect(m.thread, ChatThread.broadcastKey);
    });

    test('respons rusak tidak menjatuhkan layar', () {
      // Baris tanpa waktu tetap dibaca - kehilangan satu pesan lebih baik
      // daripada layar pesan yang mati seluruhnya.
      final m = ChatMessage.fromServer({'id': 'x', 'body': 'halo'});

      expect(m.id, 0);
      expect(m.body, 'halo');
      expect(m.createdAt, isNotNull);
    });
  });

  group('Penamaan utas', () {
    test('utas sendiri diberi nama Admin, bukan NIK sendiri', () {
      const t = ChatThread(thread: 'M.9276');

      expect(t.judulUntuk('M.9276'), 'Admin');
    });

    test('bagi admin, utas operator bernama NIK operatornya', () {
      const t = ChatThread(thread: 'M.9276');

      expect(t.judulUntuk('F.9964'), 'M.9276');
    });

    test('utas pengumuman selalu bernama Pengumuman', () {
      const t = ChatThread(thread: ChatThread.broadcastKey, broadcast: true);

      expect(t.judulUntuk('M.9276'), 'Pengumuman');
      expect(t.judulUntuk('F.9964'), 'Pengumuman');
    });
  });

  group('Baris daftar percakapan', () {
    test('utas kosong terbaca sebagai belum ada pesan', () {
      final t = ChatThread.fromServer({
        'thread': 'BROADCAST',
        'broadcast': 1,
        'last_id': 0,
        'belum_dibaca': 0,
      });

      expect(t.lastId, 0);
      expect(t.lastAt, isNull);
      expect(t.belumDibaca, 0);
    });

    test('jumlah belum dibaca terbaca apa adanya dari server', () {
      // Angkanya dihitung server, bukan ditebak perangkat: satu utas dibaca
      // beberapa admin, jadi hitungan lokal akan cepat meleset.
      final t = ChatThread.fromServer({
        'thread': 'M.9276',
        'last_id': '2',
        'last_body': 'Sudah saya cek',
        'last_from': 'F.9964',
        'last_at': '2026-09-04 13:42:34',
        'belum_dibaca': '3',
      });

      expect(t.belumDibaca, 3);
      expect(t.lastFrom, 'F.9964');
      expect(t.lastAt, isNotNull);
    });
  });
}
