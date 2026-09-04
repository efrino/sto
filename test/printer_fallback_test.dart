import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sto_prep/data/local/prefs_store.dart';
import 'package:sto_prep/data/models/part_item.dart';
import 'package:sto_prep/core/config/app_config.dart';
import 'package:sto_prep/data/models/sto_tag.dart';
import 'package:sto_prep/services/printer/label_document.dart';
import 'package:sto_prep/services/printer/printer_service.dart';
import 'package:sto_prep/state/printer_provider.dart';

/// Printer tiruan yang bisa disuruh menolak - mewakili jalur pabrikan yang
/// susunan AIDL-nya ternyata berbeda dari tebakan aplikasi.
class _PrinterPalsu implements PrinterService {
  _PrinterPalsu({required this.nama, this.menolak = false});

  final String nama;
  final bool menolak;
  int cetak = 0;

  PrinterState _state = PrinterState.disconnected;

  @override
  PrinterState get state => _state;

  @override
  PrinterDevice? get currentDevice =>
      _state == PrinterState.connected ? _perangkat : null;

  PrinterDevice get _perangkat =>
      PrinterDevice(name: nama, address: 'palsu:$nama', isBuiltIn: true);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<PrinterDevice>> discoverDevices() async => [_perangkat];

  @override
  Future<void> connect(PrinterDevice device) async {
    _state = PrinterState.connected;
  }

  @override
  Future<void> disconnect() async {
    _state = PrinterState.disconnected;
  }

  @override
  Future<PaperStatus> paperStatus() async => PaperStatus.ok;

  @override
  Future<void> printDocument(
    LabelDocument document, {
    bool feedAtEnd = true,
    int? feedDots,
    int? gapDots,
  }) async {
    if (menolak) throw PrinterException('$nama menolak.');
    cetak++;
    feedDotsTerakhir = feedDots;
    gapDotsTerakhir = gapDots;
  }

  /// Nilai [gapDots] terakhir yang diterima [printDocument].
  int? gapDotsTerakhir;

  /// Nilai [feedDots] terakhir yang diterima [printDocument].
  int? feedDotsTerakhir;

  @override
  Future<void> testFeed(int dots, {int gapDots = 0}) async {
    ujiTerakhir = dots;
    ujiGapTerakhir = gapDots;
  }

  /// Jarak antar tag yang terakhir diuji.
  int? ujiGapTerakhir;

