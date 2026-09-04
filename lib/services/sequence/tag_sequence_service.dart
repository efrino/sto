import 'dart:math' as math;

import '../../core/config/app_config.dart';
import '../../data/local/prefs_store.dart';
import '../../data/local/tag_dao.dart';
import '../../data/remote/api_gateway.dart';
import '../../data/remote/sto_api.dart';

/// Penyedia nomor urut tag.
///
/// Nomor urut WAJIB unik karena dipakai sebagai identitas tag yang dicetak.
/// Urutan prioritas:
/// 1. minta blok nomor ke server (`/sequence/reserve`),
/// 2. bila server tidak bisa dihubungi -> pakai counter lokal dengan prefix
///    berawalan `L` supaya mudah direkonsiliasi saat sinkronisasi.
class TagSequenceService {
  TagSequenceService({
    required this.api,
    required this.prefs,
    required this.tagDao,
  });

  final ApiGateway api;
  final PrefsStore prefs;
  final TagDao tagDao;

  Future<SequenceReservation> reserve({
    required int qty,
    required String area,
    required String nik,
  }) async {
    try {
      final reservation =
          await api.reserveSequence(qty: qty, area: area, nik: nik);
      if (reservation.prefix.isEmpty) {
        return SequenceReservation(
          prefix: todayPrefix(),
          start: reservation.start,
          end: reservation.end,
        );
      }
      return reservation;
    } catch (_) {
      return _reserveLocal(qty);
    }
  }

  /// Memesan nomor lanjutan berdasarkan isi database lokal, dengan prefix yang
  /// sudah ditentukan. Dipakai sebagai penyelamat bila nomor dari server
  /// ternyata sudah terpakai di perangkat ini (mis. counter server tiruan
  /// mengulang dari awal setelah aplikasi dijalankan ulang).
  Future<SequenceReservation> reserveAfterLocalMax(
    String prefix,
    int qty,
  ) async {
    final last = await tagDao.lastSequenceForPrefix(prefix);
    return SequenceReservation(
      prefix: prefix,
      start: last + 1,
      end: last + qty,
      fromServer: false,
    );
  }

  Future<SequenceReservation> _reserveLocal(int qty) async {
    final prefix = '${AppConfig.offlineSequencePrefix}${todayPrefix()}';
    final fromPrefs = await prefs.localSequence(prefix);
    final fromDb = await tagDao.lastSequenceForPrefix(prefix);
    final last = math.max(fromPrefs, fromDb);
    final start = last + 1;
    final end = last + qty;
    await prefs.setLocalSequence(prefix, end);
    return SequenceReservation(
      prefix: prefix,
      start: start,
      end: end,
      fromServer: false,
    );
  }

  /// Prefix harian: STO + yyMMdd (contoh: STO260902).
  static String todayPrefix([DateTime? date]) {
    final now = date ?? DateTime.now();
    return 'STO'
        '${now.year.toString().substring(2)}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Format akhir nomor tag: STO260902-000123
  static String formatTagNo(String prefix, int sequence) =>
      '$prefix-${sequence.toString().padLeft(AppConfig.sequencePadding, '0')}';
}
