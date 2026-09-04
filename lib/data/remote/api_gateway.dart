import '../local/prefs_store.dart';
import '../models/app_user.dart';
import '../models/part_item.dart';
import '../models/print_batch.dart';
import '../models/pengajuan_batal.dart';
import '../models/print_entry.dart';
import '../models/sto_count.dart';
import '../models/chat_message.dart';
import '../models/sto_tag.dart';
import '../models/tag_ok.dart';
import 'api_client.dart';
import 'sto_api.dart';

/// Satu pintu ke API: memilih implementasi mock atau HTTP sesuai setting,
/// sehingga peralihan ke API asli cukup lewat toggle di halaman Setting.
class ApiGateway implements StoApi {
  ApiGateway({
    required PrefsStore prefs,
    ApiClient? client,
    StoApi? mock,
  })  : _prefs = prefs,
        _client = client ?? ApiClient(baseUrlResolver: prefs.baseUrl),
        _mock = mock ?? MockStoApi() {
    _http = HttpStoApi(_client);
  }

  final PrefsStore _prefs;
  final ApiClient _client;
  final StoApi _mock;
  late final StoApi _http;

  bool _useMock = false;

  bool get useMock => _useMock;

  /// Dipanggil sekali saat bootstrap dan setiap kali setting berubah.
  Future<void> reloadSettings() async {
    _useMock = await _prefs.useMockApi();
  }

  void setUseMock(bool value) => _useMock = value;

  StoApi get _api => _useMock ? _mock : _http;

  set authToken(String? token) => _client.authToken = token;

  /// Perangkat yang menurut server terpasang pada user hasil login terakhir.
  /// null saat mode simulasi atau bila user belum dipasangkan.
  Map<String, dynamic>? get perangkatTerpasang =>
      _useMock ? null : (_http as HttpStoApi).perangkatTerpasang;

  @override
  Future<AppUser> login(
    String nik, {
    String? password,
    String? androidId,
  }) =>
      _api.login(nik, password: password, androidId: androidId);

  @override
  Future<List<PartItem>> fetchParts({
    String? keyword,
    DateTime? updatedSince,
    List<String> areas = const [],
    int limit = 1000,
  }) =>
      _api.fetchParts(
        keyword: keyword,
        updatedSince: updatedSince,
        areas: areas,
        limit: limit,
      );

  @override
  Future<Map<String, dynamic>> printTag({
    required String area,
    String? partNumber,
    String? jobNumber,
    int? itemId,
    int? eventId,
    String? nik,
  }) =>
      _api.printTag(
        area: area,
        partNumber: partNumber,
        jobNumber: jobNumber,
        itemId: itemId,
        eventId: eventId,
        nik: nik,
      );

  @override
  Future<SequenceReservation> reserveSequence({
    required int qty,
    required String area,
    required String nik,
  }) =>
      _api.reserveSequence(qty: qty, area: area, nik: nik);

  @override
  Future<void> createBatch(PrintBatch batch, List<StoTag> tags) =>
      _api.createBatch(batch, tags);

  @override
  Future<void> confirmPrint(StoTag tag) => _api.confirmPrint(tag);

  @override
  Future<void> reportPrintFailed(StoTag tag, String message) =>
      _api.reportPrintFailed(tag, message);

  @override
  Future<List<ChatThread>> fetchChatThreads(String nik) =>
      _api.fetchChatThreads(nik);

  @override
  Future<List<ChatMessage>> fetchChatMessages({
    required String nik,
    required String thread,
    int afterId = 0,
    int limit = 50,
  }) =>
      _api.fetchChatMessages(
        nik: nik,
        thread: thread,
        afterId: afterId,
        limit: limit,
      );

  @override
  Future<ChatMessage> sendChat({
    required String nik,
    required String thread,
    required String body,
  }) =>
      _api.sendChat(nik: nik, thread: thread, body: body);

  @override
  Future<void> markChatRead({
    required String nik,
    required String thread,
    required int lastId,
  }) =>
      _api.markChatRead(nik: nik, thread: thread, lastId: lastId);

  @override
  Future<void> muteChat({
    required String nik,
    required String nikUser,
    required int menit,
  }) =>
      _api.muteChat(nik: nik, nikUser: nikUser, menit: menit);

  @override
  Future<TagOk> fetchTagOk(String nik, String idTagOk) =>
      _api.fetchTagOk(nik, idTagOk);

  @override
  Future<TagOk> openTagOk(String nik, String idTagOk) =>
      _api.openTagOk(nik, idTagOk);

  @override
  Future<TagOk> scanTagOk(String nik, String idTagOk, int qty) =>
      _api.scanTagOk(nik, idTagOk, qty);

  @override
  Future<List<TagOk>> fetchTagOkList({
    required String nik,
    bool? terbuka,
    String? keyword,
    String? milik,
    int? batal,
    int limit = 100,
  }) =>
      _api.fetchTagOkList(
        nik: nik,
        terbuka: terbuka,
        keyword: keyword,
        milik: milik,
        batal: batal,
        limit: limit,
      );

  @override
  Future<TagOk> cancelTagOk({
    required String nik,
    required String idTagOk,
    String alasan = '',
    String? keputusan,
  }) =>
      _api.cancelTagOk(
        nik: nik,
        idTagOk: idTagOk,
        alasan: alasan,
        keputusan: keputusan,
      );

