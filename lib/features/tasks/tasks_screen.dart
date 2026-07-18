import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/utils/search_text.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/persian_date_picker.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../deadlines/personal_deadline_utils.dart';

enum _TaskFilter { open, today, expired, future, done, all }

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({
    super.key,
    this.personalOnly = false,
    this.initialTaskId,
    this.initialDeadlineId,
    this.openAddOnStart = false,
    this.initialAddType = 'task',
  });

  final bool personalOnly;
  final int? initialTaskId;
  final int? initialDeadlineId;
  final bool openAddOnStart;
  final String initialAddType;

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final searchController = TextEditingController();
  String query = '';
  _TaskFilter filter = _TaskFilter.open;
  bool _openedInitialTask = false;
  bool _openedInitialDeadline = false;
  bool _openedInitialAdd = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.personalOnly ? 'کارها، یادآوری‌ها و مهلت‌های شخصی' : 'کارها'),
        actions: const [GlobalSettingsButton()],
      ),
      body: StreamBuilder<int>(
        stream: db.watchAny(),
        builder: (context, _) {
          return FutureBuilder<_TaskDeadlineData>(
            future: _load(db),
            builder: (context, snapshot) {
              final data = snapshot.data ?? const _TaskDeadlineData(tasks: <Task>[], deadlines: <Deadline>[]);
              final tasks = data.tasks.where(_passesTaskFilter).where(_matchesTaskQuery).toList();
              final deadlines = data.deadlines.where(_passesDeadlineFilter).where(_matchesDeadlineQuery).toList();

              _openRequestedDialogs(db, data.tasks, data.deadlines);

              return ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 104 + MediaQuery.of(context).padding.bottom),
                children: [
                  CompactSearchField(
                    controller: searchController,
                    hintText: widget.personalOnly ? 'جستجو در کارها و مهلت‌های شخصی...' : 'جستجو در کارها...',
                    onChanged: (value) => setState(() => query = normalizeSearchText(value)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip(_TaskFilter.open, 'باز'),
                      _filterChip(_TaskFilter.today, 'امروز'),
                      _filterChip(_TaskFilter.expired, 'گذشته'),
                      _filterChip(_TaskFilter.future, 'آینده'),
                      _filterChip(_TaskFilter.done, 'انجام‌شده'),
                      _filterChip(_TaskFilter.all, 'همه'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (data.tasks.isEmpty && data.deadlines.isEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.task_alt),
                        title: Text(widget.personalOnly ? 'هنوز کار، یادآوری یا مهلت شخصی ثبت نشده است.' : 'هنوز کاری ثبت نشده است.'),
                        subtitle: Text(widget.personalOnly ? 'با دکمه + نوع مورد را انتخاب و ثبت کنید.' : 'با دکمه + کار جدید اضافه کنید.'),
                      ),
                    )
                  else if (tasks.isEmpty && deadlines.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.search_off),
                        title: Text('موردی با این شرایط پیدا نشد.'),
                        subtitle: Text('جستجو یا فیلتر را تغییر دهید.'),
                      ),
                    )
                  else ...[
                    if (tasks.isNotEmpty) ...[
                      _TaskSectionHeader(count: tasks.length),
                      const SizedBox(height: 6),
                      for (final task in tasks) _TaskTile(task: task),
                    ],
                    if (deadlines.isNotEmpty) ...[
                      if (tasks.isNotEmpty) const SizedBox(height: 14),
                      _DeadlineSectionHeader(deadlines: deadlines),
                      const SizedBox(height: 6),
                      for (final deadline in deadlines) _DeadlineTile(deadline: deadline),
                    ],
                  ],
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: widget.personalOnly ? 'افزودن کار، یادآوری یا مهلت شخصی' : 'افزودن کار',
        onPressed: () => widget.personalOnly ? _chooseAddType(context, db) : _showTaskDialog(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<_TaskDeadlineData> _load(AppDatabase db) async {
    final taskRows = await db.select(db.tasks).get();
    final tasks = taskRows.where((task) => !widget.personalOnly || task.caseId == null).toList()..sort(_taskSort);
    if (!widget.personalOnly) return _TaskDeadlineData(tasks: tasks, deadlines: const <Deadline>[]);
    final deadlineRows = await db.select(db.deadlines).get();
    final deadlines = deadlineRows.where((deadline) => deadline.caseId == null).toList()..sort(_deadlineSort);
    return _TaskDeadlineData(tasks: tasks, deadlines: deadlines);
  }

  void _openRequestedDialogs(AppDatabase db, List<Task> tasks, List<Deadline> deadlines) {
    if (!_openedInitialTask && widget.initialTaskId != null) {
      Task? target;
      for (final task in tasks) {
        if (task.id == widget.initialTaskId) {
          target = task;
          break;
        }
      }
      if (target != null) {
        _openedInitialTask = true;
        final selected = target;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showTaskDialog(context, db, task: selected);
        });
      }
    }
    if (!_openedInitialDeadline && widget.initialDeadlineId != null) {
      Deadline? target;
      for (final deadline in deadlines) {
        if (deadline.id == widget.initialDeadlineId) {
          target = deadline;
          break;
        }
      }
      if (target != null) {
        _openedInitialDeadline = true;
        final selected = target;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showDeadlineDialog(context, db, deadline: selected);
        });
      }
    }
    if (!_openedInitialAdd && widget.openAddOnStart) {
      _openedInitialAdd = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.initialAddType == 'deadline' && widget.personalOnly) {
          _showDeadlineDialog(context, db);
        } else {
          _showTaskDialog(context, db);
        }
      });
    }
  }

  Widget _filterChip(_TaskFilter value, String label) => ChoiceChip(
        label: Text(label),
        selected: filter == value,
        onSelected: (_) => setState(() => filter = value),
      );

  int _taskSort(Task a, Task b) {
    if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
    final ad = a.dueDate;
    final bd = b.dueDate;
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    if (ad != null && bd != null) {
      final byDate = ad.compareTo(bd);
      if (byDate != 0) return byDate;
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  int _deadlineSort(Deadline a, Deadline b) {
    if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
    return a.dueDate.compareTo(b.dueDate);
  }

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
  bool _matchesTaskQuery(Task task) {
    if (query.isEmpty) return true;
    return searchAnyContains(query, [
      task.title,
      task.priority,
      task.isDone ? 'انجام شده' : 'انجام نشده',
      task.dueDate == null ? null : formatPersianLongDate(task.dueDate!),
    ]);
  }

  bool _matchesDeadlineQuery(Deadline deadline) {
    if (query.isEmpty) return true;
    final status = personalDeadlineStatus(
      dueDate: deadline.dueDate,
      isDone: deadline.isDone,
    );
    return searchAnyContains(query, [
      deadline.title,
      deadline.notes,
      formatPersianLongDate(deadline.dueDate),
      personalDeadlineStatusLabel(status),
      personalDeadlineRemainingLabel(dueDate: deadline.dueDate, isDone: deadline.isDone),
      personalDeadlineReminderLabel(deadline.reminderMinutesBefore),
    ]);
  }

  bool _passesTaskFilter(Task task) {
    final today = _dateOnly(DateTime.now());
    final due = task.dueDate == null ? null : _dateOnly(task.dueDate!);
    switch (filter) {
      case _TaskFilter.open:
        return !task.isDone;
      case _TaskFilter.today:
        return !task.isDone && (due == null || due == today);
      case _TaskFilter.expired:
        return !task.isDone && due != null && due.isBefore(today);
      case _TaskFilter.future:
        return !task.isDone && due != null && due.isAfter(today);
      case _TaskFilter.done:
        return task.isDone;
      case _TaskFilter.all:
        return true;
    }
  }

  bool _passesDeadlineFilter(Deadline deadline) {
    final status = personalDeadlineStatus(
      dueDate: deadline.dueDate,
      isDone: deadline.isDone,
    );
    switch (filter) {
      case _TaskFilter.open:
        return status != PersonalDeadlineStatus.done;
      case _TaskFilter.today:
        return status == PersonalDeadlineStatus.dueToday;
      case _TaskFilter.expired:
        return status == PersonalDeadlineStatus.expired;
      case _TaskFilter.future:
        return status == PersonalDeadlineStatus.active;
      case _TaskFilter.done:
        return status == PersonalDeadlineStatus.done;
      case _TaskFilter.all:
        return true;
    }
  }

  Future<void> _chooseAddType(BuildContext context, AppDatabase db) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    final type = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('نوع مورد جدید'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('انتخاب کنید کار و یادآوری ثبت شود یا مهلت شخصی.'),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: const Text('کار و یادآوری'),
              onTap: () => Navigator.pop(dialogContext, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.alarm_outlined),
              title: const Text('مهلت'),
              onTap: () => Navigator.pop(dialogContext, 'deadline'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
        ],
      ),
    );
    if (!context.mounted) return;
    if (type == 'task') await _showTaskDialog(context, db);
    if (type == 'deadline') await _showDeadlineDialog(context, db);
  }

  Future<void> _showTaskDialog(BuildContext context, AppDatabase db, {Task? task}) async {
    final titleController = TextEditingController(text: task?.title ?? '');
    String priority = task?.priority ?? 'متوسط';
    DateTime? dueDate = task?.dueDate;
    bool isDone = task?.isDone ?? false;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(task == null ? (widget.personalOnly ? 'افزودن کار و یادآوری شخصی' : 'افزودن کار') : 'ویرایش کار و یادآوری'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان کار یا یادآوری')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    items: const [
                      DropdownMenuItem(value: 'خیلی زیاد', child: Text('خیلی زیاد')),
                      DropdownMenuItem(value: 'زیاد', child: Text('زیاد')),
                      DropdownMenuItem(value: 'متوسط', child: Text('متوسط')),
                      DropdownMenuItem(value: 'کم', child: Text('کم')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => priority = value);
                    },
                    decoration: const InputDecoration(labelText: 'اولویت'),
                  ),
                  const SizedBox(height: 8),
                  _DateTimePickerRow(
                    value: dueDate,
                    emptyText: 'بدون تاریخ؛ در خانه امروز نمایش داده می‌شود',
                    dateTitle: 'انتخاب تاریخ کار یا یادآوری',
                    onChanged: (value) => setDialogState(() => dueDate = value),
                    allowClear: true,
                  ),
                  if (task != null)
                    SwitchListTile(
                      value: isDone,
                      onChanged: (value) => setDialogState(() => isDone = value),
                      title: const Text('انجام‌شده'),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('عنوان کار یا یادآوری را وارد کنید.')));
                    return;
                  }
                  if (task == null) {
                    await db.into(db.tasks).insert(
                          TasksCompanion.insert(
                            title: title,
                            priority: Value(priority),
                            dueDate: Value(dueDate),
                            caseId: const Value<int?>(null),
                          ),
                        );
                  } else {
                    final updated = task.copyWith(title: title, priority: priority, dueDate: Value(dueDate), isDone: task.isDone);
                    await db.setTaskDone(updated, isDone);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('ذخیره'),
              ),
            ],
          ),
        ),
      );
    } finally {
      titleController.dispose();
    }
  }

  Future<void> _showDeadlineDialog(BuildContext context, AppDatabase db, {Deadline? deadline}) async {
    final titleController = TextEditingController(text: deadline?.title ?? '');
    final notesController = TextEditingController(text: deadline?.notes ?? '');
    DateTime dueDate = deadline?.dueDate ?? DateTime.now().add(const Duration(days: 1));
    final storedReminderMinutes = deadline?.reminderMinutesBefore ?? 0;
    int reminderMinutesBefore = personalDeadlineReminderOptions.contains(storedReminderMinutes)
        ? storedReminderMinutes
        : 0;
    bool isDone = deadline?.isDone ?? false;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(deadline == null ? 'افزودن مهلت شخصی' : 'ویرایش مهلت شخصی'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext).colorScheme.errorContainer.withOpacity(.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'مهلت شخصی یک سررسید قطعی دارد. وضعیت و فوریت آن بر اساس زمان باقی‌مانده محاسبه می‌شود و اولویت دستی ندارد.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    autofocus: deadline == null,
                    decoration: const InputDecoration(labelText: 'عنوان مهلت'),
                  ),
                  const SizedBox(height: 10),
                  _DateTimePickerRow(
                    value: dueDate,
                    emptyText: 'تاریخ و ساعت پایان مهلت الزامی است',
                    dateTitle: 'انتخاب تاریخ پایان مهلت',
                    dateButtonLabel: 'تاریخ پایان',
                    timeButtonLabel: 'ساعت پایان',
                    onChanged: (value) {
                      if (value != null) setDialogState(() => dueDate = value);
                    },
                    allowClear: false,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: reminderMinutesBefore,
                    items: personalDeadlineReminderOptions
                        .map(
                          (minutes) => DropdownMenuItem<int>(
                            value: minutes,
                            child: Text(personalDeadlineReminderLabel(minutes)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => reminderMinutesBefore = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'یادآوری پیش از سررسید',
                      prefixIcon: Icon(Icons.notifications_active_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'توضیحات، اختیاری'),
                  ),
                  if (deadline != null)
                    SwitchListTile(
                      value: isDone,
                      onChanged: (value) => setDialogState(() => isDone = value),
                      title: const Text('مهلت انجام شده است'),
                      subtitle: const Text('با فعال‌کردن این گزینه، اعلان آینده مهلت لغو می‌شود.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('عنوان مهلت را وارد کنید.')));
                    return;
                  }
                  final reminderTime = personalDeadlineReminderTime(
                    dueDate: dueDate,
                    reminderMinutesBefore: reminderMinutesBefore,
                  );
                  if (!isDone && dueDate.isBefore(DateTime.now())) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('تاریخ پایان مهلت در گذشته است؛ مهلت با وضعیت منقضی‌شده ذخیره می‌شود.')),
                    );
                  } else if (!isDone && reminderTime != null && reminderTime.isBefore(DateTime.now())) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('زمان یادآوری انتخاب‌شده گذشته است؛ مهلت ذخیره می‌شود اما اعلان آینده ثبت نخواهد شد.')),
                    );
                  }
                  if (deadline == null) {
                    await db.into(db.deadlines).insert(
                          DeadlinesCompanion.insert(
                            caseId: const Value<int?>(null),
                            title: title,
                            deadlineType: const Value<String?>(null),
                            dueDate: dueDate,
                            priority: const Value<String>('خیلی زیاد'),
                            reminderMinutesBefore: Value<int>(reminderMinutesBefore),
                            notes: Value<String?>(notesController.text.trim()),
                          ),
                        );
                  } else {
                    final updated = deadline.copyWith(
                      title: title,
                      deadlineType: const Value<String?>(null),
                      dueDate: dueDate,
                      priority: 'خیلی زیاد',
                      reminderMinutesBefore: reminderMinutesBefore,
                      notes: Value<String?>(notesController.text.trim()),
                      isDone: deadline.isDone,
                    );
                    await db.setDeadlineDone(updated, isDone);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('ذخیره مهلت'),
              ),
            ],
          ),
        ),
      );
    } finally {
      titleController.dispose();
      notesController.dispose();
    }
  }

}

