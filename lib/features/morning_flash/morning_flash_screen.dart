import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../database/app_database.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../kourosh_suggestions/kourosh_suggestion_engine.dart';

class MorningFlashScreen extends ConsumerWidget {
  const MorningFlashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('فلش صبحگاهی')),
      body: FutureBuilder(
        future: Future.wait([
          db.select(db.tasks).get(),
          db.select(db.deadlines).get(),
          db.select(db.financeItems).get(),
          db.select(db.cases).get(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final tasks = snapshot.data![0] as List<Task>;
          final deadlines = snapshot.data![1] as List<Deadline>;
          final finance = snapshot.data![2] as List<FinanceItem>;
          final cases = snapshot.data![3] as List<Case>;

          final openTasks = tasks.where((t) => !t.isDone).toList();
          final personalTasks = openTasks.where((t) => t.caseId == null).toList();
          final officeTasks = openTasks.where((t) => t.caseId != null).toList();

          final suggestions = buildKouroshSuggestions(
            tasks: tasks,
            deadlines: deadlines,
            financeItems: finance,
          );

          final today = DateTime.now();
          final todayOnly = DateTime(today.year, today.month, today.day);
          final nearDeadlines = deadlines.where((d) {
            if (d.isDone) return false;
            final due = DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day);
            return due.difference(todayOnly).inDays <= 7;
          }).toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

          final income = finance.where((f) => f.type == 'درآمد').fold<double>(0, (s, f) => s + f.amount);
          final expenses = finance.where((f) => f.type == 'هزینه').fold<double>(0, (s, f) => s + f.amount);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.wb_sunny),
                  title: Text('صبح بخیر کوروش - ${formatPersianLongDate(DateTime.now())}'),
                  subtitle: const Text('فقط مهم‌ترین چیزهایی که برای شروع روز لازم داری.'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb),
                  title: Text('پیشنهاد کوروش: ${suggestions.first.title}'),
                  subtitle: Text(suggestions.first.message),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.gavel),
                  title: const Text('امور وکالت'),
                  subtitle: Text(officeTasks.isEmpty
                      ? 'فعلاً کار پرونده‌ای باز ثبت نشده است.'
                      : officeTasks.take(3).map((t) => '• ${t.title}').join('\n')),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('کارهای شخصی'),
                  subtitle: Text(personalTasks.isEmpty
                      ? 'فعلاً کار شخصی باز ثبت نشده است.'
                      : personalTasks.take(3).map((t) => '• ${t.title}').join('\n')),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: const Text('مهلت‌های نزدیک'),
                  subtitle: Text(nearDeadlines.isEmpty
                      ? 'مهلت نزدیکی ثبت نشده است.'
                      : nearDeadlines.take(3).map((d) => '• ${d.title} - ${formatPersianLongDate(d.dueDate)}').join('\n')),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments),
                  title: const Text('خلاصه مالی'),
                  subtitle: Text('درآمد: ${toPersianDigits(income.toStringAsFixed(0))} تومان\nهزینه: ${toPersianDigits(expenses.toStringAsFixed(0))} تومان\nمانده: ${toPersianDigits((income - expenses).toStringAsFixed(0))} تومان'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('وضعیت کلی'),
                  subtitle: Text('پرونده‌ها: ${toPersianDigits(cases.length)}\nکارهای باز: ${toPersianDigits(openTasks.length)}\nمهلت‌های نزدیک: ${toPersianDigits(nearDeadlines.length)}'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
