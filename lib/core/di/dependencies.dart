import 'dart:io';

import '../../data/local/app_database.dart';
import '../../data/local/outbox_dao.dart';
import '../../data/local/count_dao.dart';
import '../../data/local/device_dao.dart';
import '../../data/local/event_dao.dart';
import '../../data/local/part_dao.dart';
import '../../data/local/prefs_store.dart';
import '../../data/local/tag_dao.dart';
import '../../data/local/user_dao.dart';
import '../../data/remote/api_gateway.dart';
import '../../data/remote/mock_sto_api.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/cancel_repository.dart';
import '../../data/repositories/count_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/demo_seeder.dart';
import '../../data/repositories/part_repository.dart';
import '../../data/repositories/pembersih_data_contoh.dart';
import '../../data/repositories/sync_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../../services/device/device_identity.dart';
import '../../services/feedback/sound_service.dart';
import '../../services/printer/bluetooth_printer_service.dart';
import '../../services/printer/mock_printer_service.dart';
import '../../services/printer/vendor_printer_service.dart';
import '../../services/printer/printer_service.dart';
import '../../services/sequence/tag_sequence_service.dart';

/// Perakitan dependensi aplikasi (tanpa package DI - cukup sekali di main).
/// Memilih jalur printer untuk perangkat sungguhan.
///
/// Jalur yang dipakai adalah Bluetooth ke printer internal (InnerPrinter,
/// alamat [BluetoothPrinterService.builtInAddress] = 00:11:22:33:44:55) -
/// jalur yang sejak awal terbukti mencetak di handheld ini.
///
/// Jalur service pabrikan ([VendorPrinterService]) sudah disiapkan lengkap
/// tetapi TIDAK dipakai: di unit ini service-nya menolak permintaan sambung,
/// tanda susunan AIDL-nya berbeda dari yang bisa dibaca dari APK-nya yang
/// sudah di-obfuscate. Begitu pabrikan mengirim berkas AIDL resminya, cukup
/// timpa `PrinterInterface.aidl` lalu kembalikan pemilihan di sini.
Future<PrinterService> _printerPerangkat() async => BluetoothPrinterService();

/// Jalur cadangan bila jalur utama menolak saat mencetak.
///
/// Null selama jalur utama sudah Bluetooth - tidak ada jalur lain di
/// belakangnya, dan kegagalan cetak memang harus dilempar apa adanya supaya
/// tag tidak pernah ditandai sudah dicetak.
PrinterService Function()? _printerCadangan(PrinterService utama) =>
    utama is VendorPrinterService ? BluetoothPrinterService.new : null;

class AppDependencies {
  AppDependencies._({
    required this.prefs,
    required this.database,
    required this.api,
    required this.partDao,
    required this.tagDao,
    required this.outboxDao,
    required this.userDao,
    required this.eventDao,
    required this.countDao,
    required this.deviceRepository,
    required this.authRepository,
    required this.partRepository,
    required this.tagRepository,
    required this.syncRepository,
    required this.adminRepository,
    required this.countRepository,
    required this.cancelRepository,
    required this.printerService,
    required this.printerFallback,
    required this.sound,
    required this.demoSeeder,
  });

  final PrefsStore prefs;
  final AppDatabase database;
  final ApiGateway api;
  final PartDao partDao;
  final TagDao tagDao;
  final OutboxDao outboxDao;
  final UserDao userDao;
  final EventDao eventDao;
  final CountDao countDao;
  final DeviceRepository deviceRepository;
  final AuthRepository authRepository;
  final PartRepository partRepository;
  final TagRepository tagRepository;
  final SyncRepository syncRepository;
  final AdminRepository adminRepository;
  final CountRepository countRepository;
  final CancelRepository cancelRepository;
  final PrinterService printerService;

  /// Jalur printer pengganti bila jalur pabrikan menolak (null bila tidak ada).
  final PrinterService Function()? printerFallback;
  final SoundService sound;

  /// Pengisi data contoh selama API belum tersedia.
  final DemoSeeder demoSeeder;

  static Future<AppDependencies> bootstrap() async {
    final prefs = PrefsStore.instance;
    final database = AppDatabase.instance;

    final partDao = PartDao(database);
    final tagDao = TagDao(database);
    final outboxDao = OutboxDao(database);
    final userDao = UserDao(database);
    final eventDao = EventDao(database);
    final countDao = CountDao(database);
    final api = ApiGateway(
      prefs: prefs,
      // Counter mock melanjutkan nomor tertinggi di database lokal, jadi nomor
      // tag tidak mengulang dari 1 setiap aplikasi dibuka.
      mock: MockStoApi(lastUsedSequence: tagDao.lastSequenceForPrefix),
    );

    final deviceRepository = DeviceRepository(
      dao: DeviceDao(database),
      identityService: DeviceIdentityService(prefs),
      api: api,
    );
    await api.reloadSettings();
    await prefs.wipeLegacyNikHistory();

    // Begitu aplikasi memakai API sungguhan, data contoh dibuang: event
    // contoh akan terbaca sebagai event berjalan kedua, dan master part
    // contoh memakai kode area yang tidak dikenal server.
    if (!api.useMock) {
      await PembersihDataContoh(database).bersihkan();
    }

    final sequenceService = TagSequenceService(
      api: api,
      prefs: prefs,
      tagDao: tagDao,
    );

    // Emulator / HP tanpa printer internal otomatis memakai simulasi.
    final simulation = await prefs.printerSimulation(
      fallback: !Platform.isAndroid,
    );

    final partRepository =
        PartRepository(api: api, dao: partDao, prefs: prefs);

    final tagRepository = TagRepository(
      tagDao: tagDao,
      outboxDao: outboxDao,
      sequenceService: sequenceService,
      api: api,
    );
    final countRepository = CountRepository(
      countDao: countDao,
      tagDao: tagDao,
      outboxDao: outboxDao,
      api: api,
    );

    final printer =
        simulation ? MockPrinterService() : await _printerPerangkat();

    return AppDependencies._(
      prefs: prefs,
      database: database,
      api: api,
      partDao: partDao,
      tagDao: tagDao,
      outboxDao: outboxDao,
      userDao: userDao,
      eventDao: eventDao,
      countDao: countDao,
      deviceRepository: deviceRepository,
      authRepository: AuthRepository(
        api: api,
        prefs: prefs,
        userDao: userDao,
        deviceRepository: deviceRepository,
      ),
      adminRepository: AdminRepository(
        userDao: userDao,
        eventDao: eventDao,
        partDao: partDao,
        api: api,
      ),
      partRepository: partRepository,
      tagRepository: tagRepository,
      syncRepository: SyncRepository(
        api: api,
        outboxDao: outboxDao,
        tagDao: tagDao,
        countDao: countDao,
        prefs: prefs,
      ),
      countRepository: countRepository,
      cancelRepository: CancelRepository(
        tagDao: tagDao,
        tagRepository: tagRepository,
        countRepository: countRepository,
        api: api,
      ),
      printerService: printer,
      printerFallback: _printerCadangan(printer),
      sound: SoundService(enabled: await prefs.soundEnabled()),
      demoSeeder: DemoSeeder(
        partRepository: partRepository,
        tagDao: tagDao,
        outboxDao: outboxDao,
      ),
    );
  }
}
