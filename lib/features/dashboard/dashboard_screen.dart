import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('داشبورد مدیریتی')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('خلاصه دفتر', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          StreamBuilder(
            stream: db.select(db.cases).watch(),
            builder: (context, snapshot) {
              final cases = snapshot.data ?? [];
              return _StatCard(
                icon: Icons.gavel,
                title: 'پرونده‌ها',
                value: cases.length.toString(),
                subtitle: 'تعداد پرونده‌های ثبت‌شده',
              );
            },
          ),
          StreamBuilder(
            stream: db.select(db.tasks).watch(),
            builder: (context, snapshot) {
              final tasks = snapshot.data ?? [];
              final open = tasks.where((t) => !t.isDone).length;
              final done = tasks.where((t) => t.isDone).length;
              return _StatCard(
                icon: Icons.check_circle_outline,
                title: 'کارها',
                value: open.toString(),
                subtitle: 'باز: $open | انجام‌شده: $done',
              );
            },
          ),
          StreamBuilder(
            stream: db.select(db.deadlines).watch(),
            builder: (context, snapshot) {
              final deadlines = (snapshot.data ?? []).where((d) => !d.isDone).toList();
              final urgent = deadlines.where((d) => daysUntil(d.dueDate) <= 3).length;
              final near = deadlines.where((d) => daysUntil(d.dueDate) <= 7).length;
              return _StatCard(
                icon: Icons.warning_amber,
                title: 'مهلت‌ها',
                value: urgent.toString(),
                subtitle: 'فوری تا سه روز: $urgent | نزدیک تا هفت روز: $near',
                danger: urgent > 0,
              );
            },
          ),
          StreamBuilder(
            stream: db.select(db.financeItems).watch(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              final income = items.where((i) => i.type == 'درآمد').fold<double>(0, (s, i) => s + i.amount);
              final expense = items.where((i) => i.type == 'هزینه').fold<double>(0, (s, i) => s + i.amount);
              return _StatCard(
                icon: Icons.payments,
                title: 'مالی',
                value: (income - expense).toStringAsFixed(0),
                subtitle: 'درآمد: ${income.toStringAsFixed(0)} | هزینه: ${expense.toStringAsFixed(0)} تومان',
              );
            },
          ),
          StreamBuilder(
            stream: db.select(db.legalTexts).watch(),
            builder: (context, snapshot) {
              final texts = snapshot.data ?? [];
              final top = texts.where((t) => (t.qualityScore ?? 0) >= 4).length;
              return _StatCard(
                icon: Icons.menu_book,
                title: 'بانک متون',
                value: texts.length.toString(),
                subtitle: 'متون با امتیاز بالا: $top',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool danger;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: danger ? Colors.redAccent : null,
          child: Icon(icon, color: danger ? Colors.white : null),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
