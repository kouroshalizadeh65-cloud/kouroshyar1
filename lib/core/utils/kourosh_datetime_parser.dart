String normalizeKouroshDigits(String value) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var result = value;
  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return result;
}

DateTime parseKouroshDate(String text) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  if (text.contains('پس‌فردا') || text.contains('پس فردا')) {
    return today.add(const Duration(days: 2));
  }

  if (text.contains('فردا')) {
    return today.add(const Duration(days: 1));
  }

  if (text.contains('امروز')) {
    return today;
  }

  if (text.contains('هفته آینده') || text.contains('هفته بعد')) {
    return today.add(const Duration(days: 7));
  }

  return today;
}

String? parseKouroshTime(String text) {
  final normalized = normalizeKouroshDigits(text)
      .replaceAll('٫', ':')
      .replaceAll('،', ':')
      .replaceAll('：', ':');

  // برای جلوگیری از اشتباه گرفتن شماره پرونده/ماده/مبلغ با ساعت،
  // زمان فقط وقتی پذیرفته می‌شود که کنار آن «ساعت»، دو نقطه، یا نشانه زمانی مثل صبح/عصر آمده باشد.
  final match = RegExp(
    r'(?:ساعت\s*(\d{1,2})(?::(\d{1,2}))?\s*(صبح|عصر|شب|بعدازظهر|ظهر)?)|(?:\b(\d{1,2}):(\d{1,2})\b)|(?:\b(\d{1,2})\s*(صبح|عصر|شب|بعدازظهر|ظهر)\b)',
  ).firstMatch(normalized);
  if (match == null) return null;

  var hour = int.tryParse(match.group(1) ?? match.group(4) ?? match.group(6) ?? '');
  final minute = int.tryParse(match.group(2) ?? match.group(5) ?? '0') ?? 0;
  final marker = match.group(3) ?? match.group(7) ?? '';

  if (hour == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }

  if ((marker.contains('عصر') || marker.contains('شب') || marker.contains('بعدازظهر')) && hour > 0 && hour < 12) {
    hour += 12;
  }

  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

DateTime parseKouroshDateTime(String text) {
  final date = parseKouroshDate(text);
  final time = parseKouroshTime(text);
  if (time == null) return date;
  final parts = time.split(':');
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

String stripKouroshTemporalPhrases(String text) {
  var value = normalizeKouroshDigits(text)
      .replaceAll('‌', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  value = value.replaceAll(
    RegExp(r'ساعت\s*\d{1,2}(?::\d{1,2})?\s*(صبح|عصر|شب|بعدازظهر|ظهر)?'),
    ' ',
  );
  value = value.replaceAll(
    RegExp(r'\d{1,2}(?::\d{1,2})?\s*(صبح|عصر|شب|بعدازظهر|ظهر)'),
    ' ',
  );
  value = value
      .replaceAll('پس فردا', ' ')
      .replaceAll('پس‌فردا', ' ')
      .replaceAll('فردا', ' ')
      .replaceAll('امروز', ' ')
      .replaceAll('هفته آینده', ' ')
      .replaceAll('هفته بعد', ' ');
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String formatKouroshDateTime(DateTime date, String? time) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  final resolvedTime = time ?? (date.hour == 0 && date.minute == 0
      ? null
      : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');
  if (resolvedTime == null) return '$y/$m/$d';
  return '$y/$m/$d ساعت $resolvedTime';
}
