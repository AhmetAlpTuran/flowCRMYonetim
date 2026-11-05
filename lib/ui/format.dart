/// Turkish display formatting for times, money, counts and phone numbers.
///
/// Every function converts to local time first, so a UTC timestamp from the server
/// never shows as the wrong hour.
library;

import 'app_typography.dart';

const _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const _monthsShort = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
const _weekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const _weekdaysShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

String _two(int value) => value.toString().padLeft(2, '0');

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// "14:05" in local time.
String formatClock(DateTime time) {
  final t = time.toLocal();
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// "5 Kasım".
String formatDayMonth(DateTime time) {
  final t = time.toLocal();
  return '${t.day} ${_months[t.month - 1]}';
}

/// "5 Kasım 2026".
String formatDate(DateTime time) {
  final t = time.toLocal();
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// "5 Kasım 2026, 14:05".
String formatDateTime(DateTime time) => '${formatDate(time)}, ${formatClock(time)}';

/// "Perşembe".
String formatWeekday(DateTime time) => _weekdays[time.toLocal().weekday - 1];

/// List timestamp: the time today, "Dün", a weekday this week, else a short date.
String formatListStamp(DateTime time, {DateTime? now}) {
  final t = time.toLocal();
  final today = _day(now?.toLocal() ?? DateTime.now());
  final days = today.difference(_day(t)).inDays;
  if (days <= 0) return formatClock(t);
  if (days == 1) return 'Dün';
  if (days < 7) return _weekdaysShort[t.weekday - 1];
  final short = '${t.day} ${_monthsShort[t.month - 1]}';
  return t.year == today.year ? short : '$short ${t.year}';
}

/// Elapsed time: "şimdi", "6 dk", "2 sa", "3 gün", then a date.
String formatAgo(DateTime time, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inMinutes < 1) return 'şimdi';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} dk';
  if (elapsed.inHours < 24) return '${elapsed.inHours} sa';
  if (elapsed.inDays < 7) return '${elapsed.inDays} gün';
  return formatDayMonth(time);
}

/// "1.240" with Turkish thousands separators.
String formatCount(num value) {
  final negative = value < 0;
  final digits = value.abs().truncate().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buffer';
}

/// "900.000 ₺", or "1.490,50 ₺" when there are kuruş.
String formatPrice(num value) {
  final kurus = ((value.abs() * 100).round() % 100);
  final whole = formatCount(value.isNegative ? -(value.abs().floor()) : value.floor());
  return kurus == 0 ? '$whole ₺' : '$whole,${_two(kurus)} ₺';
}

/// "+90 555 111 22 33" from "905551112233"; other numbers are grouped loosely.
String formatPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('90')) {
    return '+90 ${digits.substring(2, 5)} ${digits.substring(5, 8)} '
        '${digits.substring(8, 10)} ${digits.substring(10)}';
  }
  if (digits.length == 11 && digits.startsWith('0')) {
    return '${digits.substring(0, 4)} ${digits.substring(4, 7)} '
        '${digits.substring(7, 9)} ${digits.substring(9)}';
  }
  if (digits.isEmpty) return raw;
  final groups = <String>[];
  for (var i = 0; i < digits.length; i += 3) {
    groups.add(digits.substring(i, i + 3 > digits.length ? digits.length : i + 3));
  }
  return '+${groups.join(' ')}';
}

/// Up to two initials in Turkish capitals: "Ayşe Yılmaz" → "AY", "işletme" → "İ".
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final letters = words.length == 1 ? words.first.substring(0, 1) : words.first[0] + words.last[0];
  return upperTr(letters);
}
