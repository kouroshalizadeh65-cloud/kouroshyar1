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
  final match = RegExp(r'(?:ساعت\s*)?(\d{1,2})(?::(\d{1,2}))?').firstMatch(text);
  if (match == null) return null;

  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;

  if (hour == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }

  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String formatKouroshDateTime(DateTime date, String? time) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  if (time == null) return '$y/$m/$d';
  return '$y/$m/$d ساعت $time';
}
