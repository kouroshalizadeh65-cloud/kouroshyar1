import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../database/app_database.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';

class DayReviewScreen extends ConsumerWidget {
  const DayReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('پایان روز')),
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

          final doneTasks = tasks.where((t) => t.isDone).length;
          final openTasks = tasks.where((t) => !t.isDone).length;
          final openDeadlines = deadlines.where((d) => !d.isDone).length;
          final expenses = finance.where((f) => f.type == 'هزینه').fold<double>(0, (s, f) => s + f.amount);
          final income = finance.where((f) => f.type == 'درآمد').fold<double>(0, (s, f) => s + f.amount);

          final score = _score(doneTasks, openTasks, openDeadlines);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.nightlight_round),
                  title: Text('مرور امروز - ${formatPersianLongDate(DateTime.now())}'),
                  subtitle: const Text('خلاصه‌ای کوتاه برای بستن روز و آماده شدن برای فردا.'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.score),
                  title: Text('امتیاز امروز: ${toPersianDigits(score)} از ۱۰۰'),
                  subtitle: Text(_scoreMessage(score)),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle),
                  title: const Text('کارها'),
                  subtitle: Text('انجام‌شده: ${toPersianDigits(doneTasks)}\nباقی‌مانده: ${toPersianDigits(openTasks)}'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: const Text('مهلت‌ها'),
                  subtitle: Text('مهلت‌های باز: ${toPersianDigits(openDeadlines)}'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments),
                  title: const Text('مالی'),
                  subtitle: Text('درآمد: ${income.toStringAsFixed(0)} تومان\nهزینه: ${expenses.toStringAsFixed(0)} تومان\nمانده: ${(income - expenses).toStringAsFixed(0)} تومان'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.gavel),
                  title: const Text('پرونده‌ها'),
                  subtitle: Text('پرونده‌های ثبت‌شده: ${toPersianDigits(cases.length)}'),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lightbulb),
                  title: Text('پیشنهاد برای فردا'),
                  subtitle: Text('صبح ابتدا مهلت‌های نزدیک و کارهای با اولویت بالا را بررسی کن.'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _score(int doneTasks, int openTasks, int openDeadlines) {
    var score = 100;
    score -= openTasks * 5;
    score -= openDeadlines * 8;
    score += doneTasks * 2;
    if (score > 100) return 100;
    if (score < 0) return 0;
    return score;
  }

  String _scoreMessage(int score) {
    if (score >= 85) return 'روز خوبی بوده؛ فقط برنامه فردا را سبک مرور کن.';
    if (score >= 60) return 'روز متوسطی بوده؛ چند مورد برای فردا باقی مانده است.';
    return 'چند کار مهم عقب مانده؛ بهتر است فردا را با تمرکز شروع کنی.';
  }
}
