import '../../database/app_database.dart';

class KouroshSuggestion {
  final String title;
  final String message;
  final String level; // فوری، مهم، شخصی، مالی

  const KouroshSuggestion({
    required this.title,
    required this.message,
    required this.level,
  });
}

List<KouroshSuggestion> buildKouroshSuggestions({
  required List<Task> tasks,
  required List<Deadline> deadlines,
  required List<FinanceItem> financeItems,
}) {
  final suggestions = <KouroshSuggestion>[];

  final openDeadlines = deadlines.where((d) => !d.isDone).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final urgentDeadlines = openDeadlines.where((d) {
    final due = DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day);
    return due.difference(today).inDays <= 3;
  }).toList();

  if (urgentDeadlines.isNotEmpty) {
    suggestions.add(
      KouroshSuggestion(
        title: 'مهلت فوری',
        message: 'تعداد ${urgentDeadlines.length} مهلت نزدیک داری. بهتر است یکی‌یکی بررسی شوند.',
        level: 'فوری',
      ),
    );
  }

  final highTasks = tasks.where((t) => !t.isDone && (t.priority == 'خیلی زیاد' || t.priority == 'زیاد')).toList();

  if (highTasks.isNotEmpty) {
    suggestions.add(
      KouroshSuggestion(
        title: 'کارهای مهم',
        message: '${highTasks.length} کار مهم باز است. فقط از مهم‌ترین مورد شروع کن.',
        level: 'مهم',
      ),
    );
  }

  final expenses = financeItems.where((f) => f.type == 'هزینه').fold<double>(0, (s, f) => s + f.amount);
  final income = financeItems.where((f) => f.type == 'درآمد').fold<double>(0, (s, f) => s + f.amount);

  if (expenses > income && financeItems.isNotEmpty) {
    suggestions.add(
      const KouroshSuggestion(
        title: 'وضعیت مالی',
        message: 'هزینه‌های ثبت‌شده از درآمدها بیشتر است. بهتر است دریافت‌ها یا حق‌الوکاله‌ها را بررسی کنی.',
        level: 'مالی',
      ),
    );
  }

  if (suggestions.isEmpty) {
    suggestions.add(
      const KouroshSuggestion(
        title: 'روز خلوت‌تر',
        message: 'فعلاً مورد فوری دیده نمی‌شود. بهترین زمان برای تکمیل بانک متون یا مرتب‌سازی پرونده‌هاست.',
        level: 'پیشنهاد',
      ),
    );
  }

  return suggestions.take(3).toList();
}
