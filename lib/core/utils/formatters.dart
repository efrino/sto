import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final DateFormat _date = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTime = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _full = DateFormat('EEEE, dd MMMM yyyy', 'id');

  static String date(DateTime value) => _date.format(value);

  static String dateTime(DateTime value) => _dateTime.format(value);

  static String time(DateTime value) => _time.format(value);

  /// Format judul tag: 02/09/2026 10.50 AM
  /// AM/PM ditulis manual supaya tidak ikut berubah mengikuti locale perangkat.
  static String dateTimeAmPm(DateTime value) {
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    return '${_date.format(value)} '
        '${hour12.toString().padLeft(2, '0')}.$minute $suffix';
  }

  /// Waktu ringkas untuk daftar: jam saja bila hari ini, "dd/MM HH:mm" bila
  /// bukan. Tanggal lengkap berulang-ulang di tiap baris hanya membuat kartu
  /// penuh tanpa menambah keterangan.
  static String ringkas(DateTime value, {DateTime? sekarang}) {
    final kini = sekarang ?? DateTime.now();
    final hariIni = value.year == kini.year &&
        value.month == kini.month &&
        value.day == kini.day;
    return hariIni ? _time.format(value) : _ringkas.format(value);
  }

  static final DateFormat _ringkas = DateFormat('dd/MM HH:mm');

  static String fullDate(DateTime value) {
    try {
      return _full.format(value);
    } catch (_) {
      return _date.format(value);
    }
  }

  /// "2 menit lalu", "kemarin 14:05", dst - untuk info cache & sinkron.
  static String relative(DateTime? value) {
    if (value == null) return 'belum pernah';
    final diff = DateTime.now().difference(value);
    if (diff.inSeconds < 60) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays == 1) return 'kemarin ${_time.format(value)}';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return _dateTime.format(value);
  }

  static String plural(int count, String singular, [String? plural]) =>
      '$count ${count <= 1 ? singular : (plural ?? singular)}';
}
