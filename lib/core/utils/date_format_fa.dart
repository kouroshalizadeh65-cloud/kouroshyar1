import 'persian_numbers.dart';

class JalaliDate {
  const JalaliDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;
}

const List<String> _jalaliMonthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

String _weekDayName(DateTime date) {
  switch (date.weekday) {
    case DateTime.saturday:
      return 'شنبه';
    case DateTime.sunday:
      return 'یکشنبه';
    case DateTime.monday:
      return 'دوشنبه';
    case DateTime.tuesday:
      return 'سه‌شنبه';
    case DateTime.wednesday:
      return 'چهارشنبه';
    case DateTime.thursday:
      return 'پنجشنبه';
    case DateTime.friday:
      return 'جمعه';
  }
  return '';
}

String _toLatinDigits(String value) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var out = value;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return out;
}

JalaliDate gregorianToJalali(DateTime date) {
  final gy = date.year - 1600;
  final gm = date.month - 1;
  final gd = date.day - 1;

  const gDaysInMonth = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  const jDaysInMonth = <int>[31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29];

  var gDayNo = 365 * gy + ((gy + 3) ~/ 4) - ((gy + 99) ~/ 100) + ((gy + 399) ~/ 400);

  for (var i = 0; i < gm; ++i) {
    gDayNo += gDaysInMonth[i];
  }

  if (gm > 1 && ((date.year % 4 == 0 && date.year % 100 != 0) || (date.year % 400 == 0))) {
    gDayNo++;
  }

  gDayNo += gd;

  var jDayNo = gDayNo - 79;

  final jNp = jDayNo ~/ 12053;
  jDayNo %= 12053;

  var jy = 979 + 33 * jNp + 4 * (jDayNo ~/ 1461);
  jDayNo %= 1461;

  if (jDayNo >= 366) {
    jy += (jDayNo - 1) ~/ 365;
    jDayNo = (jDayNo - 1) % 365;
  }

  var jm = 0;
  while (jm < 11 && jDayNo >= jDaysInMonth[jm]) {
    jDayNo -= jDaysInMonth[jm];
    jm++;
  }

  return JalaliDate(jy, jm + 1, jDayNo + 1);
}

DateTime jalaliToGregorian(int jy, int jm, int jd) {
  jy -= 979;
  jm -= 1;
  jd -= 1;

  const gDaysInMonth = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  const jDaysInMonth = <int>[31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29];

  var jDayNo = 365 * jy + (jy ~/ 33) * 8 + ((jy % 33 + 3) ~/ 4);
  for (var i = 0; i < jm; ++i) {
    jDayNo += jDaysInMonth[i];
  }
  jDayNo += jd;

  var gDayNo = jDayNo + 79;
  var gy = 1600 + 400 * (gDayNo ~/ 146097);
  gDayNo %= 146097;

  var leap = true;
  if (gDayNo >= 36525) {
    gDayNo--;
    gy += 100 * (gDayNo ~/ 36524);
    gDayNo %= 36524;

    if (gDayNo >= 365) {
      gDayNo++;
    } else {
      leap = false;
    }
  }

  gy += 4 * (gDayNo ~/ 1461);
  gDayNo %= 1461;

  if (gDayNo >= 366) {
    leap = false;
    gDayNo--;
    gy += gDayNo ~/ 365;
    gDayNo %= 365;
  }

  var gm = 0;
  while (gm < 11 && gDayNo >= gDaysInMonth[gm] + ((gm == 1 && leap) ? 1 : 0)) {
    gDayNo -= gDaysInMonth[gm] + ((gm == 1 && leap) ? 1 : 0);
    gm++;
  }

  return DateTime(gy, gm + 1, gDayNo + 1);
}

DateTime? parsePersianDateInput(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  final today = DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  if (raw.contains('پس‌فردا') || raw.contains('پس فردا')) return base.add(const Duration(days: 2));
  if (raw.contains('فردا')) return base.add(const Duration(days: 1));
  if (raw.contains('امروز')) return base;

  final normalized = _toLatinDigits(raw).replaceAll('-', '/').replaceAll('.', '/');
  final numeric = RegExp(r'(\d{4})\s*/\s*(\d{1,2})\s*/\s*(\d{1,2})').firstMatch(normalized);
  if (numeric != null) {
    final y = int.tryParse(numeric.group(1)!);
    final m = int.tryParse(numeric.group(2)!);
    final d = int.tryParse(numeric.group(3)!);
    if (y == null || m == null || d == null) return null;
    if (y >= 1300 && y <= 1600 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      return jalaliToGregorian(y, m, d);
    }
    if (y >= 1900 && y <= 2200 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      return DateTime(y, m, d);
    }
  }

  for (var i = 0; i < _jalaliMonthNames.length; i++) {
    final monthName = _jalaliMonthNames[i];
    if (!raw.contains(monthName)) continue;
    final dayMatch = RegExp(r'(\d{1,2})').firstMatch(_toLatinDigits(raw));
    final yearMatch = RegExp(r'(1[34]\d{2})').firstMatch(_toLatinDigits(raw));
    final day = dayMatch == null ? null : int.tryParse(dayMatch.group(1)!);
    final year = yearMatch == null ? gregorianToJalali(base).year : int.tryParse(yearMatch.group(1)!);
    if (day != null && year != null) {
      return jalaliToGregorian(year, i + 1, day);
    }
  }

  return null;
}

String formatSimpleDate(DateTime date) {
  final jalali = gregorianToJalali(date);
  final y = jalali.year.toString().padLeft(4, '0');
  final m = jalali.month.toString().padLeft(2, '0');
  final d = jalali.day.toString().padLeft(2, '0');
  return toPersianDigits('$y/$m/$d');
}

String formatPersianLongDate(DateTime date) {
  final jalali = gregorianToJalali(date);
  final month = _jalaliMonthNames[jalali.month - 1];
  return '${_weekDayName(date)} ${toPersianDigits(jalali.day.toString())} $month ${toPersianDigits(jalali.year.toString())}';
}

String formatSimpleDateTime(DateTime date) {
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '${formatPersianLongDate(date)} - ${toPersianDigits('$hh:$mm')}';
}

int daysUntil(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  return target.difference(today).inDays;
}

String deadlineStatusText(DateTime date) {
  final d = daysUntil(date);
  if (d < 0) return 'گذشته';
  if (d == 0) return 'امروز';
  if (d == 1) return 'فردا';
  return '${toPersianDigits(d.toString())} روز دیگر';
}
