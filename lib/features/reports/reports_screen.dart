import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/widgets/global_search_button.dart';
import '../calendar/calendar_screen.dart';
import '../cases/case_detail_screen.dart';
import '../cases/cases_screen.dart';
import '../deadlines/deadlines_screen.dart';
import '../documents/documents_screen.dart';
import '../finance/finance_screen.dart';
import '../tasks/tasks_screen.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<_ReportData> _load(AppDatabase db) async {
    final results = await Future.wait<Object>([
      db.select(db.tasks).get(),
      db.select(db.deadlines).get(),
      db.select(db.cases).get(),
      db.select(db.financeItems).get(),
      db.select(db.caseDocuments).get(),
      db.select(db.caseTimelineEvents).get(),
      db.select(db.casePeople).get(),
    ]);

    return _ReportData(
      tasks: results[0] as List<Task>,
      deadlines: results[1] as List<Deadline>,
      cases: results[2] as List<Case>,
      financeItems: results[3] as List<FinanceItem>,
      documents: results[4] as List<CaseDocument>,
      timelineEvents: results[5] as List<CaseTimelineEvent>,
      people: results[6] as List<CasePerson>,
    );
  }

  String _money(double value) => '${toPersianDigits(value.toStringAsFixed(0))} تومان';

  void _openPage(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openCase(BuildContext context, Case item) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: item)));
  }

  Case? _caseForId(List<Case> cases, int id) {
    for (final item in cases) {
      if (item.id == id) return item;
    }
    return null;
  }

  String _mainRecommendation(_ReportData data) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final nextWeek = today.add(const Duration(days: 7));

    final expiredDeadlines = data.deadlines.where((d) => !d.isDone && _dateOnly(d.dueDate).isBefore(today)).toList();
    if (expiredDeadlines.isNotEmpty) {
      expiredDeadlines.sort((a, b) => a.dueDate.compareTo(b.dueDate));
      return 'اولویت فوری: رسیدگی به مهلت منقضی‌شده «${expiredDeadlines.first.title}». این مورد قبل از کارهای عادی بررسی شود.';
    }

    final todayDeadlines = data.deadlines.where((d) => !d.isDone && _sameDay(d.dueDate, today)).toList();
    if (todayDeadlines.isNotEmpty) {
      return 'اولویت امروز: اقدام درباره «${todayDeadlines.first.title}»؛ این مهلت برای امروز ثبت شده است.';
    }

    final nearDeadlines = data.deadlines.where((d) {
      final date = _dateOnly(d.dueDate);
      return !d.isDone && date.isAfter(today) && !date.isAfter(nextWeek);
    }).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (nearDeadlines.isNotEmpty) {
      return 'اولویت پیشنهادی: آماده‌سازی برای نزدیک‌ترین مهلت؛ «${nearDeadlines.first.title}» در ${deadlineStatusText(nearDeadlines.first.dueDate)}.';
    }

    final overdueTasks = data.tasks.where((t) => !t.isDone && t.dueDate != null && _dateOnly(t.dueDate!).isBefore(today)).toList();
    if (overdueTasks.isNotEmpty) {
      return 'اولویت کاری: ${toPersianDigits(overdueTasks.length)} کار عقب‌افتاده دارید. ابتدا کارهای با اولویت زیاد را تعیین تکلیف کن.';
    }

    final inactiveCases = data.cases.where((c) => c.status != 'مختومه' && (c.nextAction ?? '').trim().isEmpty).toList();
    if (inactiveCases.isNotEmpty) {
      return 'پیشنهاد مدیریتی: برای ${toPersianDigits(inactiveCases.length)} پرونده فعال اقدام بعدی ثبت نشده است؛ این موارد را مرور کن.';
    }

    return 'وضعیت امروز منظم است. بهترین اقدام بعدی: ثبت یا مرور برنامه فردا و تکمیل اسناد پرونده‌های فعال.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final now = DateTime.now();
    final today = _dateOnly(now);
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));

    return Scaffold(
      appBar: AppBar(title: const Text('گزارش‌های تصمیم‌ساز'), actions: const [GlobalSearchButton()]),
      body: FutureBuilder<_ReportData>(
        future: _load(db),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('گزارش‌ها موقتاً آماده نمایش نیستند.'),
                    subtitle: Text('کمی بعد دوباره همین صفحه را باز کنید یا به صفحه قبل برگردید.'),
                  ),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final openTasks = data.tasks.where((t) => !t.isDone).toList();
          final doneTasks = data.tasks.where((t) => t.isDone).toList();
          final overdueTasks = openTasks.where((t) => t.dueDate != null && _dateOnly(t.dueDate!).isBefore(today)).toList();
          final todayTasks = openTasks.where((t) => t.dueDate != null && _sameDay(t.dueDate!, today)).toList();

          final openDeadlines = data.deadlines.where((d) => !d.isDone).toList();
          final expiredDeadlines = openDeadlines.where((d) => _dateOnly(d.dueDate).isBefore(today)).toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
          final todayDeadlines = openDeadlines.where((d) => _sameDay(d.dueDate, today)).toList();
          final nearDeadlines = openDeadlines.where((d) {
            final date = _dateOnly(d.dueDate);
            return date.isAfter(today) && !date.isAfter(nextWeek);
          }).toList()
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

          final activeCases = data.cases.where((c) => c.status != 'مختومه').toList();
          final casesWithoutNextAction = activeCases.where((c) => (c.nextAction ?? '').trim().isEmpty).toList();

          final income = data.financeItems.where((i) => i.type == 'درآمد').fold<double>(0, (sum, item) => sum + item.amount);
          final expense = data.financeItems.where((i) => i.type == 'هزینه').fold<double>(0, (sum, item) => sum + item.amount);
          final todayFinance = data.financeItems.where((i) => _sameDay(i.date, today)).toList();
          final todayIncome = todayFinance.where((i) => i.type == 'درآمد').fold<double>(0, (sum, item) => sum + item.amount);
          final todayExpense = todayFinance.where((i) => i.type == 'هزینه').fold<double>(0, (sum, item) => sum + item.amount);

          final todaySessions = data.timelineEvents.where((e) => e.eventType == 'جلسه' && _sameDay(e.eventDate, today)).toList();
          final tomorrowSessions = data.timelineEvents.where((e) => e.eventType == 'جلسه' && _sameDay(e.eventDate, tomorrow)).toList();
          final nearSessions = data.timelineEvents.where((e) {
            final date = _dateOnly(e.eventDate);
            return e.eventType == 'جلسه' && !date.isBefore(today) && !date.isAfter(nextWeek);
          }).toList()
            ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatPersianLongDate(now), style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(_mainRecommendation(data)),
                      const SizedBox(height: 8),
                      const Text('همه ردیف‌های عددی و گزارشی قابل لمس هستند و به صفحه مرتبط می‌روند.', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              _MetricGrid(items: [
                _MetricItem('کار باز', toPersianDigits(openTasks.length), Icons.task_alt, () => _openPage(context, const TasksScreen())),
                _MetricItem('کار عقب‌افتاده', toPersianDigits(overdueTasks.length), Icons.warning_amber, () => _openPage(context, const TasksScreen())),
                _MetricItem('مهلت فوری', toPersianDigits(expiredDeadlines.length + todayDeadlines.length), Icons.alarm, () => _openPage(context, const DeadlinesScreen())),
                _MetricItem('پرونده فعال', toPersianDigits(activeCases.length), Icons.gavel, () => _openPage(context, const CasesScreen())),
                _MetricItem('جلسه امروز', toPersianDigits(todaySessions.length), Icons.event, () => _openPage(context, const CalendarScreen())),
                _MetricItem('مانده مالی', _money(income - expense), Icons.account_balance_wallet, () => _openPage(context, const FinanceScreen())),
              ]),
              _ReportSection(
                title: 'اولویت‌های امروز',
                icon: Icons.priority_high,
                emptyText: 'برای امروز مورد فوری ثبت نشده است.',
                items: [
                  ...todayDeadlines.map((d) => _ReportLine('مهلت امروز', d.title, d.deadlineType ?? 'مهلت حقوقی', () => _openPage(context, const DeadlinesScreen()))),
                  ...todayTasks.map((t) => _ReportLine('کار امروز', t.title, 'اولویت: ${t.priority}', () => _openPage(context, const TasksScreen()))),
                  ...todaySessions.map((e) => _ReportLine('جلسه امروز', e.title, formatPersianLongDate(e.eventDate), () {
                        final relatedCase = _caseForId(data.cases, e.caseId);
                        if (relatedCase == null) {
                          _openPage(context, const CalendarScreen());
                        } else {
                          _openCase(context, relatedCase);
                        }
                      })),
                ],
              ),
              _ReportSection(
                title: 'مهلت‌های منقضی‌شده',
                icon: Icons.error_outline,
                emptyText: 'مهلت منقضی‌شده‌ای وجود ندارد.',
                items: expiredDeadlines
                    .map((d) => _ReportLine(d.title, formatPersianLongDate(d.dueDate), d.deadlineType ?? 'مهلت', () => _openPage(context, const DeadlinesScreen())))
                    .toList(),
              ),
              _ReportSection(
                title: 'مهلت‌های ۷ روز آینده',
                icon: Icons.date_range,
                emptyText: 'در ۷ روز آینده مهلت نزدیکی ثبت نشده است.',
                items: nearDeadlines
                    .map((d) => _ReportLine(d.title, formatPersianLongDate(d.dueDate), deadlineStatusText(d.dueDate), () => _openPage(context, const DeadlinesScreen())))
                    .toList(),
              ),
              _ReportSection(
                title: 'جلسات نزدیک',
                icon: Icons.groups,
                emptyText: 'جلسه‌ای برای امروز، فردا یا ۷ روز آینده ثبت نشده است.',
                items: nearSessions
                    .map((e) => _ReportLine(e.title, formatPersianLongDate(e.eventDate), e.description ?? 'جلسه پرونده', () {
                          final relatedCase = _caseForId(data.cases, e.caseId);
                          if (relatedCase == null) {
                            _openPage(context, const CalendarScreen());
                          } else {
                            _openCase(context, relatedCase);
                          }
                        }))
                    .toList(),
                footer: tomorrowSessions.isEmpty ? null : '${toPersianDigits(tomorrowSessions.length)} جلسه برای فردا ثبت شده است.',
              ),
              _ReportSection(
                title: 'پرونده‌های بی‌اقدام',
                icon: Icons.info_outline,
                emptyText: 'همه پرونده‌های فعال اقدام بعدی دارند.',
                muted: true,
                items: casesWithoutNextAction
                    .map((c) => _ReportLine(c.title, c.stage ?? 'مرحله ثبت نشده', 'اقدام بعدی ثبت نشده است.', () => _openCase(context, c)))
                    .toList(),
              ),
              _FinanceReportCard(
                income: income,
                expense: expense,
                todayIncome: todayIncome,
                todayExpense: todayExpense,
                onTap: () => _openPage(context, const FinanceScreen()),
              ),
              _ReportSection(
                title: 'اسناد و اشخاص پرونده',
                icon: Icons.folder_copy,
                emptyText: 'هنوز سند یا شخص پرونده ثبت نشده است.',
                items: [
                  _ReportLine('اسناد ثبت‌شده', toPersianDigits(data.documents.length), 'مدارک و فایل‌های پرونده', () => _openPage(context, const DocumentsScreen())),
                  _ReportLine('اشخاص پرونده', toPersianDigits(data.people.length), 'موکل، طرف مقابل، کارشناس، شاهد و سایر', () => _openPage(context, const CasesScreen())),
                  _ReportLine('رویدادهای خط زمان', toPersianDigits(data.timelineEvents.length), 'وقایع و جلسات پرونده', () => _openPage(context, const CalendarScreen())),
                ],
              ),
              _ReportSection(
                title: 'جمع‌بندی کارها',
                icon: Icons.check_circle_outline,
                emptyText: 'کاری ثبت نشده است.',
                items: [
                  _ReportLine('انجام‌شده', toPersianDigits(doneTasks.length), 'کارهای بسته‌شده', () => _openPage(context, const TasksScreen())),
                  _ReportLine('باقی‌مانده', toPersianDigits(openTasks.length), 'کارهای باز', () => _openPage(context, const TasksScreen())),
                  _ReportLine('امروز', toPersianDigits(todayTasks.length), 'کارهای دارای موعد امروز', () => _openPage(context, const TasksScreen())),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportData {
  const _ReportData({
    required this.tasks,
    required this.deadlines,
    required this.cases,
    required this.financeItems,
    required this.documents,
    required this.timelineEvents,
    required this.people,
  });

  final List<Task> tasks;
  final List<Deadline> deadlines;
  final List<Case> cases;
  final List<FinanceItem> financeItems;
  final List<CaseDocument> documents;
  final List<CaseTimelineEvent> timelineEvents;
  final List<CasePerson> people;
}

class _MetricItem {
  const _MetricItem(this.label, this.value, this.icon, this.onTap);
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});
  final List<_MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: items
          .map((item) => Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: item.onTap,
                  child: ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.label),
                    trailing: const Icon(Icons.chevron_left),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _ReportLine {
  const _ReportLine(this.title, this.value, this.note, this.onTap);
  final String title;
  final String value;
  final String note;
  final VoidCallback onTap;
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.items,
    this.footer,
    this.muted = false,
  });

  final String title;
  final IconData icon;
  final String emptyText;
  final List<_ReportLine> items;
  final String? footer;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final textStyle = muted ? const TextStyle(color: Colors.white60) : null;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: !muted,
        leading: Icon(icon),
        title: Text(title, style: textStyle),
        subtitle: const Text('برای دیدن جزئیات، روی ردیف‌ها بزنید.'),
        children: [
          if (items.isEmpty)
            ListTile(title: Text(emptyText, style: textStyle), leading: const Icon(Icons.info_outline))
          else
            ...items.map((item) => ListTile(
                  leading: const Icon(Icons.chevron_left),
                  title: Text(item.title),
                  subtitle: Text(item.note),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(item.value, textAlign: TextAlign.left, overflow: TextOverflow.ellipsis, maxLines: 2),
                  ),
                  onTap: item.onTap,
                )),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(alignment: Alignment.centerRight, child: Text(footer!)),
            ),
        ],
      ),
    );
  }
}

class _FinanceReportCard extends StatelessWidget {
  const _FinanceReportCard({
    required this.income,
    required this.expense,
    required this.todayIncome,
    required this.todayExpense,
    required this.onTap,
  });

  final double income;
  final double expense;
  final double todayIncome;
  final double todayExpense;
  final VoidCallback onTap;

  String _money(double value) => '${toPersianDigits(value.toStringAsFixed(0))} تومان';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.account_balance_wallet),
                title: Text('گزارش مالی'),
                subtitle: Text('برای مشاهده جزئیات مالی، این کارت را لمس کنید.'),
                trailing: Icon(Icons.chevron_left),
              ),
              const Divider(),
              _MoneyRow('درآمد کل', _money(income)),
              _MoneyRow('هزینه کل', _money(expense)),
              _MoneyRow('مانده کل', _money(income - expense)),
              const SizedBox(height: 8),
              _MoneyRow('درآمد امروز', _money(todayIncome)),
              _MoneyRow('هزینه امروز', _money(todayExpense)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