  @override
  Future<List<StoCount>> fetchScanHistory({
    String? nik,
    String? team,
    String? area,
    String? keyword,
    DateTime? start,
    DateTime? end,
    int limit = 100,
  }) =>
      _api.fetchScanHistory(
        nik: nik,
        team: team,
        area: area,
        keyword: keyword,
        start: start,
        end: end,
        limit: limit,
      );

  @override
  Future<List<PengajuanBatal>> fetchCancelRequests(
    String adminNik, {
    int limit = 100,
  }) =>
      _api.fetchCancelRequests(adminNik, limit: limit);

  @override
  Future<Map<String, String>> fetchPrinterSetting(String nik) =>
      _api.fetchPrinterSetting(nik);

  @override
  Future<Map<String, String>> savePrinterSetting(
    String adminNik,
    Map<String, Object> setelan,
  ) =>
      _api.savePrinterSetting(adminNik, setelan);

  @override
  Future<PrintHistory> fetchPrintHistory({
    required String nik,
    List<PrintState> statuses = const [],
    String? keyword,
    int limit = 100,
  }) =>
      _api.fetchPrintHistory(
        nik: nik,
        statuses: statuses,
        keyword: keyword,
        limit: limit,
      );

  @override
  Future<void> cancelTag(StoTag tag, String reason) =>
      _api.cancelTag(tag, reason);

  @override
  Future<void> requestCancelTag(StoTag tag, String reason) =>
      _api.requestCancelTag(tag, reason);

  @override
  Future<void> rejectCancelTag(StoTag tag) => _api.rejectCancelTag(tag);

  @override
  Future<Map<String, dynamic>?> fetchTagDetail(String tagNo) =>
      _api.fetchTagDetail(tagNo);

  @override
  Future<void> submitCount(Map<String, dynamic> payload) =>
      _api.submitCount(payload);

  // ------------------------------------------------------ pengelolaan user
  @override
  Future<AppUser> registerUser(
    AppUser user, {
    required String createdBy,
    int? deviceId,
  }) =>
      _api.registerUser(user, createdBy: createdBy, deviceId: deviceId);

  @override
  Future<List<AppUser>> fetchUsers(
    String adminNik, {
    int? deviceId,
    String? keyword,
    int limit = 200,
  }) =>
      _api.fetchUsers(
        adminNik,
        deviceId: deviceId,
        keyword: keyword,
        limit: limit,
      );

  @override
  Future<Map<String, dynamic>> updateUser({
    required String adminNik,
    required String targetNik,
    String? role,
    String? team,
    int? deviceId,
    List<String>? areas,
    List<String>? permissions,
  }) =>
      _api.updateUser(
        adminNik: adminNik,
        targetNik: targetNik,
        role: role,
        team: team,
        deviceId: deviceId,
        areas: areas,
        permissions: permissions,
      );

  @override
  Future<Map<String, dynamic>> deleteUser({
    required String adminNik,
    required String targetNik,
    bool force = false,
  }) =>
      _api.deleteUser(
        adminNik: adminNik,
        targetNik: targetNik,
        force: force,
      );

  // --------------------------------------------------- perangkat & event
  @override
  Future<List<Map<String, dynamic>>> fetchDevices(String adminNik) =>
      _api.fetchDevices(adminNik);

  @override
  Future<Map<String, dynamic>?> fetchDeviceDetail(
    String adminNik, {
    int? deviceId,
    String? androidId,
  }) =>
      _api.fetchDeviceDetail(
        adminNik,
        deviceId: deviceId,
        androidId: androidId,
      );

  @override
  Future<Map<String, dynamic>> createDevice({
    required String adminNik,
    required String name,
    required String androidId,
  }) =>
      _api.createDevice(
        adminNik: adminNik,
        name: name,
        androidId: androidId,
      );

  @override
  Future<Map<String, dynamic>> updateDevice({
    required String adminNik,
    required int deviceId,
    String? name,
    String? androidId,
  }) =>
      _api.updateDevice(
        adminNik: adminNik,
        deviceId: deviceId,
        name: name,
        androidId: androidId,
      );

  @override
  Future<Map<String, dynamic>> deleteDevice({
    required String adminNik,
    required int deviceId,
    bool force = false,
  }) =>
      _api.deleteDevice(
        adminNik: adminNik,
        deviceId: deviceId,
        force: force,
      );

  @override
  Future<List<Map<String, dynamic>>> fetchEvents(String adminNik) =>
      _api.fetchEvents(adminNik);

  @override
  Future<Map<String, dynamic>> createEvent({
    required String adminNik,
    required String name,
    required DateTime start,
    required DateTime end,
    bool berjalan = true,
  }) =>
      _api.createEvent(
        adminNik: adminNik,
        name: name,
        start: start,
        end: end,
        berjalan: berjalan,
      );

  @override
  Future<Map<String, dynamic>> updateEvent({
    required String adminNik,
    required int eventId,
    String? name,
    DateTime? start,
    DateTime? end,
    bool? berjalan,
  }) =>
      _api.updateEvent(
        adminNik: adminNik,
        eventId: eventId,
        name: name,
        start: start,
        end: end,
        berjalan: berjalan,
      );

  @override
  Future<Map<String, dynamic>> deleteEvent({
    required String adminNik,
    required int eventId,
    bool force = false,
  }) =>
      _api.deleteEvent(
        adminNik: adminNik,
        eventId: eventId,
        force: force,
      );
}
