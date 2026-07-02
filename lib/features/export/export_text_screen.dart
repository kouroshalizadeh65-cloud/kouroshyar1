import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';

class ExportTextScreen extends ConsumerStatefulWidget {
  const ExportTextScreen({super.key});

  @override
  ConsumerState<ExportTextScreen> createState() => _ExportTextScreenState();
}

class _ExportTextScreenState extends ConsumerState<ExportTextScreen> {
  String output = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خروجی متنی گزارش')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.description),
            label: const Text('ساخت گزارش قابل کپی'),
          ),
          const SizedBox(height: 16),
          if (output.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(output),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final db = ref.read(databaseProvider);
    final cases = await db.select(db.cases).get();
    final tasks = await db.select(db.tasks).get();
    final deadlines = await db.select(db.deadlines).get();
    final finance = await db.select(db.financeItems).get();
    final legalTexts = await db.select(db.legalTexts).get();

    final openTasks = tasks.where((t) => !t.isDone).toList();
    final openDeadlines = deadlines.where((d) => !d.isDone).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final income = finance.where((f) => f.type == 'درآمد').fold<double>(0, (s, f) => s + f.amount);
    final expense = finance.where((f) => f.type == 'هزینه').fold<double>(0, (s, f) => s + f.amount);

    final buffer = StringBuffer();
    buffer.writeln('گزارش کوروش‌یار');
    buffer.writeln('تاریخ تولید: ${formatPersianLongDate(DateTime.now())}');
    buffer.writeln('------------------------------');
    buffer.writeln('پرونده‌ها: ${cases.length}');
    buffer.writeln('کارهای باز: ${openTasks.length}');
    buffer.writeln('مهلت‌های باز: ${openDeadlines.length}');
    buffer.writeln('متون حقوقی: ${legalTexts.length}');
    buffer.writeln('درآمد: ${income.toStringAsFixed(0)} تومان');
    buffer.writeln('هزینه: ${expense.toStringAsFixed(0)} تومان');
    buffer.writeln('مانده: ${(income - expense).toStringAsFixed(0)} تومان');
    buffer.writeln('');

    buffer.writeln('کارهای باز:');
    if (openTasks.isEmpty) {
      buffer.writeln('- موردی ثبت نشده است.');
    } else {
      for (final t in openTasks) {
        buffer.writeln('- ${t.title} | اولویت: ${t.priority}');
      }
    }

    buffer.writeln('');
    buffer.writeln('مهلت‌های نزدیک:');
    final near = openDeadlines.where((d) => daysUntil(d.dueDate) <= 7).toList();
    if (near.isEmpty) {
      buffer.writeln('- موردی ثبت نشده است.');
    } else {
      for (final d in near) {
        buffer.writeln('- ${d.title} | ${formatPersianLongDate(d.dueDate)} | ${deadlineStatusText(d.dueDate)}');
      }
    }

    setState(() => output = buffer.toString());
  }
}
