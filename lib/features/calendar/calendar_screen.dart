import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../database/app_database.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/widgets/global_search_button.dart';
import '../cases/case_detail_screen.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  Future<Case?> _caseForId(AppDatabase db, int id) async {
    final cases = await db.select(db.cases).get();
    for (final item in cases) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _openCase(BuildContext context, WidgetRef ref, int caseId) async {
    final db = ref.read(databaseProvider);
    final item = await _caseForId(db, caseId);
    if (item == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرونده مرتبط پیدا نشد.')));
      }
      return;
    }
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: item)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('تقویم و برنامه'), actions: const [GlobalSearchButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.calendar_month),
              title: Text('تقویم کاری کوروش‌یار'),
              subtitle: Text('مهلت‌ها، جلسات پرونده و کارهای دارای تاریخ در یک نمای زمانی.'),
            ),
          ),
          const SizedBox(height: 12),
          const Text('جلسات پرونده', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          StreamBuilder<List<CaseTimelineEvent>>(
            stream: db.select(db.caseTimelineEvents).watch(),
            builder: (context, snapshot) {
              final sessions = List<CaseTimelineEvent>.of(snapshot.data ?? const <CaseTimelineEvent>[])
                  .where((e) => e.eventType == 'جلسه')
                  .toList()
                ..sort((a, b) => _dateOnly(a.eventDate).compareTo(_dateOnly(b.eventDate)));

              if (sessions.isEmpty) {
                return const Card(child: ListTile(title: Text('جلسه‌ای در خط زمان پرونده‌ها ثبت نشده است.')));
              }

              return Column(
                children: sessions.map((e) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.groups),
                      title: Text(e.title),
                      subtitle: Text('${formatPersianLongDate(e.eventDate)} | ${e.description ?? 'جلسه پرونده'}'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _openCase(context, ref, e.caseId),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('مهلت‌ها بر اساس تاریخ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          StreamBuilder<List<Deadline>>(
            stream: db.select(db.deadlines).watch(),
            builder: (context, snapshot) {
              final deadlines = List<Deadline>.of(snapshot.data ?? const <Deadline>[]);
              deadlines.sort((a, b) => a.dueDate.compareTo(b.dueDate));

              if (deadlines.isEmpty) {
                return const Card(child: ListTile(title: Text('مهلتی ثبت نشده است.')));
              }

              return Column(
                children: deadlines.map((d) {
                  return Card(
                    child: ListTile(
                      leading: Icon(d.isDone ? Icons.check_circle : Icons.warning_amber),
                      title: Text(d.title),
                      subtitle: Text('${formatPersianLongDate(d.dueDate)} | ${deadlineStatusText(d.dueDate)}'),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('کارهای دارای تاریخ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          StreamBuilder<List<Task>>(
            stream: db.select(db.tasks).watch(),
            builder: (context, snapshot) {
              final tasks = List<Task>.of(snapshot.data ?? const <Task>[])
                  .where((t) => t.dueDate != null)
                  .toList()
                ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

              if (tasks.isEmpty) {
                return const Card(child: ListTile(title: Text('کار دارای تاریخ ثبت نشده است.')));
              }

              return Column(
                children: tasks.map((t) {
                  return Card(
                    child: ListTile(
                      leading: Icon(t.isDone ? Icons.check_circle : Icons.radio_button_unchecked),
                      title: Text(t.title),
                      subtitle: Text('اولویت: ${t.priority} | ${formatPersianLongDate(t.dueDate!)}'),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
