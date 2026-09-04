import '../../core/config/app_config.dart';
import '../local/part_dao.dart';
import '../local/prefs_store.dart';
import '../models/part_item.dart';
import '../remote/api_gateway.dart';

class PartCacheInfo {
  const PartCacheInfo({required this.count, this.lastSyncedAt});

  final int count;
  final DateTime? lastSyncedAt;

  bool get isEmpty => count == 0;
}

/// Pencarian part/job dengan pola cache-first:
/// 1. hasil selalu dibaca dari sqflite (cepat, tetap jalan offline),
/// 2. server dipanggil di belakang untuk menyegarkan cache bila sudah basi.
class PartRepository {
  PartRepository({
    required this.api,
    required this.dao,
    required this.prefs,
  });

  final ApiGateway api;
  final PartDao dao;
  final PrefsStore prefs;

  /// Panjang kata kunci minimum sebelum server ikut ditanya.
  ///
  /// Satu huruf cocok dengan ribuan baris - itu bukan pencarian, itu
  /// mengunduh seluruh master lewat jalan memutar.
  static const int minKeywordForServer = 2;

  /// true bila hasil terakhir dipotong oleh batas, sehingga masih mungkin ada
  /// part lain yang cocok. Dipakai layar untuk menyarankan kata kunci yang
  /// lebih spesifik.
  /// Pencarian part yang dibatasi [areas] (izin dari admin). Daftar kosong
  /// berarti tanpa batas - dipakai admin.
  Future<List<PartItem>> search(
    String keyword, {
    int limit = 50,
    int offset = 0,
    List<String> areas = const [],
  }) async {
    final local = await dao.search(
      keyword,
      limit: limit,
      offset: offset,
      areas: areas,
    );
    // Halaman lanjutan selalu dilayani cache - servernya sudah ditanya pada
    // halaman pertama.
    if (offset > 0) return local;

    final kunci = keyword.trim();

    // Server hanya ditanya bila cache belum mencukupi DAN kata kuncinya cukup
    // spesifik. Cache sengaja dibatasi [AppConfig.partCacheLimit] baris, jadi
    // part di luar batas itu memang tidak akan ketemu tanpa bertanya ke sana.
    final perluServer = local.length < limit &&
        (local.isEmpty || kunci.length >= minKeywordForServer);
    if (!perluServer) return local;
    if (kunci.isEmpty && local.isNotEmpty) return local;

    try {
      final remote = await api.fetchParts(
        keyword: kunci.isEmpty ? null : kunci,
        areas: areas,
        limit: AppConfig.partSearchLimit,
      );
      if (remote.isNotEmpty) {
        await dao.upsertAll(remote);
        final segar = await dao.search(
          keyword,
          limit: limit,
          offset: offset,
          areas: areas,
        );
        return segar;
      }
    } catch (_) {
      // Offline: biarkan hasil lokal - UI menampilkan apa adanya.
    }
    return local;
  }

  /// Semua area yang dikenal master part (untuk pilihan izin & event).
  Future<List<String>> availableAreas() => dao.distinctAreas();

  /// Tarik seluruh master part dari server dan timpa cache lokal.
  Future<int> refreshCache({
    bool force = false,
    List<String> areas = const [],
  }) async {
    if (!force && !await dao.isStale(AppConfig.partCacheTtl)) {
      return dao.count();
    }
    // Master berisi 6.508 baris; menariknya per area kerja jauh lebih ringan
    // untuk handheld, dan operator memang hanya boleh melihat areanya.
    // Dibatasi [AppConfig.partCacheLimit] - satu balasan sebesar seluruh
    // master membuat handheld tertahan lama, sedangkan part di luar batas itu
    // tetap bisa ditemukan lewat pencarian ke server.
    final remote = await api.fetchParts(
      areas: areas,
      limit: AppConfig.partCacheLimit,
    );
    if (remote.isNotEmpty) {
      await dao.replaceAll(remote);
      await prefs.setLastSyncAt(DateTime.now());
    }
    return remote.length;
  }

  /// Refresh diam-diam (dipanggil saat halaman dibuka, error diabaikan).
  Future<void> refreshIfStale({List<String> areas = const []}) async {
    try {
      await refreshCache(areas: areas);
    } catch (_) {
      // biarkan - aplikasi tetap memakai cache lama
    }
  }

  Future<PartCacheInfo> cacheInfo() async => PartCacheInfo(
        count: await dao.count(),
        lastSyncedAt: await dao.lastSyncedAt(),
      );

}