class _TaskDeadlineData {
  const _TaskDeadlineData({required this.tasks, required this.deadlines});
  final List<Task> tasks;
  final List<Deadline> deadlines;
}

class _DateTimePickerRow extends StatelessWidget {
  const _DateTimePickerRow({
    required this.value,
    required this.emptyText,
    required this.dateTitle,
    required this.onChanged,
    required this.allowClear,
    this.dateButtonLabel = 'تاریخ',
    this.timeButtonLabel = 'ساعت یادآوری',
  });

  final DateTime? value;
  final String emptyText;
  final String dateTitle;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final String dateButtonLabel;
  final String timeButtonLabel;

  String _timeText(DateTime date) => '${toPersianDigits(date.hour.toString().padLeft(2, '0'))}:${toPersianDigits(date.minute.toString().padLeft(2, '0'))}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(value == null ? emptyText : '${formatPersianLongDate(value!)}، ساعت ${_timeText(value!)}'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(dateButtonLabel),
              onPressed: () async {
                final base = value ?? DateTime.now();
                final picked = await pickPersianDate(context, initialDate: base, title: dateTitle);
                if (picked == null) return;
                onChanged(DateTime(picked.year, picked.month, picked.day, base.hour == 0 ? 9 : base.hour, base.minute));
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.access_time),
              label: Text(timeButtonLabel),
              onPressed: () async {
                final base = value ?? DateTime.now();
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: base.hour == 0 ? 9 : base.hour, minute: base.minute),
                );
                if (picked == null) return;
                onChanged(DateTime(base.year, base.month, base.day, picked.hour, picked.minute));
              },
            ),
            if (allowClear && value != null)
              TextButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('حذف تاریخ'),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ],
    );
  }
}

