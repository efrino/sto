import '../local/prefs_store.dart';
import '../local/user_dao.dart';
import '../models/app_user.dart';
import '../remote/api_client.dart';
import '../remote/api_gateway.dart';
import 'device_repository.dart';

class AuthRepository {
  AuthRepository({
    required this.api,
    required this.prefs,
    required this.userDao,
    required this.deviceRepository,
  });

  final ApiGateway api;
  final PrefsStore prefs;
  final UserDao userDao;

  /// Penjaga pemasangan NIK <-> perangkat.
  final DeviceRepository deviceRepository;

  /// Login NIK.
  ///
  /// Mode simulasi: divalidasi ke tabel `users` yang dikelola admin lewat
  /// menu Setting. Mode API: server yang menentukan peran & area, hasilnya
  /// ikut disimpan lokal supaya tetap bisa dipakai saat offline.
  Future<AppUser> login(String nik, {String? password}) async {
    await ensureSeedUsers();

    final input = nik.trim().toUpperCase();

    // ANDROID_ID wajib: server yang memutuskan apakah NIK ini memang
    // terdaftar pada perangkat yang sedang dipakai. Penugasan perangkat
    // dilakukan admin lewat register/user-update, bukan oleh login.
    final identitas = await deviceRepository.identity();

    final dariServer = await api.login(
      input,
      password: password,
      androidId: identitas.deviceId,
    );

    // Hak akses datang dari server apa adanya. Sebelumnya izin lokal yang
    // dipertahankan - itu benar saat server belum menyimpannya, tapi sekarang
    // membuat perubahan izin oleh admin tidak pernah sampai ke perangkat
    // operator yang bersangkutan.
    final remote = dariServer;

    await userDao.save(remote);

    // Pemasangan sudah diperiksa server (`login` menolak NIK yang bukan milik
    // perangkat ini). Di sini catatan lokalnya tinggal disamakan - kalau
    // penjaga lokal ikut menghakimi, aplikasi yang baru dipasang ulang akan
    // menolak NIK yang sebenarnya sah karena catatannya masih kosong.
    await deviceRepository.rekamLoginServer(remote);

    await _persist(remote);
    return remote;
  }

  /// Menarik ulang identitas user yang sedang login dari server.
  ///
  /// Dipakai supaya perubahan izin oleh admin langsung terasa tanpa perlu
  /// login ulang. `login` dipakai karena itu satu-satunya endpoint yang
  /// mengembalikan "akun saya" untuk operator - isinya hanya pembacaan, dan
  /// sekaligus memeriksa ulang pemasangan perangkat.
  ///
  /// Mengembalikan null bila tidak ada sesi; melempar bila server menolak
  /// (mis. pemasangan dicabut) supaya pemanggil bisa mengeluarkan user.
  Future<AppUser?> refreshSession() async {
    final cached = await prefs.readUser();
    if (cached == null) return null;
    final identitas = await deviceRepository.identity();
    final segar = await api.login(cached.nik, androidId: identitas.deviceId);

    await userDao.save(segar);
    await _persist(segar.copyWith(token: cached.token));
    return segar;
  }

  Future<void> _persist(AppUser user) async {
    await prefs.saveUser(user);
    api.authToken = user.token;
  }

  /// Sesi tersimpan disegarkan dengan data user terbaru, sehingga perubahan
  /// peran/area oleh admin langsung berlaku tanpa perlu login ulang.
  Future<AppUser?> restoreSession() async {
    final cached = await prefs.readUser();
    if (cached == null) return null;

    // Perangkat yang naik versi dari aplikasi lama punya sesi tersimpan tetapi
    // tabel user masih kosong - semai dulu supaya peran/areanya benar.
    await ensureSeedUsers();

    api.authToken = cached.token;
    final fresh = await userDao.findByNik(cached.nik);
    if (fresh == null) return cached;
    if (!fresh.active) {
      await logout();
      return null;
    }

    final merged = fresh.copyWith(token: cached.token);

    // Pemasangan bisa dicabut admin saat aplikasi tidak dipakai. Keputusan itu
    // milik server: sesi tersimpan dibiarkan, dan pencabutannya terasa pada
    // login berikutnya - juga pada setiap panggilan yang ditolak server.

    await prefs.saveUser(merged);
    return merged;
  }

  Future<void> logout() async {
    await prefs.clearUser();
    api.authToken = null;
  }

  /// Dulu menyemai akun contoh untuk mode simulasi. Akun sekarang datang
  /// dari server - menyemai NIK palsu hanya melahirkan akun yang gagal login
  /// begitu ditekan - jadi tinggal titik masuk kosong bagi pemanggil lama.
  Future<void> ensureSeedUsers() async {}
}
