String detectEntryType(String text) {
  final value = text.trim();

  if (value.contains('جلسه') || value.contains('دادگاه')) return 'جلسه';

  if (value.contains('تومان') ||
      value.contains('هزینه') ||
      value.contains('پرداخت') ||
      value.contains('حق‌الوکاله') ||
      value.contains('درآمد')) {
    return 'مالی';
  }

  if (value.contains('لایحه') ||
      value.contains('دادخواست') ||
      value.contains('شکواییه') ||
      value.contains('اظهارنامه')) {
    return 'حقوقی';
  }

  if (value.contains('تماس') || value.contains('زنگ')) return 'تماس';

  if (value.contains('مهلت') ||
      value.contains('تجدیدنظر') ||
      value.contains('واخواهی') ||
      value.contains('اجرائیه')) {
    return 'مهلت';
  }

  return 'یادداشت';
}