  /// Jarak yang terakhir diminta lewat [testFeed] - null bila belum pernah.
  int? ujiTerakhir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsStore.instance.resetForTests();
  });

  final tag = StoTag.fromPart(
    part: const PartItem(
      partNumber: '53801-BZ010',
      jobNumber: 'JOB-2601',
      partName: 'PANEL SIDE OUTER RH',
      customer: 'ADM',
      model: 'AYLA',
      area: 'WAREHOUSE 1',
      location: 'RAK A-01',
      partType: 'WIP',
    ),
    tagNo: 'STO260902-000001',
    sequence: 1,
    batchId: 'BATCH-1',
    createdBy: '11223344',
    createdAt: DateTime(2026, 9, 2, 7, 45),
  );


  group('Jarak sobek kertas (dapat diatur operator)', () {
    test('bawaan mengikuti feedAfterTagDots sampai operator mengubahnya',
        () async {
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await provider.bootstrap();

      expect(provider.feedDots, feedAfterTagDots);
    });

    test('tersimpan per perangkat dan terbawa lewat bootstrap berikutnya',
        () async {
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await provider.bootstrap();

      await provider.setFeedDots(48);
      expect(provider.feedDots, 48);

      // Provider baru (mis. setelah aplikasi dibuka ulang) harus membaca
      // nilai yang sama, bukan kembali ke bawaan.
      final ulang =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await ulang.bootstrap();
      expect(ulang.feedDots, 48);
    });

    test('jarak antar tag punya setelan sendiri, terpisah dari jarak akhir',
        () async {
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await provider.bootstrap();

      // Bawaannya: tidak menambah jarak di akhir (printer maju sendiri),
      // tetapi antar tag tetap diberi jarak gunting.
      expect(provider.feedDots, feedAfterTagDots);
      expect(provider.gapDots, gapAntarTagDots);
      expect(provider.gapDots, greaterThan(0));

      await provider.setGapDots(40);
      expect(provider.gapDots, 40);
      expect(provider.feedDots, feedAfterTagDots,
          reason: 'menyetel jarak antar tag tidak boleh mengubah jarak akhir');

      final ulang =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await ulang.bootstrap();
      expect(ulang.gapDots, 40);
    });

    test('dikirim apa adanya ke printDocument saat mencetak tag', () async {
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await provider.refreshDevices();
      await provider.connect(provider.devices.first);
      await provider.setFeedDots(64);
      await provider.setGapDots(24);

      await provider.printTag(tag);

      expect(palsu.feedDotsTerakhir, 64);
      expect(palsu.gapDotsTerakhir, 24);
    });

    test('uji jarak tidak mencetak tag utuh, hanya kirim jarak yang diminta',
        () async {
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await provider.refreshDevices();
      await provider.connect(provider.devices.first);

      await provider.testFeed(40, gapDots: 20);

      expect(palsu.ujiTerakhir, 40);
      expect(palsu.ujiGapTerakhir, 20);
      expect(palsu.cetak, 0, reason: 'uji jarak bukan cetak tag');
    });

    test('NIK setelan jatuh ke sesi tersimpan bila layar belum mengisinya',
        () async {
      // Inilah sebab dua handheld sempat mencetak dengan jarak berbeda:
      // permintaan setelan dikirim tanpa NIK, server menolaknya, dan tiap HT
      // diam-diam bertahan dengan angkanya sendiri.
      SharedPreferences.setMockInitialValues({
        'flutter.active_user':
            '{"nik":"M.9276","name":"M.9276","role":"operator"}',
      });
      PrefsStore.instance.resetForTests();

      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);

      expect(await provider.nikUntukSetelan(), 'M.9276');

      // Yang diisi layar tetap didahulukan.
      provider.nikPembaca = 'E.9948';
      expect(await provider.nikUntukSetelan(), 'E.9948');
    });

    test('tanpa sesi maupun layar, setelan tidak diminta ke server', () async {
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);

      expect(await provider.nikUntukSetelan(), isEmpty);
    });

    test('tanpa gateway API, setelan memakai cache perangkat apa adanya',
        () async {
      // Mode simulasi & test tidak punya server. Printer tetap harus bisa
      // dipakai dengan angka yang terakhir diketahui, bukan gagal memuat.
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);

      await provider.setGapDots(64);
      await provider.muatSetelanServer();

      expect(provider.gapDots, 64);
      expect(provider.setelanDariServer, isFalse,
          reason: 'belum pernah dapat jawaban server');
    });

    test('nilai di luar batas byte ESC/POS dijepit ke 0-255', () async {
      final palsu = _PrinterPalsu(nama: 'printer');
      final provider =
          PrinterProvider(service: palsu, prefs: PrefsStore.instance);
      await provider.bootstrap();

      await provider.setFeedDots(999);
      expect(provider.feedDots, 255);

      await provider.setFeedDots(-10);
      expect(provider.feedDots, 0);
    });
  });

  test('printer tersimpan dari jalur pabrikan dibuang saat bootstrap',
      () async {
    final bt = _PrinterPalsu(nama: 'bluetooth');
    SharedPreferences.setMockInitialValues({
      'printer_address': 'vendor:recieptservice',
      'printer_name': 'Printer internal (service pabrikan)',
    });

    // Pastikan nilai tiruannya benar-benar terbaca - kalau tidak, sisa test
    // ini akan lulus tanpa menguji apa pun.
    expect(await PrefsStore.instance.printerAddress(), 'vendor:recieptservice');

    final provider = PrinterProvider(service: bt, prefs: PrefsStore.instance);
    await provider.bootstrap();

    // Alamat pabrikan tidak berarti apa-apa bagi jalur Bluetooth; printer
    // internal harus dicari ulang, bukan dipakai apa adanya.
    expect(provider.selected?.address, isNot('vendor:recieptservice'));
    expect(await PrefsStore.instance.printerAddress(),
        isNot('vendor:recieptservice'));
  });

  test('printer pabrikan yang menolak dialihkan ke jalur cadangan', () async {
    final pabrikan = _PrinterPalsu(nama: 'pabrikan', menolak: true);
    final cadangan = _PrinterPalsu(nama: 'bluetooth');

    final provider = PrinterProvider(
      service: pabrikan,
      prefs: PrefsStore.instance,
      cadangan: () => cadangan,
    );
    await provider.refreshDevices();
    await provider.connect(provider.devices.first);

    await provider.printTag(tag);

    expect(cadangan.cetak, 1, reason: 'tag tercetak lewat jalur cadangan');
    expect(provider.service, same(cadangan));
  });

  test('tanpa cadangan, kegagalan cetak tetap dilempar', () async {
    final pabrikan = _PrinterPalsu(nama: 'pabrikan', menolak: true);

    final provider = PrinterProvider(
      service: pabrikan,
      prefs: PrefsStore.instance,
    );
    await provider.refreshDevices();
    await provider.connect(provider.devices.first);

    // Penting: tanpa lemparan ini, pemanggil akan menandai tag sebagai sudah
    // dicetak padahal kertasnya kosong.
    await expectLater(
      provider.printTag(tag),
      throwsA(isA<PrinterException>()),
    );
  });

  test('cadangan hanya dipakai sekali; gagal lagi tetap dilempar', () async {
    final pabrikan = _PrinterPalsu(nama: 'pabrikan', menolak: true);
    final cadangan = _PrinterPalsu(nama: 'bluetooth', menolak: true);

    final provider = PrinterProvider(
      service: pabrikan,
      prefs: PrefsStore.instance,
      cadangan: () => cadangan,
    );
    await provider.refreshDevices();
    await provider.connect(provider.devices.first);

    await expectLater(
      provider.printTag(tag),
      throwsA(isA<PrinterException>()),
    );
  });
}