class _TaskSectionHeader extends StatelessWidget {
  const _TaskSectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.task_alt_outlined, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          'کارها و یادآوری‌ها (${toPersianDigits(count)})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _DeadlineSectionHeader extends StatelessWidget {
  const _DeadlineSectionHeader({required this.deadlines});

  final List<Deadline> deadlines;

  @override
  Widget build(BuildContext context) {
    var active = 0;
    var today = 0;
    var expired = 0;
    var done = 0;
    for (final deadline in deadlines) {
      switch (personalDeadlineStatus(dueDate: deadline.dueDate, isDone: deadline.isDone)) {
        case PersonalDeadlineStatus.active:
          active += 1;
          break;
        case PersonalDeadlineStatus.dueToday:
          today += 1;
          break;
        case PersonalDeadlineStatus.expired:
          expired += 1;
          break;
        case PersonalDeadlineStatus.done:
          done += 1;
          break;
      }
    }
    final details = <String>[
      if (active > 0) 'فعال ${toPersianDigits(active)}',
      if (today > 0) 'امروز ${toPersianDigits(today)}',
      if (expired > 0) 'منقضی ${toPersianDigits(expired)}',
      if (done > 0) 'انجام‌شده ${toPersianDigits(done)}',
    ];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withOpacity(.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withOpacity(.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_bottom_rounded, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مهلت‌های شخصی (${toPersianDigits(deadlines.length)})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' | '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Card(
      child: ListTile(
        leading: Checkbox(value: task.isDone, onChanged: (value) => db.setTaskDone(task, value ?? false)),
        title: Text(task.title, style: task.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: Text(_subtitle()),
        onTap: () async {
          final state = context.findAncestorStateOfType<_TasksScreenState>();
          await state?._showTaskDialog(context, db, task: task);
        },
        trailing: PopupMenuButton<String>(
          tooltip: 'گزینه‌های کار',
          onSelected: (value) async {
            final state = context.findAncestorStateOfType<_TasksScreenState>();
            if (value == 'edit') await state?._showTaskDialog(context, db, task: task);
            if (value == 'delete') await _delete(context, db);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('ویرایش کار و یادآوری')),
            PopupMenuItem(value: 'delete', child: Text('حذف')),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>['اولویت: ${task.priority}'];
    parts.add(task.dueDate == null ? 'بدون تاریخ؛ در خانه امروز نمایش داده می‌شود' : 'یادآوری: ${formatPersianLongDate(task.dueDate!)}');
    parts.add(task.isDone ? 'انجام‌شده' : 'باز');
    return parts.join(' | ');
  }

  Future<void> _delete(BuildContext context, AppDatabase db) async {
    final confirmed = await _confirmDelete(context, 'حذف کار و یادآوری', 'آیا «${task.title}» حذف شود؟');
    if (!confirmed) return;
    await db.deleteTaskWithTimeline(task.id);
  }
}

class _DeadlineTile extends ConsumerWidget {
  const _DeadlineTile({required this.deadline});
  final Deadline deadline;

  String _timeText(DateTime value) =>
      '${toPersianDigits(value.hour.toString().padLeft(2, '0'))}:${toPersianDigits(value.minute.toString().padLeft(2, '0'))}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
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
    final notes = deadline.notes?.trim() ?? '';

    return Card(
      color: color.withOpacity(.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(.36)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(.16),
          child: Icon(icon, color: color),
        ),
        title: Text(
          deadline.title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: deadline.isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Text(
              '${personalDeadlineStatusLabel(status)} — ${personalDeadlineRemainingLabel(dueDate: deadline.dueDate, isDone: deadline.isDone)}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            Text('پایان مهلت: ${formatPersianLongDate(deadline.dueDate)}، ساعت ${_timeText(deadline.dueDate)}'),
            Text('اعلان: ${personalDeadlineReminderLabel(deadline.reminderMinutesBefore)}'),
            if (notes.isNotEmpty) Text(notes, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        onTap: () async {
          final state = context.findAncestorStateOfType<_TasksScreenState>();
          await state?._showDeadlineDialog(context, db, deadline: deadline);
        },
        trailing: SizedBox(
          width: 92,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Checkbox(
                value: deadline.isDone,
                visualDensity: VisualDensity.compact,
                onChanged: (value) => db.setDeadlineDone(deadline, value ?? false),
              ),
              PopupMenuButton<String>(
                tooltip: 'گزینه‌های مهلت شخصی',
                onSelected: (value) async {
                  final state = context.findAncestorStateOfType<_TasksScreenState>();
                  if (value == 'edit') await state?._showDeadlineDialog(context, db, deadline: deadline);
                  if (value == 'delete') {
                    final confirmed = await _confirmDelete(context, 'حذف مهلت شخصی', 'آیا مهلت «${deadline.title}» حذف شود؟');
                    if (confirmed) await db.deleteDeadlineWithTimeline(deadline.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('ویرایش مهلت شخصی')),
                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, String title, String message) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
          ],
        ),
      ) ??
      false;
}
