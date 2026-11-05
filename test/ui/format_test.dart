import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/ui/format.dart';

void main() {
  test('times are shown in local time, never raw UTC', () {
    final utc = DateTime.utc(2026, 11, 5, 8, 55);
    final local = utc.toLocal();
    expect(formatClock(utc), '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}');
    expect(formatClock(DateTime(2026, 11, 5, 9, 5)), '09:05');
  });

  test('list stamps: today, yesterday, weekday, then a short date', () {
    final now = DateTime(2026, 11, 5, 12);
    expect(formatListStamp(DateTime(2026, 11, 5, 11, 52), now: now), '11:52');
    expect(formatListStamp(DateTime(2026, 11, 4, 23), now: now), 'Dün');
    expect(formatListStamp(DateTime(2026, 11, 2, 10), now: now), 'Pzt');
    expect(formatListStamp(DateTime(2026, 10, 20, 10), now: now), '20 Eki');
    expect(formatListStamp(DateTime(2025, 10, 20, 10), now: now), '20 Eki 2025');
  });

  test('elapsed time and Turkish dates', () {
    final now = DateTime(2026, 11, 5, 12);
    expect(formatAgo(now.subtract(const Duration(seconds: 20)), now: now), 'şimdi');
    expect(formatAgo(now.subtract(const Duration(minutes: 6)), now: now), '6 dk');
    expect(formatAgo(now.subtract(const Duration(hours: 2)), now: now), '2 sa');
    expect(formatAgo(now.subtract(const Duration(days: 3)), now: now), '3 gün');
    expect(formatDate(DateTime(2026, 11, 5)), '5 Kasım 2026');
    expect(formatDateTime(DateTime(2026, 2, 14, 14)), '14 Şubat 2026, 14:00');
    expect(formatWeekday(DateTime(2026, 11, 5)), 'Perşembe');
  });

  test('counts, prices and phone numbers', () {
    expect(formatCount(1240), '1.240');
    expect(formatCount(10000), '10.000');
    expect(formatCount(999), '999');
    expect(formatPrice(900000), '900.000 ₺');
    expect(formatPrice(1490.5), '1.490,50 ₺');
    expect(formatPhone('905551112233'), '+90 555 111 22 33');
    expect(formatPhone('05551112233'), '0555 111 22 33');
    expect(formatPhone(''), '');
  });

  test('amounts typed the Turkish way', () {
    expect(parseAmount('900.000'), 900000);
    expect(parseAmount('1.490,50'), 1490.5);
    expect(parseAmount('1490,5'), 1490.5);
    expect(parseAmount('1490.5'), 1490.5);
    expect(parseAmount('900000.0'), 900000);
    expect(parseAmount(' 3.490 ₺ '), 3490);
    expect(parseAmount(''), isNull);
    expect(parseAmount('abc'), isNull);
    expect(formatPhone('4915123456789'), '+4915123456789');
  });

  test('initials use Turkish capitals', () {
    expect(initialsOf('Ayşe Yılmaz'), 'AY');
    expect(initialsOf('işletme'), 'İ');
    expect(initialsOf('  '), '?');
    expect(initialsOf('Demo Oto Galeri'), 'DG');
  });
}
