DateTime? parseSimplePersianRelativeDate(String text) {
  final now = DateTime.now();

  if (text.contains('پس‌فردا') || text.contains('پس فردا')) {
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 2));
  }

  if (text.contains('فردا')) {
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  if (text.contains('امروز')) {
    return DateTime(now.year, now.month, now.day);
  }

  return null;
}

String? parseSimpleTime(String text) {
  final match = RegExp(r'(ساعت\s*)?(\d{1,2})([:٫:](\d{1,2}))?').firstMatch(text);
  if (match == null) return null;

  final hour = int.tryParse(match.group(2) ?? '');
  final minute = int.tryParse(match.group(4) ?? '0') ?? 0;

  if (hour == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }

  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
