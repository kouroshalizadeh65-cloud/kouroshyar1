import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../database/app_database.dart';
import '../../core/utils/entry_style.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../kourosh_suggestions/kourosh_suggestion_engine.dart';
import '../focus_mode/focus_mode_state.dart';
import '../../core/widgets/global_settings_button.dart';
import '../tasks/tasks_screen.dart';
import '../deadlines/deadlines_screen.dart';
import '../deadlines/personal_deadline_utils.dart';
import '../calendar/calendar_screen.dart';
import '../cases/case_detail_screen.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  int _priorityRank(String priority) {
    switch (priority) {
      case 'فوری':
      case 'خیلی زیاد':
        return 0;
      case 'زیاد':
        return 1;
      case 'متوسط':
        return 2;
      default:
        return 3;
    }
  }


  Future<_TodayDashboardData> _loadDashboard(AppDatabase db) async {
    final results = await Future.wait<Object>([
      db.select(db.tasks).get(),
      db.select(db.deadlines).get(),
      db.select(db.cases).get(),
      db.select(db.caseTimelineEvents).get(),
    ]);
    return _TodayDashboardData(
      tasks: results[0] as List<Task>,
      deadlines: results[1] as List<Deadline>,
      cases: results[2] as List<Case>,
      timelineEvents: results[3] as List<CaseTimelineEvent>,
    );
  }

  Case? _caseForId(List<Case> cases, int id) {
    for (final item in cases) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openCase(BuildContext context, Case item) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: item)));
  }

  void _openTaskTarget(BuildContext context, Task task, List<Case> cases) {
    if (task.caseId == null) {
      _openPage(context, TasksScreen(personalOnly: true, initialTaskId: task.id));
      return;
    }
    final relatedCase = _caseForId(cases, task.caseId!);
    if (relatedCase != null) {
      _openCase(context, relatedCase);
    } else {
      _openPage(context, TasksScreen(initialTaskId: task.id));
    }
  }

  void _openDeadlineTarget(BuildContext context, Deadline deadline) {
    if (deadline.caseId == null) {
      _openPage(context, TasksScreen(personalOnly: true, initialDeadlineId: deadline.id));
      return;
    }
    _openPage(context, const DeadlinesScreen());
  }

  String _deadlineSubtitle(Deadline deadline) {
    if (deadline.caseId == null) {
      final status = personalDeadlineStatus(dueDate: deadline.dueDate, isDone: deadline.isDone);
      return '${formatPersianLongDate(deadline.dueDate)} | ${personalDeadlineStatusLabel(status)} | ${personalDeadlineRemainingLabel(dueDate: deadline.dueDate, isDone: deadline.isDone)}';
    }
    return '${formatPersianLongDate(deadline.dueDate)} | ${deadline.deadlineType ?? 'مهلت پرونده'} | ${deadline.priority}';
  }

  Widget _stableInfoCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }

  Widget _stableErrorCard(String title) => _stableInfoCard(
        icon: Icons.info_outline,
        title: title,
        message: 'در حال بارگذاری دوباره اطلاعات؛ اگر این پیام ماندگار شد، صفحه را دوباره باز کن.',
      );

  void _showDetailsSheet(BuildContext context, String title, List<Widget> children, String emptyText) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TodayDetailsScreen(
          title: title,
          children: children,
          emptyText: emptyText,
        ),
      ),
    );
  }

  String _priorityMessage(_TodayDashboardData data, DateTime today) {
    final nextWeek = today.add(const Duration(days: 7));
    final expired = data.deadlines.where((d) => !d.isDone && _dateOnly(d.dueDate).isBefore(today)).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (expired.isNotEmpty) return 'اولویت فوری: رسیدگی به «${expired.first.title}»؛ این مهلت گذشته است.';

    final todayDeadlines = data.deadlines.where((d) => !d.isDone && _sameDay(d.dueDate, today)).toList();
    if (todayDeadlines.isNotEmpty) return 'اولویت امروز: اقدام درباره «${todayDeadlines.first.title}»؛ موعد آن امروز است.';

    final todaySessions = data.timelineEvents.where((e) => !e.isDone && e.eventType == 'جلسه' && _sameDay(e.eventDate, today)).toList();
    if (todaySessions.isNotEmpty) return 'اولویت زمانی: ${toPersianDigits(todaySessions.length)} جلسه برای امروز ثبت شده است.';

    final near = data.deadlines.where((d) {
      final date = _dateOnly(d.dueDate);
      return !d.isDone && date.isAfter(today) && !date.isAfter(nextWeek);
    }).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (near.isNotEmpty) return 'اولویت پیشنهادی: آماده‌سازی برای «${near.first.title}» که ${deadlineStatusText(near.first.dueDate)} است.';

    final overdueTasks = data.tasks.where((t) => !t.isDone && t.dueDate != null && _dateOnly(t.dueDate!).isBefore(today)).toList();
    if (overdueTasks.isNotEmpty) return '${toPersianDigits(overdueTasks.length)} کار عقب‌افتاده دارید؛ ابتدا کارهای با اولویت زیاد را ببند.';

    return 'برنامه امروز وضعیت آرامی دارد؛ بهترین کار، مرور پرونده‌های فعال و ثبت اقدام بعدی است.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final now = DateTime.now();
    final today = _dateOnly(now);
    final nextWeek = today.add(const Duration(days: 7));

    return Scaffold(
      appBar: AppBar(title: const Text('امروز من'), actions: const [GlobalSettingsButton()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.today),
              title: Text(formatPersianLongDate(now)),
              subtitle: const Text('نمای تصمیم‌ساز امروز؛ کار، مهلت و پرونده‌های نیازمند توجه.'),
            ),
          ),
          if (FocusModeState.enabled)
            Card(
              child: ListTile(
                leading: const Icon(Icons.center_focus_strong),
                title: Text('حالت تمرکز: ${FocusModeState.caseTitle}'),
                subtitle: const Text('ثبت‌های سریع تا حد ممکن به همین پرونده وصل می‌شوند.'),
              ),
            ),
          FutureBuilder<List<UserProfile>>(
            future: db.select(db.userProfiles).get(),
            builder: (context, snapshot) {
              final profiles = snapshot.hasError ? const <UserProfile>[] : (snapshot.data ?? const <UserProfile>[]);
              final name = profiles.isNotEmpty ? (profiles.first.displayName ?? '').trim() : '';
              final greeting = name.isEmpty ? 'سلام، کوروش‌یار آماده است.' : 'سلام $name، کوروش‌یار آماده است.';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.assistant),
                  title: Text(greeting),
                  subtitle: const Text('فقط بگو چه کاری لازم است.'),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<int>(
            stream: db.watchAny(),
            builder: (context, _) {
              return FutureBuilder<_TodayDashboardData>(
                future: _loadDashboard(db),
                builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _stableErrorCard('داشبورد تصمیم روز');
              }
              if (!snapshot.hasData) {
                return _stableInfoCard(
                  icon: Icons.dashboard_customize,
                  title: 'داشبورد تصمیم روز',
                  message: 'در حال آماده‌سازی جمع‌بندی امروز...',
                );
              }

              final data = snapshot.data!;
              final openTasks = data.tasks.where((t) => !t.isDone).toList();
              final overdueTasks = openTasks.where((t) => t.dueDate != null && _dateOnly(t.dueDate!).isBefore(today)).toList();
              final todayTasks = openTasks.where((t) => t.dueDate == null || _sameDay(t.dueDate!, today)).toList();
              final expiredDeadlines = data.deadlines.where((d) => !d.isDone && _dateOnly(d.dueDate).isBefore(today)).toList();
              final todayDeadlines = data.deadlines.where((d) => !d.isDone && _sameDay(d.dueDate, today)).toList();
              final nextDeadlines = data.deadlines.where((d) {
                final date = _dateOnly(d.dueDate);
                return !d.isDone && date.isAfter(today) && !date.isAfter(nextWeek);
              }).toList();
              final todaySessions = data.timelineEvents.where((e) => !e.isDone && e.eventType == 'جلسه' && _sameDay(e.eventDate, today)).toList();
              final casesWithoutNext = data.cases.where((c) => c.status != 'مختومه' && c.status != 'غیرفعال' && (c.nextAction ?? '').trim().isEmpty).toList();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('داشبورد تصمیم روز', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(_priorityMessage(data, today)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetricChip(
                            label: 'کار امروز',
                            value: toPersianDigits(todayTasks.length),
                            icon: Icons.task_alt,
                            onTap: () => _showDetailsSheet(
                              context,
                              'کارهای امروز',
                              todayTasks.map((task) => Card(child: ListTile(
                                leading: const Icon(Icons.task_alt),
                                title: Text(task.title),
                                subtitle: Text('اولویت: ${task.priority}'),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => _openTaskTarget(context, task, data.cases),
                              ))).toList(),
                              'برای امروز کاری ثبت نشده است.',
                            ),
                          ),
                          _MetricChip(
                            label: 'عقب‌افتاده',
                            value: toPersianDigits(overdueTasks.length),
                            icon: Icons.warning_amber,
                            onTap: () => _showDetailsSheet(
                              context,
                              'کارهای عقب‌افتاده',
                              overdueTasks.map((task) => Card(child: ListTile(
                                leading: const Icon(Icons.warning_amber),
                                title: Text(task.title),
                                subtitle: Text('${formatPersianLongDate(task.dueDate!)} | اولویت: ${task.priority}'),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => _openTaskTarget(context, task, data.cases),
                              ))).toList(),
                              'کار عقب‌افتاده‌ای دیده نشد.',
                            ),
                          ),
                          _MetricChip(
                            label: 'مهلت فوری',
                            value: toPersianDigits(expiredDeadlines.length + todayDeadlines.length),
                            icon: Icons.alarm,
                            onTap: () => _showDetailsSheet(
                              context,
                              'مهلت‌های فوری',
                              [...expiredDeadlines, ...todayDeadlines].map((d) => Card(child: ListTile(
                                leading: const Icon(Icons.alarm),
                                title: Text(d.title),
                                subtitle: Text(_deadlineSubtitle(d)),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => _openDeadlineTarget(context, d),
                              ))).toList(),
                              'مهلت فوری ثبت نشده است.',
                            ),
                          ),
                          _MetricChip(
                            label: '۷ روز آینده',
                            value: toPersianDigits(nextDeadlines.length),
                            icon: Icons.date_range,
                            onTap: () => _showDetailsSheet(
                              context,
                              'مهلت‌های ۷ روز آینده',
                              nextDeadlines.map((d) => Card(child: ListTile(
                                leading: const Icon(Icons.date_range),
                                title: Text(d.title),
                                subtitle: Text(_deadlineSubtitle(d)),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => _openDeadlineTarget(context, d),
                              ))).toList(),
                              'مهلت نزدیک در ۷ روز آینده ثبت نشده است.',
                            ),
                          ),
                          _MetricChip(
                            label: 'جلسه امروز',
                            value: toPersianDigits(todaySessions.length),
                            icon: Icons.groups,
                            onTap: () => _showDetailsSheet(
                              context,
                              'جلسات امروز',
                              todaySessions.map((e) => Card(child: ListTile(
                                leading: const Icon(Icons.groups),
                                title: Text(e.title),
                                subtitle: Text('${formatPersianLongDate(e.eventDate)} | ${e.description ?? 'جلسه پرونده'}'),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () {
                                  final relatedCase = _caseForId(data.cases, e.caseId);
                                  if (relatedCase == null) {
                                    _openPage(context, const CalendarScreen());
                                  } else {
                                    _openCase(context, relatedCase);
                                  }
                                },
                              ))).toList(),
                              'برای امروز جلسه‌ای ثبت نشده است.',
                            ),
                          ),
                          _MetricChip(
                            label: 'بی‌اقدام',
                            value: toPersianDigits(casesWithoutNext.length),
                            icon: Icons.info_outline,
                            onTap: () => _showDetailsSheet(
                              context,
                              'پرونده‌های بدون اقدام بعدی',
                              casesWithoutNext.map((c) => Card(child: ListTile(
                                leading: const Icon(Icons.info_outline),
                                title: Text(c.title),
                                subtitle: const Text('اقدام بعدی ثبت نشده است.'),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => _openCase(context, c),
                              ))).toList(),
                              'همه پرونده‌های فعال اقدام بعدی دارند.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<int>(
            stream: db.watchAny(),
            builder: (context, _) {
              return FutureBuilder(
            future: Future.wait([
              db.select(db.tasks).get(),
              db.select(db.deadlines).get(),
            ]),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _stableInfoCard(
                  icon: Icons.lightbulb,
                  title: 'پیشنهاد کوروش‌یار',
                  message: 'برای پیشنهاد امروز هنوز داده کافی آماده نیست.',
                );
              }
              if (!snapshot.hasData) {
                return _stableInfoCard(
                  icon: Icons.lightbulb,
                  title: 'پیشنهاد کوروش‌یار',
                  message: 'در حال بررسی اطلاعات امروز...',
                );
              }

              final tasksForSuggestions = snapshot.data![0] as List<Task>;
              final deadlinesForSuggestions = snapshot.data![1] as List<Deadline>;
              final financeForSuggestions = <FinanceItem>[];

              final suggestions = buildKouroshSuggestions(
                tasks: tasksForSuggestions,
                deadlines: deadlinesForSuggestions,
                financeItems: financeForSuggestions,
              );
              final top = suggestions.isEmpty
                  ? const KouroshSuggestion(
                      title: 'روز خلوت‌تر',
                      message: 'فعلاً مورد فوری دیده نمی‌شود. بهترین زمان برای مرتب‌سازی پرونده‌هاست.',
                      level: 'پیشنهاد',
                    )
                  : suggestions.first;

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb),
                  title: Text('پیشنهاد کوروش‌یار: ${top.title}'),
                  subtitle: Text(top.message),
                ),
              );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Task>>(
            stream: db.select(db.tasks).watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Section(
                  title: '✅ کارهای امروز',
                  emptyText: 'در دریافت کارها خطا رخ داد؛ دوباره تلاش کنید.',
                  children: const [],
                );
              }
              final tasks = List<Task>.of(snapshot.data ?? const <Task>[]);
              final open = tasks.where((t) => !t.isDone).toList();
              final todayTasks = open.where((t) => t.dueDate == null || _sameDay(t.dueDate!, today)).toList()
                ..sort((a, b) => _priorityRank(a.priority).compareTo(_priorityRank(b.priority)));
              final overdueTasks = open.where((t) => t.dueDate != null && _dateOnly(t.dueDate!).isBefore(today)).toList()
                ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: '✅ کارهای امروز',
                    emptyText: 'برای امروز کاری ثبت نشده است.',
                    children: todayTasks.map((task) => ListTile(
                      leading: Checkbox(
                        value: task.isDone,
                        onChanged: (value) async {
                          await db.setTaskDone(task, value ?? false);
                        },
                      ),
                      title: Text(task.title),
                      subtitle: Text('اولویت: ${task.priority}'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _openTaskTarget(context, task, const <Case>[]),
                    )).toList(),
                  ),
                  _Section(
                    title: '⚠️ کارهای عقب‌افتاده',
                    emptyText: 'کار عقب‌افتاده‌ای دیده نشد.',
                    children: overdueTasks.map((task) => ListTile(
                      leading: const Icon(Icons.warning_amber),
                      title: Text(task.title),
                      subtitle: Text('${formatPersianLongDate(task.dueDate!)} | اولویت: ${task.priority}'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _openTaskTarget(context, task, const <Case>[]),
                    )).toList(),
                  ),
                ],
              );
            },
          ),
          StreamBuilder<List<Deadline>>(
            stream: db.select(db.deadlines).watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Section(
                  title: '⏰ مهلت‌ها',
                  emptyText: 'در دریافت مهلت‌ها خطا رخ داد؛ دوباره تلاش کنید.',
                  children: const [],
                );
              }
              final deadlines = List<Deadline>.of(snapshot.data ?? const <Deadline>[]).where((d) => !d.isDone).toList();
              final expired = deadlines.where((d) => _dateOnly(d.dueDate).isBefore(today)).toList()
                ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
              final todayDeadlines = deadlines.where((d) => _sameDay(d.dueDate, today)).toList()
                ..sort((a, b) => a.priority.compareTo(b.priority));
              final nextDeadlines = deadlines.where((d) {
                final date = _dateOnly(d.dueDate);
                return date.isAfter(today) && !date.isAfter(nextWeek);
              }).toList()
                ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: '🚨 مهلت‌های منقضی‌شده',
                    emptyText: 'مهلت منقضی‌شده‌ای ثبت نشده است.',
                    children: expired.map((d) => ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(d.title),
                      subtitle: Text(_deadlineSubtitle(d)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _openDeadlineTarget(context, d),
                    )).toList(),
                  ),
                  _Section(
                    title: '⏰ مهلت‌های امروز',
                    emptyText: 'برای امروز مهلتی ثبت نشده است.',
                    children: todayDeadlines.map((d) => ListTile(
                      leading: const Icon(Icons.alarm),
                      title: Text(d.title),
                      subtitle: Text(_deadlineSubtitle(d)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _openDeadlineTarget(context, d),
                    )).toList(),
                  ),
                  _Section(
                    title: '📅 مهلت‌های ۷ روز آینده',
                    emptyText: 'مهلت نزدیک در ۷ روز آینده ثبت نشده است.',
                    children: nextDeadlines.map((d) => ListTile(
                      leading: const Icon(Icons.event_available),
                      title: Text(d.title),
                      subtitle: Text(_deadlineSubtitle(d)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _openDeadlineTarget(context, d),
                    )).toList(),
                  ),
                ],
              );
            },
          ),
          StreamBuilder<List<Case>>(
            stream: db.select(db.cases).watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Section(
                  title: '⚖️ پرونده‌های بدون اقدام بعدی',
                  emptyText: 'در دریافت پرونده‌ها خطا رخ داد؛ دوباره تلاش کنید.',
                  children: const [],
                  muted: true,
                );
              }
              final cases = List<Case>.of(snapshot.data ?? const <Case>[])
                  .where((c) => c.status != 'مختومه' && c.status != 'غیرفعال' && (c.nextAction ?? '').trim().isEmpty)
                  .toList();
              return _Section(
                title: '⚖️ پرونده‌های بدون اقدام بعدی',
                emptyText: 'همه پرونده‌های فعال اقدام بعدی دارند.',
                muted: true,
                children: cases.map((c) => ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(c.title),
                  subtitle: const Text('اقدام بعدی ثبت نشده است. این فقط یادآوری کم‌رنگ است.'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _openCase(context, c),
                )).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text('📥 ثبت‌های سریع اخیر', style: TextStyle(fontSize: 18)),
          StreamBuilder<List<InboxItem>>(
            stream: db.select(db.inboxItems).watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(child: ListTile(title: Text('در دریافت ثبت‌های سریع خطا رخ داد؛ دوباره تلاش کنید.')));
              }
              final items = List<InboxItem>.of(snapshot.data ?? const <InboxItem>[]);
              if (items.isEmpty) {
                return const Card(child: ListTile(title: Text('هنوز ثبت سریعی نداریم.')));
              }
              return Column(
                children: items.reversed.take(5).map((item) {
                  return Card(
                    child: ListTile(
                      title: Text(item.rawText),
                      subtitle: Text(item.detectedType ?? 'ثبت سریع'),
                      leading: CircleAvatar(
                        backgroundColor: entryColor(item.detectedType),
                        child: Icon(entryIcon(item.detectedType), color: Colors.white),
                      ),
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


class _TodayDetailsScreen extends StatelessWidget {
  const _TodayDetailsScreen({required this.title, required this.children, required this.emptyText});

  final String title;
  final List<Widget> children;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [GlobalSettingsButton()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.touch_app),
              title: Text(title),
              subtitle: const Text('جزئیات این بخش در همین صفحه نمایش داده شده است. برای بررسی کامل‌تر، روی هر ردیف بزن.'),
            ),
          ),
          if (children.isEmpty)
            Card(child: ListTile(title: Text(emptyText), leading: const Icon(Icons.info_outline)))
          else
            ...children,
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.emptyText, required this.children, this.muted = false});

  final String title;
  final String emptyText;
  final List<Widget> children;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final textStyle = muted ? const TextStyle(color: Colors.white60) : null;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: !muted,
        title: Text(title, style: textStyle),
        children: [
          if (children.isEmpty)
            ListTile(title: Text(emptyText, style: textStyle))
          else
            ...children,
        ],
      ),
    );
  }
}

class _TodayDashboardData {
  const _TodayDashboardData({
    required this.tasks,
    required this.deadlines,
    required this.cases,
    required this.timelineEvents,
  });

  final List<Task> tasks;
  final List<Deadline> deadlines;
  final List<Case> cases;
  final List<CaseTimelineEvent> timelineEvents;
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value, required this.icon, required this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text('$label: $value'),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left, size: 16),
          ],
        ),
      ),
    );
  }
}
