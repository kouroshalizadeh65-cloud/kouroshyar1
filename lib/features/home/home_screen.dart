import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/kourosh_datetime_parser.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/global_search_field.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../cases/case_detail_screen.dart';
import '../deadlines/personal_deadline_utils.dart';
import '../tasks/tasks_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum _HomeScope { all, legal, personal }

enum _HomeItemType { task, deadline, session }

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeScope _scope = _HomeScope.all;
  late Future<_HomeData> _homeFuture;

  @override
  void initState() {
    super.initState();
    final db = ref.read(databaseProvider);
    _homeFuture = _load(db);
    _homeFuture.then(
      (_) async {
        try {
          await db.syncNotifications();
        } catch (_) {}
        WidgetsBinding.instance.addPostFrameCallback((_) => _showStartupRecoveryNotice(db));
      },
      onError: (_) {},
    );
  }

  void _showStartupRecoveryNotice(AppDatabase db) {
    if (!mounted) return;
    final notice = db.takeStartupRecoveryNotice();
    if (notice == null || notice.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(notice), duration: const Duration(seconds: 8)),
    );
  }

  void _refreshHome() {
    if (!mounted) return;
    setState(() {
      _homeFuture = _load(ref.read(databaseProvider));
    });
  }

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  bool _sameDay(DateTime a, DateTime b) => _dateOnly(a) == _dateOnly(b);

  bool _isBeforeToday(DateTime value) => _dateOnly(value).isBefore(_dateOnly(DateTime.now()));

  int _daysUntil(DateTime value) => _dateOnly(value).difference(_dateOnly(DateTime.now())).inDays;

  bool _hasRealTime(DateTime? value) {
    if (value == null) return false;
    return value.hour != 0 || value.minute != 0;
  }

  String _timeText(DateTime? value) {
    if (!_hasRealTime(value)) return '';
    final hh = value!.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return toPersianDigits('$hh:$mm');
  }

  DateTime? _dateWithTimeFromTitle(DateTime? original, String title) {
    final parsedTime = parseKouroshTime(title);
    if (parsedTime == null) return original;
    final base = original ?? DateTime.now();
    final parts = parsedTime.split(':');
    final hour = int.tryParse(parts.first) ?? base.hour;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? base.minute;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  String _cleanHomeTitle(String value, String fallback) {
    var title = stripKouroshTemporalPhrases(value)
        .replaceAll(RegExp(r'^(جلسه|کار|مهلت)\s*[:：]\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty || title.length < 2) title = fallback;
    return title;
  }

  int _priorityRank(String value) {
    final p = value.trim();
    if (p.contains('خیلی') || p.contains('زیاد') || p.contains('بالا') || p.contains('مهم') || p.contains('فوری')) {
      return 0;
    }
    if (p.contains('کم') || p.contains('پایین')) return 2;
    return 1;
  }

  Future<_HomeData> _load(AppDatabase db) async {
    final results = await Future.wait<Object>([
      db.select(db.cases).get(),
      db.select(db.tasks).get(),
      db.select(db.deadlines).get(),
      db.select(db.caseTimelineEvents).get(),
    ]);

    final cases = results[0] as List<Case>;
    final tasks = results[1] as List<Task>;
    final deadlines = results[2] as List<Deadline>;
    final timeline = results[3] as List<CaseTimelineEvent>;
    final caseById = {for (final item in cases) item.id: item};
    final today = _dateOnly(DateTime.now());

    final rows = <_HomeItem>[];

    for (final task in tasks.where((e) => !e.isDone)) {
      final effectiveDate = _dateWithTimeFromTitle(task.dueDate, task.title);
      final isTodayOrOverdue = effectiveDate == null || !_dateOnly(effectiveDate).isAfter(today);
      if (!isTodayOrOverdue) continue;
      final caseTitle = task.caseId == null ? null : caseById[task.caseId!]?.title;
      final isSessionLike = task.title.contains('جلسه');
      final title = _cleanHomeTitle(task.title, isSessionLike ? 'جلسه ثبت‌شده' : 'کار بدون عنوان');
      final priority = task.priority.trim().isEmpty ? (isSessionLike ? 'زیاد' : 'متوسط') : task.priority.trim();
      rows.add(_HomeItem(
        type: _HomeItemType.task,
        title: title,
        subtitle: _taskSubtitle(effectiveDate, caseTitle, task.dueDate == null),
        sortDate: _sortDate(effectiveDate, fallbackHour: isSessionLike ? 9 : 18),
        hasTime: _hasRealTime(effectiveDate),
        priorityRank: _priorityRank(priority),
        priority: priority,
        isLegal: task.caseId != null,
        task: task,
        caseId: task.caseId,
        caseTitle: caseTitle,
        badge: task.caseId == null ? 'شخصی' : 'وکالت',
        detailType: isSessionLike ? 'جلسه / کار زمان‌دار' : 'کار',
        detailDate: effectiveDate,
      ));
    }

    for (final deadline in deadlines.where((e) => !e.isDone && _daysUntil(e.dueDate) <= 7)) {
      final caseTitle = deadline.caseId == null ? null : caseById[deadline.caseId!]?.title;
      final priority = deadline.priority.trim().isEmpty ? 'خیلی زیاد' : deadline.priority.trim();
      final personalStatus = personalDeadlineStatus(
        dueDate: deadline.dueDate,
        isDone: deadline.isDone,
      );
      rows.add(_HomeItem(
        type: _HomeItemType.deadline,
        title: _cleanHomeTitle(deadline.title, 'مهلت بدون عنوان'),
        subtitle: _deadlineSubtitle(deadline, caseTitle),
        sortDate: _sortDate(deadline.dueDate, fallbackHour: 8),
        hasTime: _hasRealTime(deadline.dueDate),
        priorityRank: _daysUntil(deadline.dueDate) <= 0 ? 0 : _priorityRank(priority),
        priority: deadline.caseId == null ? personalDeadlineStatusLabel(personalStatus) : priority,
        isLegal: deadline.caseId != null,
        deadline: deadline,
        caseId: deadline.caseId,
        caseTitle: caseTitle,
        badge: deadline.caseId == null
            ? personalDeadlineStatusLabel(personalStatus) == 'منقضی‌شده'
                ? 'مهلت شخصی منقضی'
                : 'مهلت شخصی'
            : (_daysUntil(deadline.dueDate) < 0 ? 'مهلت پرونده گذشته' : 'مهلت پرونده'),
        detailType: deadline.caseId == null ? 'مهلت شخصی' : 'مهلت پرونده',
        detailDate: deadline.dueDate,
        notes: deadline.notes,
      ));
    }

    final todaySessions = timeline
        .where((e) => !e.isDone && e.eventType == 'جلسه' && _sameDay(_dateWithTimeFromTitle(e.eventDate, e.title) ?? e.eventDate, today))
        .toList();
    for (final session in todaySessions) {
      final caseTitle = caseById[session.caseId]?.title;
      final effectiveDate = _dateWithTimeFromTitle(session.eventDate, session.title) ?? session.eventDate;
      rows.add(_HomeItem(
        type: _HomeItemType.session,
        title: _cleanHomeTitle(session.title, 'جلسه پرونده'),
        subtitle: _sessionSubtitle(effectiveDate, caseTitle),
        sortDate: _sortDate(effectiveDate, fallbackHour: 9),
        hasTime: _hasRealTime(effectiveDate),
        priorityRank: 0,
        priority: 'بالا',
        isLegal: true,
        caseId: session.caseId,
        caseTitle: caseTitle,
        badge: 'جلسه',
        detailType: 'جلسه',
        detailDate: effectiveDate,
        notes: session.description,
        session: session,
      ));
    }

    rows.sort((a, b) {
      if (a.hasTime != b.hasTime) return a.hasTime ? -1 : 1;
      if (a.hasTime && b.hasTime) {
        final byDate = a.sortDate.compareTo(b.sortDate);
        if (byDate != 0) return byDate;
      }
      final byPriority = a.priorityRank.compareTo(b.priorityRank);
      if (byPriority != 0) return byPriority;
      final byDate = a.sortDate.compareTo(b.sortDate);
      if (byDate != 0) return byDate;
      return a.title.compareTo(b.title);
    });

    return _HomeData(rows: rows);
  }

  DateTime _sortDate(DateTime? value, {required int fallbackHour}) {
    final today = _dateOnly(DateTime.now());
    if (value == null) return DateTime(today.year, today.month, today.day, fallbackHour, 0);
    if (_hasRealTime(value)) return value;
    return DateTime(value.year, value.month, value.day, fallbackHour, 0);
  }

  String _taskSubtitle(DateTime? dueDate, String? caseTitle, bool withoutDate) {
    final parts = <String>[];
    if (dueDate != null && _isBeforeToday(dueDate)) {
      parts.add('عقب‌افتاده از ${formatPersianLongDate(dueDate)}');
    }
    final time = _timeText(dueDate);
    if (time.isNotEmpty) parts.add('ساعت $time');
    if (caseTitle != null && caseTitle.trim().isNotEmpty) parts.add('پرونده: $caseTitle');
    if (withoutDate) parts.add('بدون تاریخ؛ در فهرست امروز');
    return parts.isEmpty ? 'کار امروز' : parts.join(' — ');
  }

  String _deadlineSubtitle(Deadline deadline, String? caseTitle) {
    if (deadline.caseId == null) {
      final time = _timeText(deadline.dueDate);
      final parts = <String>[
        personalDeadlineRemainingLabel(dueDate: deadline.dueDate, isDone: deadline.isDone),
        formatPersianLongDate(deadline.dueDate),
        if (time.isNotEmpty) 'ساعت $time',
      ];
      return parts.join(' — ');
    }
    final day = _daysUntil(deadline.dueDate);
    final status = day < 0
        ? 'مهلت گذشته'
        : day == 0
            ? 'امروز'
            : 'تا ${toPersianDigits(day)} روز دیگر';
    final parts = <String>[status, formatPersianLongDate(deadline.dueDate)];
    if (caseTitle != null && caseTitle.trim().isNotEmpty) parts.add('پرونده: $caseTitle');
    return parts.join(' — ');
  }

  String _sessionSubtitle(DateTime eventDate, String? caseTitle) {
    final parts = <String>[];
    final time = _timeText(eventDate);
    if (time.isNotEmpty) parts.add('ساعت $time');
    if (caseTitle != null && caseTitle.trim().isNotEmpty) parts.add('پرونده: $caseTitle');
    return parts.isEmpty ? 'جلسه امروز' : parts.join(' — ');
  }

  List<_HomeItem> _filteredRows(_HomeData data) {
    switch (_scope) {
      case _HomeScope.all:
        return data.rows;
      case _HomeScope.legal:
        return data.rows.where((e) => e.isLegal).toList();
      case _HomeScope.personal:
        return data.rows.where((e) => !e.isLegal).toList();
    }
  }

  Future<Case?> _findCase(AppDatabase db, int id) async {
    final cases = await db.select(db.cases).get();
    for (final item in cases) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _openCase(BuildContext context, int caseId) async {
    final item = await _findCase(ref.read(databaseProvider), caseId);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرونده مرتبط پیدا نشد.')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: item)));
    if (!mounted) return;
    _refreshHome();
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    _refreshHome();
  }

  void _openItem(BuildContext context, _HomeItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _HomeItemDetailScreen(item: item),
      ),
    );
  }

  void _previewItem(BuildContext context, _HomeItem item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bottom = MediaQuery.of(sheetContext).padding.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(item.subtitle),
                  if ((item.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.notes!.trim(), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _openItem(context, item);
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('جزئیات'),
                        ),
                      ),
                      if (item.caseId != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _openCase(context, item.caseId!);
                            },
                            icon: const Icon(Icons.gavel),
                            label: const Text('ورود به پرونده'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _markTaskDone(Task task) async {
    final db = ref.read(databaseProvider);
    await db.setTaskDone(task, true);
    if (!mounted) return;
    _refreshHome();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کار انجام‌شده شد.')));
  }

  Future<void> _markDeadlineDone(Deadline deadline) async {
    final db = ref.read(databaseProvider);
    await db.setDeadlineDone(deadline, true);
    if (!mounted) return;
    _refreshHome();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مهلت انجام‌شده شد.')));
  }

  Future<void> _markSessionDone(CaseTimelineEvent session) async {
    final db = ref.read(databaseProvider);
    await db.setCaseSessionDone(session, true);
    if (!mounted) return;
    _refreshHome();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جلسه علامت‌گذاری شد.')));
  }

  String _scopeLabel(_HomeScope scope) {
    switch (scope) {
      case _HomeScope.all:
        return 'همه';
      case _HomeScope.legal:
        return 'وکالت';
      case _HomeScope.personal:
        return 'شخصی';
    }
  }

  String _summaryText(List<_HomeItem> rows) {
    if (rows.isEmpty) return 'برای امروز موردی ثبت نشده است.';
    final taskCount = rows.where((e) => e.type == _HomeItemType.task).length;
    final deadlineCount = rows.where((e) => e.type == _HomeItemType.deadline).length;
    final sessionCount = rows.where((e) => e.type == _HomeItemType.session).length;
    final parts = <String>[];
    if (taskCount > 0) parts.add('${toPersianDigits(taskCount)} کار');
    if (sessionCount > 0) parts.add('${toPersianDigits(sessionCount)} جلسه');
    if (deadlineCount > 0) parts.add('${toPersianDigits(deadlineCount)} مهلت');
    return parts.isEmpty ? '${toPersianDigits(rows.length)} مورد امروز' : '${parts.join('، ')} در فهرست امروز';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          children: [
            Text('خانه'),
            SizedBox(width: 10),
            Expanded(child: GlobalSearchField()),
          ],
        ),
        actions: const [GlobalSettingsButton()],
      ),
      body: FutureBuilder<_HomeData>(
        future: _homeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          // در حالت عادی نباید پیام خطای بارگذاری روی خانه بماند.
          // اگر خواندن داده‌ها خطا بدهد، خانه با داده خالی و بدون هشدار مزاحم باز می‌شود.

          final data = snapshot.data ?? _HomeData.empty();
          final rows = _filteredRows(data);
          final firstImportant = rows.isEmpty ? null : rows.first;

          return ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.of(context).padding.bottom),
            children: [
              Text('امروز', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(formatPersianLongDate(DateTime.now()), style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              SegmentedButton<_HomeScope>(
                segments: [
                  for (final item in _HomeScope.values)
                    ButtonSegment<_HomeScope>(value: item, label: Text(_scopeLabel(item))),
                ],
                selected: {_scope},
                onSelectionChanged: (value) => setState(() => _scope = value.first),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.today),
                  title: Text(_summaryText(rows), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(firstImportant == null ? 'از دکمه ثبت سریع، کار جدید اضافه کن.' : firstImportant.title),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('فهرست امروز', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                  TextButton.icon(
                    onPressed: () => _open(context, const TasksScreen()),
                    icon: const Icon(Icons.list_alt),
                    label: const Text('همه کارها'),
                  ),
                ],
              ),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('برای امروز موردی ثبت نشده است.'),
                    subtitle: Text('کار بدون تاریخ هم در همین فهرست نمایش داده می‌شود.'),
                  ),
                )
              else
                ...rows.map((item) => _HomeListRow(
                      item: item,
                      onTap: () => _openItem(context, item),
                      onLongPress: () => _previewItem(context, item),
                      onTaskDone: item.task == null ? null : () => _markTaskDone(item.task!),
                      onDeadlineDone: item.deadline == null ? null : () => _markDeadlineDone(item.deadline!),
                      onSessionDone: item.session == null ? null : () => _markSessionDone(item.session!),
                    )),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _HomeListRow extends StatelessWidget {
  const _HomeListRow({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.onTaskDone,
    this.onDeadlineDone,
    this.onSessionDone,
  });

  final _HomeItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onTaskDone;
  final VoidCallback? onDeadlineDone;
  final VoidCallback? onSessionDone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onTaskDone != null)
                Checkbox(value: false, onChanged: (_) => onTaskDone?.call())
              else if (onDeadlineDone != null)
                Checkbox(value: false, onChanged: (_) => onDeadlineDone?.call())
              else if (onSessionDone != null)
                Checkbox(value: false, onChanged: (_) => onSessionDone?.call())
              else
                const SizedBox(width: 14),
              item.type == _HomeItemType.deadline && item.deadline?.caseId == null
                  ? _DeadlineMarker(deadline: item.deadline!)
                  : _PriorityMarker(rank: item.priorityRank),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(item.badge, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeadlineMarker extends StatelessWidget {
  const _DeadlineMarker({required this.deadline, this.size = 28});

  final Deadline deadline;
  final double size;

  @override
  Widget build(BuildContext context) {
    final status = personalDeadlineStatus(dueDate: deadline.dueDate, isDone: deadline.isDone);
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      PersonalDeadlineStatus.active => scheme.primary,
      PersonalDeadlineStatus.dueToday => Colors.deepOrange,
      PersonalDeadlineStatus.expired => scheme.error,
      PersonalDeadlineStatus.done => Colors.blueGrey,
    };
    final icon = switch (status) {
      PersonalDeadlineStatus.active => Icons.hourglass_bottom_rounded,
      PersonalDeadlineStatus.dueToday => Icons.notification_important_outlined,
      PersonalDeadlineStatus.expired => Icons.error_outline,
      PersonalDeadlineStatus.done => Icons.check_circle_outline,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(.18),
        border: Border.all(color: color, width: 1.3),
      ),
      child: Icon(icon, color: color, size: size * .58),
    );
  }
}

class _PriorityMarker extends StatelessWidget {
  const _PriorityMarker({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      0 => Colors.redAccent,
      2 => Colors.blueGrey,
      _ => Colors.orangeAccent,
    };
    final icon = switch (rank) {
      0 => Icons.arrow_upward,
      2 => Icons.arrow_downward,
      _ => Icons.arrow_forward,
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(.22), border: Border.all(color: color, width: 1.3)),
      child: Icon(icon, color: color, size: 17),
    );
  }
}

class _HomeItemDetailScreen extends ConsumerWidget {
  const _HomeItemDetailScreen({required this.item});

  final _HomeItem item;

  Future<Case?> _findCase(AppDatabase db, int? id) async {
    if (id == null) return null;
    final cases = await db.select(db.cases).get();
    for (final entry in cases) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('جزئیات مورد'), actions: const [GlobalSettingsButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      item.type == _HomeItemType.deadline && item.deadline?.caseId == null
                          ? _DeadlineMarker(deadline: item.deadline!, size: 34)
                          : _PriorityMarker(rank: item.priorityRank),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DetailLine(label: 'نوع', value: item.detailType),
                  if (item.detailDate != null) _DetailLine(label: 'زمان/تاریخ', value: item.hasTime ? 'ساعت ${toPersianDigits(item.detailDate!.hour.toString().padLeft(2, '0'))}:${toPersianDigits(item.detailDate!.minute.toString().padLeft(2, '0'))} — ${formatPersianLongDate(item.detailDate!)}' : formatPersianLongDate(item.detailDate!)),
                  if ((item.caseTitle ?? '').trim().isNotEmpty) _DetailLine(label: 'پرونده', value: item.caseTitle!.trim()),
                  if (item.type == _HomeItemType.deadline && item.deadline?.caseId == null) ...[
                    _DetailLine(label: 'وضعیت', value: item.priority),
                    _DetailLine(
                      label: 'یادآوری',
                      value: personalDeadlineReminderLabel(item.deadline!.reminderMinutesBefore),
                    ),
                  ] else
                    _DetailLine(label: 'اولویت', value: item.priority),
                  if ((item.notes ?? '').trim().isNotEmpty) _DetailLine(label: 'توضیحات', value: item.notes!.trim()),
                ],
              ),
            ),
          ),
          if (item.caseId != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<Case?>(
              future: _findCase(ref.read(databaseProvider), item.caseId),
              builder: (context, snapshot) {
                final caseItem = snapshot.data;
                return FilledButton.icon(
                  onPressed: caseItem == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: caseItem))),
                  icon: const Icon(Icons.gavel),
                  label: const Text('ورود به پرونده'),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({required this.rows});

  factory _HomeData.empty() => const _HomeData(rows: []);

  final List<_HomeItem> rows;
}

class _HomeItem {
  const _HomeItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.sortDate,
    required this.hasTime,
    required this.priorityRank,
    required this.priority,
    required this.isLegal,
    required this.badge,
    required this.detailType,
    this.detailDate,
    this.task,
    this.deadline,
    this.session,
    this.caseId,
    this.caseTitle,
    this.notes,
  });

  final _HomeItemType type;
  final String title;
  final String subtitle;
  final DateTime sortDate;
  final bool hasTime;
  final int priorityRank;
  final String priority;
  final bool isLegal;
  final String badge;
  final String detailType;
  final DateTime? detailDate;
  final Task? task;
  final Deadline? deadline;
  final CaseTimelineEvent? session;
  final int? caseId;
  final String? caseTitle;
  final String? notes;
}
