enum CommandIntentType {
  task,
  session,
  deadline,
  finance,
  search,
  openCase,
  report,
  ai,
  settings,
  unknown,
}

class CommandIntent {
  final CommandIntentType type;
  final String title;
  final String? detail;
  final bool needsOnlineAi;
  final bool needsConfirmation;

  const CommandIntent({
    required this.type,
    required this.title,
    this.detail,
    this.needsOnlineAi = false,
    this.needsConfirmation = false,
  });
}

CommandIntent detectCommandIntent(String input) {
  final text = input.trim();

  if (text.isEmpty) {
    return const CommandIntent(type: CommandIntentType.unknown, title: 'فرمان خالی است.');
  }

  if (text.contains('لایحه') || text.contains('دادخواست') || text.contains('تحلیل') || text.contains('دفاع') || text.contains('قاضی')) {
    return CommandIntent(
      type: CommandIntentType.ai,
      title: 'درخواست هوش مصنوعی',
      detail: text,
      needsOnlineAi: true,
      needsConfirmation: true,
    );
  }

  if (text.contains('گزارش') || text.contains('امروز چه')) {
    return CommandIntent(type: CommandIntentType.report, title: 'نمایش گزارش', detail: text);
  }

  if (text.contains('جلسه') || text.contains('دادگاه') || text.contains('رسیدگی')) {
    return CommandIntent(type: CommandIntentType.session, title: 'ثبت جلسه', detail: text, needsConfirmation: true);
  }

  if (text.contains('هزینه') || text.contains('پرداخت') || text.contains('تومان') || text.contains('درآمد') || text.contains('حق‌الوکاله')) {
    return CommandIntent(type: CommandIntentType.finance, title: 'ثبت مالی', detail: text, needsConfirmation: true);
  }

  if (text.contains('مهلت') || text.contains('اجرائیه') || text.contains('تجدیدنظر') || text.contains('واخواهی') || text.contains('تا فردا')) {
    return CommandIntent(type: CommandIntentType.deadline, title: 'ثبت مهلت', detail: text, needsConfirmation: true);
  }

  if (text.contains('جستجو') || text.contains('پیدا کن')) {
    return CommandIntent(type: CommandIntentType.search, title: 'جستجو', detail: text);
  }

  if (text.contains('باز کن') || text.contains('پرونده')) {
    return CommandIntent(type: CommandIntentType.openCase, title: 'جستجو یا باز کردن پرونده', detail: text);
  }

  if (text.contains('حالت تیره') || text.contains('تنظیمات') || text.contains('اعلان')) {
    return CommandIntent(type: CommandIntentType.settings, title: 'تنظیمات', detail: text, needsConfirmation: true);
  }

  if (text.contains('شخصی') || text.contains('ورزش') || text.contains('خرید') || text.contains('ماشین') || text.contains('خانواده')) {
    return CommandIntent(type: CommandIntentType.task, title: 'ثبت کار شخصی', detail: text, needsConfirmation: true);
  }

  return CommandIntent(type: CommandIntentType.task, title: 'ثبت کار', detail: text, needsConfirmation: true);
}
