import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/widgets/global_search_button.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../calendar/calendar_screen.dart';
import '../cases/case_detail_screen.dart';
import '../cases/cases_screen.dart';
import '../deadlines/deadlines_screen.dart';
import '../finance/finance_screen.dart';
import '../reports/reports_screen.dart';
import '../tasks/tasks_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  bool _sameDay(DateTime a, DateTime b) => _dateOnly(a) == _dateOnly(b);

  int _daysUntil(DateTime value) => _dateOnly(value).difference(_dateOnly(DateTime.now())).inDays;

  Future<_HomeData> _load(AppDatabase db) async {
    final results = await Future.wait<Object>([
      db.select(db.cases).get(),
      db.select(db.tasks).get(),
      db.select(db.deadlines).get(),
      db.select(db.financeItems).get(),
      db.select(db.caseTimelineEvents).get(),
      db.select(db.caseDocuments).get(),
    ]);

    final cases = results[0] as List<Case>;
    final tasks = results[1] as List<Task>;
    final deadlines = results[2] as List<Deadline>;
    final finance = results[3] as List<FinanceItem>;
    final timeline = results[4] as List<CaseTimelineEvent>;
    final documents = results[5] as List<CaseDocument>;
    final today = _dateOnly(DateTime.now());

    final todayTasks = tasks.where((e) => !e.isDone && e.dueDate != null && _sameDay(e.dueDate!, today)).toList();
    final overdueTasks = tasks.where((e) => !e.isDone && e.dueDate != null && _dateOnly(e.dueDate!).isBefore(today)).toList();
    final urgentDeadlines = deadlines.where((e) => !e.isDone && _daysUntil(e.dueDate) <= 3).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final todaySessions = timeline.where((e) => e.eventType == 'جلسه' && _sameDay(e.eventDate, today)).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    final todayFinance = finance.where((e) => _sameDay(e.date, today)).toList();
    final noNextActionCases = cases
        .where((e) => e.status != 'مختومه' && (e.nextAction == null || e.nextAction!.trim().isEmpty))
        .toList();
    final activeCases = cases.where((e) => e.status != 'مختومه').toList();

    return _HomeData(
      cases: cases,
      activeCases: activeCases,
      documents: documents,
      todayTasks: todayTasks,
      overdueTasks: overdueTasks,
      urgentDeadlines: urgentDeadlines,
      todaySessions: todaySessions,
      todayFinance: todayFinance,
      noNextActionCases: noNextActionCases,
    );
  }

  Future<Case?> _findCase(AppDatabase db, int id) async {
    final cases = await db.select(db.cases).get();
    for (final item in cases) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _openCase(BuildContext context, WidgetRef ref, int caseId) async {
    final item = await _findCase(ref.read(databaseProvider), caseId);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرونده مرتبط پیدا نشد.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: item)));
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  String _priorityTitle(_HomeData data) {
    if (data.urgentDeadlines.any((e) => _daysUntil(e.dueDate) < 0)) {
      return 'اولویت فوری: بررسی مهلت منقضی‌شده';
    }
    if (data.urgentDeadlines.isNotEmpty) {
      return 'اولویت امروز: پیگیری نزدیک‌ترین مهلت';
    }
    if (data.todaySessions.isNotEmpty) {
      return 'اولویت امروز: آماده‌سازی جلسه';
    }
    if (data.overdueTasks.isNotEmpty) {
      return 'اولویت امروز: بستن کارهای عقب‌افتاده';
    }
    if (data.noNextActionCases.isNotEmpty) {
      return 'اولویت امروز: تعیین اقدام بعدی پرونده‌ها';
    }
    return 'وضعیت امروز آرام است؛ ثبت و مرور را ادامه بده.';
  }

  String _prioritySubtitle(_HomeData data) {
    if (data.urgentDeadlines.isNotEmpty) {
      final item = data.urgentDeadlines.first;
      return '${item.title} — ${formatPersianLongDate(item.dueDate)}';
    }
    if (data.todaySessions.isNotEmpty) return data.todaySessions.first.title;
    if (data.overdueTasks.isNotEmpty) return data.overdueTasks.first.title;
    if (data.noNextActionCases.isNotEmpty) return data.noNextActionCases.first.title;
    return 'مورد فوری ثبت نشده است.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('خانه'),
        actions: const [GlobalSearchButton()],
      ),
      body: FutureBuilder<_HomeData>(
        future: _load(db),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('خانه موقتاً آماده نیست.'),
                    subtitle: Text('در خواندن داده‌ها خطا رخ داد. از بخش وضعیت سلامت برنامه می‌توانی داده‌ها را بررسی کنی.'),
                  ),
                ),
              ],
            );
          }
          final data = snapshot.data ?? _HomeData.empty();
          final incomeToday = data.todayFinance.where((e) => e.type == 'درآمد').fold<double>(0, (sum, item) => sum + item.amount);
          final expenseToday = data.todayFinance.where((e) => e.type == 'هزینه').fold<double>(0, (sum, item) => sum + item.amount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text('سلام، کوروش‌یار آماده است.', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('امروز را از همین‌جا مدیریت کن؛ اولویت‌ها، پرونده‌ها، تقویم و ثبت سریع در دسترس‌اند.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.priority_high),
                  title: Text(_priorityTitle(data), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_prioritySubtitle(data)),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _open(context, const ReportsScreen()),
                ),
              ),
              const SizedBox(height: 8),
              _SectionTitle(title: 'اقدام‌های امروز', action: 'گزارش کامل', onTap: () => _open(context, const ReportsScreen())),
              _ActionCard(
                icon: Icons.warning_amber,
                title: 'مهلت‌های فوری',
                value: data.urgentDeadlines.length,
                subtitle: data.urgentDeadlines.isEmpty ? 'مهلت فوری ثبت نشده است.' : data.urgentDeadlines.first.title,
                danger: data.urgentDeadlines.any((e) => _daysUntil(e.dueDate) <= 0),
                onTap: () => _open(context, const DeadlinesScreen()),
              ),
              _ActionCard(
                icon: Icons.groups,
                title: 'جلسات امروز',
                value: data.todaySessions.length,
                subtitle: data.todaySessions.isEmpty ? 'جلسه‌ای برای امروز ثبت نشده است.' : data.todaySessions.first.title,
                onTap: () {
                  if (data.todaySessions.length == 1) {
                    _openCase(context, ref, data.todaySessions.first.caseId);
                  } else {
                    _open(context, const CalendarScreen());
                  }
                },
              ),
              _ActionCard(
                icon: Icons.task_alt,
                title: 'کارهای امروز',
                value: data.todayTasks.length,
                subtitle: data.todayTasks.isEmpty ? 'کار تاریخ‌دار برای امروز ثبت نشده است.' : data.todayTasks.first.title,
                onTap: () => _open(context, const TasksScreen()),
              ),
              _ActionCard(
                icon: Icons.history,
                title: 'کارهای عقب‌افتاده',
                value: data.overdueTasks.length,
                subtitle: data.overdueTasks.isEmpty ? 'کار عقب‌افتاده‌ای وجود ندارد.' : data.overdueTasks.first.title,
                danger: data.overdueTasks.isNotEmpty,
                onTap: () => _open(context, const TasksScreen()),
              ),
              const SizedBox(height: 8),
              _SectionTitle(title: 'دفتر و پرونده‌ها'),
              _ActionCard(
                icon: Icons.gavel,
                title: 'پرونده‌های فعال',
                value: data.activeCases.length,
                subtitle: data.activeCases.isEmpty ? 'پرونده فعالی ثبت نشده است.' : 'کل پرونده‌ها: ${toPersianDigits(data.cases.length)}',
                onTap: () => _open(context, const CasesScreen()),
              ),
              _ActionCard(
                icon: Icons.flag_outlined,
                title: 'پرونده‌های بدون اقدام بعدی',
                value: data.noNextActionCases.length,
                subtitle: data.noNextActionCases.isEmpty ? 'همه پرونده‌های فعال اقدام بعدی دارند.' : data.noNextActionCases.first.title,
                muted: true,
                onTap: () {
                  if (data.noNextActionCases.length == 1) {
                    _openCase(context, ref, data.noNextActionCases.first.id);
                  } else {
                    _open(context, const CasesScreen());
                  }
                },
              ),
              _ActionCard(
                icon: Icons.description,
                title: 'اسناد پرونده‌ها',
                value: data.documents.length,
                subtitle: data.documents.isEmpty ? 'سندی ثبت نشده است.' : 'برای مشاهده اسناد، وارد بخش بیشتر شو.',
                onTap: () => _open(context, const CasesScreen()),
              ),
              const SizedBox(height: 8),
              _SectionTitle(title: 'مالی امروز'),
              _ActionCard(
                icon: Icons.payments,
                title: 'مالی امروز',
                value: data.todayFinance.length,
                subtitle: 'درآمد: ${toPersianDigits(incomeToday.toStringAsFixed(0))} | هزینه: ${toPersianDigits(expenseToday.toStringAsFixed(0))} تومان',
                onTap: () => _open(context, const FinanceScreen()),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('مسیرهای اصلی', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipButton(label: 'پرونده‌ها', icon: Icons.gavel, onTap: () => _open(context, const CasesScreen())),
                          _ChipButton(label: 'تقویم', icon: Icons.calendar_month, onTap: () => _open(context, const CalendarScreen())),
                          _ChipButton(label: 'کارها', icon: Icons.task_alt, onTap: () => _open(context, const TasksScreen())),
                          _ChipButton(label: 'مهلت‌ها', icon: Icons.alarm, onTap: () => _open(context, const DeadlinesScreen())),
                          _ChipButton(label: 'گزارش‌ها', icon: Icons.bar_chart, onTap: () => _open(context, const ReportsScreen())),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          if (action != null)
            TextButton(onPressed: onTap, child: Text(action!)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final int value;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : muted ? Colors.blueGrey : Theme.of(context).colorScheme.primary;
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(.2), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(toPersianDigits(value), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.cases,
    required this.activeCases,
    required this.documents,
    required this.todayTasks,
    required this.overdueTasks,
    required this.urgentDeadlines,
    required this.todaySessions,
    required this.todayFinance,
    required this.noNextActionCases,
  });

  factory _HomeData.empty() => const _HomeData(
        cases: [],
        activeCases: [],
        documents: [],
        todayTasks: [],
        overdueTasks: [],
        urgentDeadlines: [],
        todaySessions: [],
        todayFinance: [],
        noNextActionCases: [],
      );

  final List<Case> cases;
  final List<Case> activeCases;
  final List<CaseDocument> documents;
  final List<Task> todayTasks;
  final List<Task> overdueTasks;
  final List<Deadline> urgentDeadlines;
  final List<CaseTimelineEvent> todaySessions;
  final List<FinanceItem> todayFinance;
  final List<Case> noNextActionCases;
}
