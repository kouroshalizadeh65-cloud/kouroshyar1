import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_format_fa.dart';
import '../../core/utils/money_format.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/utils/search_text.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/global_search_field.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../tasks/tasks_screen.dart';

enum _PersonalFinancePeriod { all, today, week, month }

String _normalizeAccountPersonName(String value) => value
    .trim()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp(r'[\s\u200c]+'), ' ')
    .toLowerCase();

const List<String> _defaultPurchaseTitles = [
  'تخم مرغ',
  'نان',
  'برنج',
  'گوشت',
  'مرغ',
  'ماهی',
  'میوه',
  'سبزیجات',
  'لبنیات',
  'روغن',
  'چای',
  'قند و شکر',
  'بنزین',
  'کرایه و حمل‌ونقل',
  'قبض برق',
  'قبض آب',
  'قبض گاز',
  'اینترنت و موبایل',
  'شارژ ساختمان',
  'اجاره',
  'قسط',
  'درمان',
  'دارو',
  'پوشاک',
  'تعمیرات',
  'لوازم خانه',
  'سایر هزینه‌ها',
];

const List<String> _defaultIncomeTitles = [
  'حقوق',
  'حق‌الوکاله',
  'مشاوره',
  'فروش',
  'طلب وصول‌شده',
  'سایر درآمدها',
];

const List<String> _defaultCategories = [
  'خوراکی',
  'خانه',
  'حمل‌ونقل',
  'درمان',
  'پوشاک',
  'قبوض',
  'قسط و بدهی',
  'درآمد کاری',
  'سایر',
];

class PersonalScreen extends ConsumerWidget {
  const PersonalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          children: [
            Text('امور شخصی'),
            SizedBox(width: 10),
            Expanded(child: GlobalSearchField()),
          ],
        ),
        actions: const [GlobalSettingsButton()],
      ),
      body: StreamBuilder<int>(
        stream: db.watchAny(),
        builder: (context, _) {
          return FutureBuilder<_PersonalSummary>(
            future: _loadSummary(db),
            builder: (context, snapshot) {
              final summary = snapshot.data ?? const _PersonalSummary.empty();
              return ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.of(context).padding.bottom),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.sticky_note_2_outlined),
                      title: const Text('یادداشت‌های شخصی'),
                      subtitle: Text('دفترچه یادداشت آفلاین؛ ${toPersianDigits(summary.notesCount.toString())} یادداشت'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalNotesScreen())),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.task_alt_outlined),
                      title: const Text('کارها، یادآوری‌ها و مهلت‌های شخصی'),
                      subtitle: Text('دو بخش مستقل؛ ${toPersianDigits(summary.openTasksCount.toString())} کار و یادآوری، ${toPersianDigits(summary.openDeadlinesCount.toString())} مهلت فعال یا منقضی'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen(personalOnly: true))),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('هزینه و درآمدها'),
                      subtitle: Text.rich(
                        TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                              text: 'درآمد: ${formatMoney(summary.income)} تومان\n',
                              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: 'هزینه و خرید: ${formatMoney(summary.expense)} تومان\n',
                              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: 'مانده: ${formatMoney(summary.income - summary.expense)} تومان',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalFinanceScreen())),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.people_alt_outlined),
                      title: const Text('طلب و بدهی‌ها'),
                      subtitle: Text.rich(
                        TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                              text: 'مجموع طلب‌ها: ${formatMoney(summary.totalReceivable)} تومان\n',
                              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: 'مجموع بدهی‌ها: ${formatMoney(summary.totalPayable)} تومان',
                              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalAccountsScreen())),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('تفکیک از پرونده‌ها'),
                      subtitle: Text('یادداشت‌ها و امور مالی این بخش شخصی هستند. کارها و مهلت‌های این بخش شخصی‌اند و همان داده‌ها در خانه و تقویم نیز نمایش داده می‌شوند.'),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<_PersonalSummary> _loadSummary(AppDatabase db) async {
    final notes = await db.select(db.personalNotes).get();
    final tasks = (await db.select(db.tasks).get()).where((task) => task.caseId == null && !task.isDone).toList();
    final deadlines = (await db.select(db.deadlines).get()).where((item) => item.caseId == null && !item.isDone).toList();
    final finances = (await db.select(db.financeItems).get()).where((item) => item.caseId == null).toList();
    final income = finances.where((item) => item.type == 'درآمد').fold<double>(0, (sum, item) => sum + item.amount);
    final expense = finances.where((item) => item.type != 'درآمد').fold<double>(0, (sum, item) => sum + item.amount);
    final accountTransactions = await db.select(db.personalAccountTransactions).get();
    final accountSummary = _buildAccountSummaries(accountTransactions);
    final totalReceivable = accountSummary.fold<double>(0, (sum, item) => sum + item.receivable);
    final totalPayable = accountSummary.fold<double>(0, (sum, item) => sum + item.payable);
    return _PersonalSummary(
      notesCount: notes.length,
      openTasksCount: tasks.length,
      openDeadlinesCount: deadlines.length,
      income: income,
      expense: expense,
      totalReceivable: totalReceivable,
      totalPayable: totalPayable,
    );
  }
}

class _PersonalSummary {
  const _PersonalSummary({
    required this.notesCount,
    required this.openTasksCount,
    required this.openDeadlinesCount,
    required this.income,
    required this.expense,
    required this.totalReceivable,
    required this.totalPayable,
  });
  const _PersonalSummary.empty()
      : notesCount = 0,
        openTasksCount = 0,
        openDeadlinesCount = 0,
        income = 0,
        expense = 0,
        totalReceivable = 0,
        totalPayable = 0;

  final int notesCount;
  final int openTasksCount;
  final int openDeadlinesCount;
  final double income;
  final double expense;
  final double totalReceivable;
  final double totalPayable;
}

class PersonalNotesScreen extends ConsumerStatefulWidget {
  const PersonalNotesScreen({super.key});

  @override
  ConsumerState<PersonalNotesScreen> createState() => _PersonalNotesScreenState();
}

class _PersonalNotesScreenState extends ConsumerState<PersonalNotesScreen> {
  final searchController = TextEditingController();
  String query = '';

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
        title: const Text('یادداشت‌های شخصی'),
        actions: const [GlobalSettingsButton()],
      ),
      body: StreamBuilder<List<PersonalNote>>(
        stream: db.select(db.personalNotes).watch(),
        builder: (context, snapshot) {
          final items = List<PersonalNote>.of(snapshot.data ?? const <PersonalNote>[]);
          items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          final filtered = items.where((note) => _matchesNote(note, query)).toList();

          return ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.of(context).padding.bottom),
            children: [
              CompactSearchField(
                controller: searchController,
                hintText: 'جستجو در یادداشت‌ها...',
                onChanged: (value) => setState(() => query = normalizeSearchText(value)),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.note_add_outlined),
                    title: Text('یادداشتی پیدا نشد.'),
                    subtitle: Text('با دکمه + یادداشت جدید اضافه کنید.'),
                  ),
                ),
              for (final note in filtered)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(note.title),
                    subtitle: Text(
                      [
                        if ((note.category ?? '').trim().isNotEmpty) 'دسته: ${note.category}',
                        'ویرایش: ${formatPersianLongDate(note.updatedAt)}',
                        if (note.body.trim().isNotEmpty) note.body.trim(),
                      ].join('\n'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _showNoteDialog(context, db, note: note);
                        if (value == 'delete') _deleteNote(context, db, note);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                    onTap: () => _showNoteDialog(context, db, note: note),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'یادداشت جدید',
        onPressed: () => _showNoteDialog(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  bool _matchesNote(PersonalNote note, String rawQuery) {
    if (rawQuery.isEmpty) return true;
    return searchAnyContains(rawQuery, [note.title, note.body, note.category]);
  }

  void _showNoteDialog(BuildContext context, AppDatabase db, {PersonalNote? note}) {
    final titleController = TextEditingController(text: note?.title ?? '');
    final bodyController = TextEditingController(text: note?.body ?? '');
    final categoryController = TextEditingController(text: note?.category ?? '');

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(note == null ? 'یادداشت جدید' : 'ویرایش یادداشت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'عنوان یادداشت'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: 'دسته‌بندی اختیاری'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bodyController,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'متن یادداشت'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final body = bodyController.text.trim();
              if (title.isEmpty && body.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حداقل عنوان یا متن یادداشت را وارد کنید.')));
                return;
              }
              final safeTitle = title.isEmpty ? 'یادداشت بدون عنوان' : title;
              if (note == null) {
                await db.into(db.personalNotes).insert(
                      PersonalNotesCompanion.insert(
                        title: safeTitle,
                        body: body,
                        category: Value(categoryController.text.trim()),
                      ),
                    );
              } else {
                await db.update(db.personalNotes).replace(
                      note.copyWith(
                        title: safeTitle,
                        body: body,
                        category: Value(categoryController.text.trim()),
                        updatedAt: DateTime.now(),
                      ),
                    );
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note == null ? 'یادداشت ثبت شد' : 'یادداشت ویرایش شد')));
              }
            },
            child: Text(note == null ? 'ثبت' : 'ذخیره'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteNote(BuildContext context, AppDatabase db, PersonalNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف یادداشت'),
        content: const Text('آیا این یادداشت حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    await (db.delete(db.personalNotes)..where((n) => n.id.equals(note.id))).go();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('یادداشت حذف شد')));
  }
}

class PersonalFinanceScreen extends ConsumerStatefulWidget {
  const PersonalFinanceScreen({super.key});

  @override
  ConsumerState<PersonalFinanceScreen> createState() => _PersonalFinanceScreenState();
}

class _PersonalFinanceScreenState extends ConsumerState<PersonalFinanceScreen> {
  final searchController = TextEditingController();
  String query = '';
  _PersonalFinancePeriod period = _PersonalFinancePeriod.month;

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
        title: const Text('هزینه و درآمدها'),
        actions: const [GlobalSettingsButton()],
      ),
      body: StreamBuilder<List<FinanceItem>>(
        stream: db.select(db.financeItems).watch(),
        builder: (context, snapshot) {
          final allItems = List<FinanceItem>.of(snapshot.data ?? const <FinanceItem>[]).where((item) => item.caseId == null).toList();
          final suggestions = _suggestionsFromItems(allItems);
          final categorySuggestions = _categorySuggestionsFromItems(allItems);
          final filtered = allItems.where((item) => _matchesFinance(item, query) && _isInsidePeriod(item.date, period)).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          final income = filtered.where((item) => item.type == 'درآمد').fold<double>(0, (sum, item) => sum + item.amount);
          final expense = filtered.where((item) => item.type != 'درآمد').fold<double>(0, (sum, item) => sum + item.amount);
          final quantityText = _quantitySummary(filtered, query);
          final summaryTitle = _summaryTitle(filtered, query, period);
          final querySummaryType = _financeSummaryType(filtered);
          final mixedQuery = querySummaryType == 'ترکیبی';
          final querySummaryAmount = mixedQuery ? income - expense : income + expense;
          final querySummaryColor = mixedQuery
              ? (querySummaryAmount > 0
                  ? Colors.green.shade700
                  : querySummaryAmount < 0
                      ? Colors.red.shade700
                      : Theme.of(context).textTheme.bodyMedium?.color)
              : _summaryTypeColor(context, querySummaryType);

          return ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.of(context).padding.bottom),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.people_alt_outlined),
                  title: const Text('طلب و بدهی‌ها'),
                  subtitle: const Text('ثبت پرداختی و دریافتی از اشخاص و محاسبه طلب یا بدهی.'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalAccountsScreen())),
                ),
              ),
              const SizedBox(height: 8),
              CompactSearchField(
                controller: searchController,
                hintText: 'جستجو، مثل تخم مرغ یا قبض برق...',
                onChanged: (value) => setState(() => query = normalizeSearchText(value)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _periodChip(_PersonalFinancePeriod.today, 'امروز'),
                  _periodChip(_PersonalFinancePeriod.week, 'این هفته'),
                  _periodChip(_PersonalFinancePeriod.month, 'این ماه'),
                  _periodChip(_PersonalFinancePeriod.all, 'همه'),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.summarize_outlined),
                  title: Text(
                    summaryTitle,
                    style: TextStyle(
                      fontWeight: query.trim().isEmpty ? FontWeight.normal : FontWeight.bold,
                      color: query.trim().isEmpty ? null : querySummaryColor,
                    ),
                  ),
                  subtitle: Text.rich(
                    TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'درآمد: ${formatMoney(income)} تومان\n',
                          style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: 'هزینه و خرید: ${formatMoney(expense)} تومان\n',
                          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: 'مانده: ${formatMoney(income - expense)} تومان',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (query.trim().isNotEmpty)
                          TextSpan(
                            text: '\nجمع ${_summarySubject(filtered, query)}: ${formatMoney(querySummaryAmount)} تومان',
                            style: TextStyle(
                              color: querySummaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (quantityText.isNotEmpty)
                          TextSpan(
                            text: '\n$quantityText',
                            style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_outlined),
                    title: Text('ثبت مالی پیدا نشد.'),
                    subtitle: Text('با دکمه + هزینه، خرید یا درآمد جدید ثبت کنید.'),
                  ),
                ),
              for (final item in filtered)
                Card(
                  child: ListTile(
                    leading: Icon(item.type == 'درآمد' ? Icons.trending_up : item.type == 'خرید' ? Icons.shopping_cart_outlined : Icons.trending_down),
                    title: Text(item.title),
                    subtitle: Text(
                      '${item.type} | ${formatMoney(item.amount)} تومان | ${item.category ?? 'بدون دسته'}\n'
                      '${formatPersianLongDate(item.date)}${(item.notes ?? '').trim().isEmpty ? '' : '\n${item.notes}'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _showFinanceDialog(context, db, suggestions: suggestions, categorySuggestions: categorySuggestions, item: item);
                        if (value == 'delete') _deleteFinance(context, db, item);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'ثبت هزینه یا درآمد',
        onPressed: () async {
          final items = await db.select(db.financeItems).get();
          if (!mounted) return;
          final personalItems = items.where((item) => item.caseId == null).toList();
          _showFinanceDialog(
            context,
            db,
            suggestions: _suggestionsFromItems(personalItems),
            categorySuggestions: _categorySuggestionsFromItems(personalItems),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _periodChip(_PersonalFinancePeriod value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: period == value,
      onSelected: (_) => setState(() => period = value),
    );
  }

  String _periodLabel(_PersonalFinancePeriod value) {
    switch (value) {
      case _PersonalFinancePeriod.today:
        return 'امروز';
      case _PersonalFinancePeriod.week:
        return 'این هفته';
      case _PersonalFinancePeriod.month:
        return 'این ماه';
      case _PersonalFinancePeriod.all:
        return 'کل دوره';
    }
  }

  bool _matchesFinance(FinanceItem item, String rawQuery) {
    if (rawQuery.isEmpty) return true;
    return searchAnyContains(rawQuery, [item.title, item.category, item.notes, item.type]);
  }

  bool _sameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInsidePeriod(DateTime date, _PersonalFinancePeriod value) {
    final now = DateTime.now();
    switch (value) {
      case _PersonalFinancePeriod.today:
        return _sameDate(date, now);
      case _PersonalFinancePeriod.week:
        final today = DateTime(now.year, now.month, now.day);
        final daysFromSaturday = (today.weekday + 1) % 7;
        final start = today.subtract(Duration(days: daysFromSaturday));
        final end = start.add(const Duration(days: 7));
        return !date.isBefore(start) && date.isBefore(end);
      case _PersonalFinancePeriod.month:
        final current = gregorianToJalali(now);
        final target = gregorianToJalali(date);
        return current.year == target.year && current.month == target.month;
      case _PersonalFinancePeriod.all:
        return true;
    }
  }

  List<String> _suggestionsFromItems(List<FinanceItem> items) {
    final set = <String>{..._defaultPurchaseTitles, ..._defaultIncomeTitles};
    for (final item in items) {
      final title = item.title.trim();
      if (title.isNotEmpty) set.add(title);
    }
    return set.toList()..sort((a, b) => a.compareTo(b));
  }

  List<String> _categorySuggestionsFromItems(List<FinanceItem> items) {
    final set = <String>{..._defaultCategories};
    for (final item in items) {
      final category = (item.category ?? '').trim();
      if (category.isNotEmpty) set.add(category);
    }
    return set.toList()..sort((a, b) => a.compareTo(b));
  }

  List<String> _uniqueOptions(Iterable<String> values) {
    final set = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) set.add(trimmed);
    }
    return set.toList()..sort((a, b) => a.compareTo(b));
  }

  String _summaryTitle(List<FinanceItem> items, String rawQuery, _PersonalFinancePeriod selectedPeriod) {
    final q = rawQuery.trim();
    if (q.isEmpty) return 'خلاصه ${_periodLabel(selectedPeriod)}';
    return 'خلاصه ${_summarySubject(items, q)} ${_periodSuffix(selectedPeriod)}';
  }

  String _financeSummaryType(List<FinanceItem> items) {
    final types = items.map((item) => item.type).toSet();
    if (types.length == 1) return types.first;
    if (types.isEmpty) return 'مالی';
    return 'ترکیبی';
  }

  Color? _summaryTypeColor(BuildContext context, String type) {
    if (type == 'درآمد') return Colors.green.shade700;
    if (type == 'خرید' || type == 'هزینه') return Colors.red.shade700;
    return Theme.of(context).textTheme.bodyMedium?.color;
  }

  String _summarySubject(List<FinanceItem> items, String rawQuery) {
    final q = rawQuery.trim();
    final types = items.map((item) => item.type).toSet();
    var type = 'هزینه و درآمد';
    if (types.length == 1) {
      type = types.first;
    }
    return q.isEmpty ? type : '$type $q';
  }

  String _periodSuffix(_PersonalFinancePeriod value) {
    switch (value) {
      case _PersonalFinancePeriod.today:
        return 'در امروز';
      case _PersonalFinancePeriod.week:
        return 'این هفته';
      case _PersonalFinancePeriod.month:
        return 'این ماه';
      case _PersonalFinancePeriod.all:
        return 'در همه دوره‌ها';
    }
  }

  Widget _searchableDropdownTextField({
    required TextEditingController controller,
    required String label,
    required List<String> options,
    String? helperText,
  }) {
    return DropdownMenu<String>(
      controller: controller,
      enableFilter: true,
      enableSearch: true,
      menuHeight: 260,
      label: Text(label),
      helperText: helperText,
      dropdownMenuEntries: options.map((value) => DropdownMenuEntry<String>(value: value, label: value)).toList(),
      onSelected: (value) {
        if (value != null) controller.text = value;
      },
    );
  }

  String _quantitySummary(List<FinanceItem> items, String rawQuery) {
    final q = rawQuery.trim();
    if (q.isEmpty) return '';
    final matched = items.where((item) => item.title.trim().contains(q)).toList();
    if (matched.isEmpty) return '';
    var count = 0;
    final units = <String, double>{};
    for (final item in matched) {
      final parsed = _parseQuantity(item.notes ?? '');
      if (parsed == null) continue;
      count++;
      units[parsed.unit] = (units[parsed.unit] ?? 0) + parsed.amount;
    }
    if (count == 0 || units.isEmpty) return '';
    final parts = units.entries.map((entry) => '${toPersianDigits(_formatQuantity(entry.value))} ${entry.key}').join('، ');
    return 'جمع مقدار خرید $q: $parts';
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  _ParsedQuantity? _parseQuantity(String notes) {
    final normalized = notes.replaceAll('تعداد:', '').replaceAll('واحد:', '').trim();
    final match = RegExp(r'([0-9۰-۹٠-٩]+(?:[\./][0-9۰-۹٠-٩]+)?)\s*(\S+)').firstMatch(normalized);
    if (match == null) return null;
    final rawNumber = _latinDigits(match.group(1) ?? '').replaceAll('/', '.');
    final amount = double.tryParse(rawNumber);
    final unit = match.group(2)?.trim() ?? '';
    if (amount == null || unit.isEmpty) return null;
    return _ParsedQuantity(amount, unit);
  }

  String _latinDigits(String value) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var out = value;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    return out;
  }

  void _showFinanceDialog(BuildContext context, AppDatabase db, {required List<String> suggestions, required List<String> categorySuggestions, FinanceItem? item}) {
    final titleController = TextEditingController(text: item?.title ?? '');
    final amountController = TextEditingController(text: item == null ? '' : formatMoneyInput(item.amount.toStringAsFixed(0)));
    final categoryController = TextEditingController(text: item?.category ?? '');
    final quantityController = TextEditingController(text: _initialQuantity(item?.notes));
    final unitController = TextEditingController(text: _initialUnit(item?.notes));
    final notesController = TextEditingController(text: _initialFreeNotes(item?.notes));
    String selectedType = item?.type == 'درآمد' ? 'درآمد' : item?.type == 'خرید' ? 'خرید' : 'هزینه';
    DateTime selectedDate = item?.date ?? DateTime.now();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(item == null ? 'ثبت هزینه یا درآمد' : 'ویرایش هزینه یا درآمد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'خرید', child: Text('خرید')),
                    DropdownMenuItem(value: 'هزینه', child: Text('هزینه')),
                    DropdownMenuItem(value: 'درآمد', child: Text('درآمد')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      selectedType = v;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'نوع ثبت'),
                ),
                const SizedBox(height: 8),
                _searchableDropdownTextField(
                  controller: titleController,
                  label: selectedType == 'درآمد' ? 'عنوان درآمد' : 'عنوان کالا یا هزینه',
                  helperText: 'از لیست جستجو کن یا عنوان جدید بنویس.',
                  options: _uniqueOptions([
                    if (selectedType == 'درآمد') ..._defaultIncomeTitles else ..._defaultPurchaseTitles,
                    ...suggestions,
                  ]),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoneyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'مبلغ تومان'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تاریخ ثبت'),
                  subtitle: Text(formatPersianLongDate(selectedDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await _askFinanceDate(dialogContext, selectedDate);
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 8),
                _searchableDropdownTextField(
                  controller: categoryController,
                  label: 'دسته‌بندی',
                  helperText: 'از دسته‌های قبلی جستجو کن یا دسته جدید بنویس.',
                  options: categorySuggestions,
                ),
                const SizedBox(height: 8),
                if (selectedType == 'خرید')
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: quantityController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩\./]'))],
                          decoration: const InputDecoration(labelText: 'تعداد'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: unitController,
                          decoration: const InputDecoration(labelText: 'واحد، مثل شانه'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'توضیحات اختیاری'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final amount = parseMoney(amountController.text);
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان را وارد کنید.')));
                  return;
                }
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مبلغ معتبر وارد کنید.')));
                  return;
                }

                final notes = _buildFinanceNotes(
                  selectedType: selectedType,
                  quantity: quantityController.text.trim(),
                  unit: unitController.text.trim(),
                  freeNotes: notesController.text.trim(),
                );

                if (item == null) {
                  await db.into(db.financeItems).insert(
                        FinanceItemsCompanion.insert(
                          caseId: const Value<int?>(null),
                          type: selectedType,
                          title: title,
                          amount: amount,
                          category: Value(categoryController.text.trim()),
                          date: Value(selectedDate),
                          notes: Value(notes),
                        ),
                      );
                } else {
                  await db.update(db.financeItems).replace(
                        FinanceItem(
                          id: item.id,
                          caseId: null,
                          type: selectedType,
                          title: title,
                          amount: amount,
                          category: categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
                          date: selectedDate,
                          notes: notes.trim().isEmpty ? null : notes.trim(),
                          attachmentPath: item.attachmentPath,
                          attachmentName: item.attachmentName,
                          attachmentType: item.attachmentType,
                          isLawyerCost: item.isLawyerCost,
                        ),
                      );
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(item == null ? 'ثبت مالی انجام شد' : 'تغییرات ذخیره شد')));
                }
              },
              child: Text(item == null ? 'ثبت' : 'ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  String _buildFinanceNotes({required String selectedType, required String quantity, required String unit, required String freeNotes}) {
    final parts = <String>[];
    if (selectedType == 'خرید' && quantity.trim().isNotEmpty && unit.trim().isNotEmpty) {
      parts.add('تعداد: ${quantity.trim()} ${unit.trim()}');
    }
    if (freeNotes.trim().isNotEmpty) parts.add(freeNotes.trim());
    return parts.join('\n');
  }

  String _initialQuantity(String? notes) => _parseQuantity(notes ?? '')?.amount.toString() ?? '';

  String _initialUnit(String? notes) => _parseQuantity(notes ?? '')?.unit ?? '';

  String _initialFreeNotes(String? notes) {
    if (notes == null || notes.trim().isEmpty) return '';
    return notes.split('\n').where((line) => !line.trim().startsWith('تعداد:')).join('\n').trim();
  }

  Future<DateTime?> _askFinanceDate(BuildContext context, DateTime current) async {
    final controller = TextEditingController(text: formatSimpleDate(current));
    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تاریخ شمسی'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'تاریخ',
            helperText: 'مثال: ۱۴۰۵/۰۴/۲۰، امروز، فردا',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
          FilledButton(
            onPressed: () {
              final parsed = parsePersianDateInput(controller.text);
              if (parsed == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاریخ معتبر نیست.')));
                return;
              }
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFinance(BuildContext context, AppDatabase db, FinanceItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف ثبت مالی'),
        content: const Text('آیا این ثبت مالی حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    await (db.delete(db.financeItems)..where((f) => f.id.equals(item.id))).go();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ثبت مالی حذف شد')));
  }
}



class PersonalAccountsScreen extends ConsumerStatefulWidget {
  const PersonalAccountsScreen({super.key});

  @override
  ConsumerState<PersonalAccountsScreen> createState() => _PersonalAccountsScreenState();
}

class _PersonalAccountsScreenState extends ConsumerState<PersonalAccountsScreen> {
  final searchController = TextEditingController();
  String query = '';

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
        title: const Text('طلب و بدهی‌ها'),
        actions: const [GlobalSettingsButton()],
      ),
      body: StreamBuilder<int>(
        stream: db.watchAny(),
        builder: (context, _) {
          return FutureBuilder<_PersonalAccountsData>(
            future: _loadAccountsData(db),
            builder: (context, snapshot) {
              final data = snapshot.data ?? const _PersonalAccountsData.empty();
              final summaries = data.summaries.where((item) => _matchesAccountSummary(item, query)).toList()
                ..sort((a, b) => a.personName.compareTo(b.personName));
              final totalReceivable = data.summaries.fold<double>(0, (sum, item) => sum + item.receivable);
              final totalPayable = data.summaries.fold<double>(0, (sum, item) => sum + item.payable);
              final net = totalReceivable - totalPayable;

              return ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.of(context).padding.bottom),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: const Text('گزارش کلی همه اشخاص'),
                      subtitle: Text.rich(
                        TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                              text: 'مجموع طلب‌ها: ${formatMoney(totalReceivable)} تومان\n',
                              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: 'مجموع بدهی‌ها: ${formatMoney(totalPayable)} تومان\n',
                              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: net > 0
                                  ? 'مانده نهایی طلب: ${formatMoney(net)} تومان'
                                  : net < 0
                                      ? 'مانده نهایی بدهی: ${formatMoney(net.abs())} تومان'
                                      : 'تسویه / بدون مانده',
                              style: TextStyle(
                                color: net > 0 ? Colors.green.shade700 : net < 0 ? Colors.red.shade700 : Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CompactSearchField(
                    controller: searchController,
                    hintText: 'جستجوی نام شخص یا توضیحات...',
                    onChanged: (value) => setState(() => query = normalizeSearchText(value)),
                  ),
                  const SizedBox(height: 12),
                  if (summaries.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.person_add_alt_1_outlined),
                        title: Text('شخصی ثبت نشده است.'),
                        subtitle: Text('با دکمه + ابتدا شخص جدید را اضافه کنید، سپس داخل حساب همان شخص پرداختی یا دریافتی ثبت کنید.'),
                      ),
                    ),
                  for (final summary in summaries)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(summary.personName),
                        subtitle: Text.rich(_personAccountTextSpan(context, summary)),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PersonalAccountDetailScreen(personName: summary.personName, personId: summary.personId)),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'افزودن شخص جدید',
        onPressed: () async {
          final persons = await db.select(db.personalAccountPersons).get();
          if (!mounted) return;
          final created = await _showPersonalAccountPersonDialog(context, db, existingPersons: persons);
          if (!mounted || created == null) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => PersonalAccountDetailScreen(personName: created.name, personId: created.id)));
        },
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }

  Future<_PersonalAccountsData> _loadAccountsData(AppDatabase db) async {
    final persons = await db.select(db.personalAccountPersons).get();
    final transactions = await db.select(db.personalAccountTransactions).get();
    final summaries = _buildAccountSummaries(transactions, persons: persons);
    return _PersonalAccountsData(persons: persons, transactions: transactions, summaries: summaries);
  }

  bool _matchesAccountSummary(_PersonAccountSummary summary, String rawQuery) {
    if (rawQuery.isEmpty) return true;
    return searchAnyContains(rawQuery, [summary.personName, summary.notes]);
  }
}

class PersonalAccountDetailScreen extends ConsumerStatefulWidget {
  const PersonalAccountDetailScreen({super.key, required this.personName, this.personId});

  final String personName;
  final int? personId;

  @override
  ConsumerState<PersonalAccountDetailScreen> createState() => _PersonalAccountDetailScreenState();
}

class _PersonalAccountDetailScreenState extends ConsumerState<PersonalAccountDetailScreen> {
  late String personName;
  int? personId;

  @override
  void initState() {
    super.initState();
    personName = widget.personName;
    personId = widget.personId;
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('طلب و بدهی $personName'),
        actions: [
          const GlobalSettingsButton(),
          StreamBuilder<int>(
            stream: db.watchAny(),
            builder: (context, _) {
              return FutureBuilder<_PersonalAccountDetailData>(
                future: _loadDetailData(db, personName, personId),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return PopupMenuButton<String>(
                    tooltip: 'گزینه‌های شخص',
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final persons = await db.select(db.personalAccountPersons).get();
                        if (!context.mounted) return;
                        final updated = await _showPersonalAccountPersonDialog(
                          context,
                          db,
                          person: data?.person,
                          fallbackName: personName,
                          existingPersons: persons,
                        );
                        if (updated != null && mounted) {
                          setState(() {
                            personName = updated.name;
                            personId = updated.id;
                          });
                        }
                      }
                      if (value == 'delete') {
                        final deleted = await _deletePersonalAccountPerson(context, db, personName, person: data?.person);
                        if (deleted && context.mounted) Navigator.pop(context);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('ویرایش شخص')),
                      PopupMenuItem(value: 'delete', child: Text('حذف شخص و تراکنش‌ها')),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<int>(
        stream: db.watchAny(),
        builder: (context, _) {
          return FutureBuilder<_PersonalAccountDetailData>(
            future: _loadDetailData(db, personName, personId),
            builder: (context, snapshot) {
              final data = snapshot.data ?? _PersonalAccountDetailData.empty(personName);
              final transactions = data.transactions;
              final summary = data.summary;

              return ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.of(context).padding.bottom),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text('خلاصه حساب $personName'),
                      subtitle: Text.rich(_personAccountTextSpan(context, summary)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _showAccountTransactionDialog(
                            context,
                            db,
                            personSuggestions: const <String>[],
                            fixedPersonName: personName,
                            fixedPersonId: personId,
                            initialType: 'پرداختی من',
                          ),
                          icon: const Icon(Icons.north_east),
                          label: const Text('افزودن پرداختی'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showAccountTransactionDialog(
                            context,
                            db,
                            personSuggestions: const <String>[],
                            fixedPersonName: personName,
                            fixedPersonId: personId,
                            initialType: 'دریافتی من',
                          ),
                          icon: const Icon(Icons.south_west),
                          label: const Text('افزودن دریافتی'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (transactions.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.receipt_long_outlined),
                        title: Text('تراکنشی ثبت نشده است.'),
                        subtitle: Text('از دکمه‌های افزودن پرداختی یا افزودن دریافتی استفاده کنید.'),
                      ),
                    ),
                  for (final item in transactions)
                    Card(
                      child: ListTile(
                        leading: Icon(item.type == 'پرداختی من' ? Icons.north_east : Icons.south_west),
                        title: Text(
                          '${item.type}: ${formatMoney(item.amount)} تومان',
                          style: TextStyle(
                            color: item.type == 'پرداختی من' ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${formatPersianLongDate(item.date)}${(item.notes ?? '').trim().isEmpty ? '' : '\n${item.notes}'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showAccountTransactionDialog(
                                context,
                                db,
                                personSuggestions: const <String>[],
                                item: item,
                                fixedPersonName: personName,
                                fixedPersonId: personId,
                              );
                            }
                            if (value == 'delete') _deleteAccountTransaction(context, db, item);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('ویرایش تراکنش')),
                            PopupMenuItem(value: 'delete', child: Text('حذف تراکنش')),
                          ],
                        ),
                        onTap: () => _showAccountTransactionDialog(
                          context,
                          db,
                          personSuggestions: const <String>[],
                          item: item,
                          fixedPersonName: personName,
                          fixedPersonId: personId,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'افزودن تراکنش',
        onPressed: () => _showAccountTransactionDialog(
          context,
          db,
          personSuggestions: const <String>[],
          fixedPersonName: personName,
          fixedPersonId: personId,
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<_PersonalAccountDetailData> _loadDetailData(AppDatabase db, String name, int? targetPersonId) async {
    final persons = await db.select(db.personalAccountPersons).get();
    final all = await db.select(db.personalAccountTransactions).get();
    final normalized = _normalizeAccountPersonName(name);
    PersonalAccountPerson? person;
    for (final item in persons) {
      if ((targetPersonId != null && item.id == targetPersonId) ||
          (targetPersonId == null && _normalizeAccountPersonName(item.name) == normalized)) {
        person = item;
        break;
      }
    }
    final resolvedId = person?.id ?? targetPersonId;
    final transactions = all.where((item) {
      if (resolvedId != null && item.personId != null) return item.personId == resolvedId;
      return _normalizeAccountPersonName(item.personName) == normalized;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final summaries = _buildAccountSummaries(transactions, persons: person == null ? const <PersonalAccountPerson>[] : <PersonalAccountPerson>[person]);
    final summary = summaries.isEmpty ? _PersonAccountSummary.empty(name) : summaries.first;
    return _PersonalAccountDetailData(person: person, transactions: transactions, summary: summary);
  }

}

class _PersonalAccountsData {
  const _PersonalAccountsData({required this.persons, required this.transactions, required this.summaries});
  const _PersonalAccountsData.empty()
      : persons = const <PersonalAccountPerson>[],
        transactions = const <PersonalAccountTransaction>[],
        summaries = const <_PersonAccountSummary>[];

  final List<PersonalAccountPerson> persons;
  final List<PersonalAccountTransaction> transactions;
  final List<_PersonAccountSummary> summaries;
}

class _PersonalAccountDetailData {
  const _PersonalAccountDetailData({required this.person, required this.transactions, required this.summary});
  factory _PersonalAccountDetailData.empty(String personName) => _PersonalAccountDetailData(
        person: null,
        transactions: const <PersonalAccountTransaction>[],
        summary: _PersonAccountSummary.empty(personName),
      );

  final PersonalAccountPerson? person;
  final List<PersonalAccountTransaction> transactions;
  final _PersonAccountSummary summary;
}

TextSpan _personAccountTextSpan(BuildContext context, _PersonAccountSummary summary) {
  return TextSpan(
    style: DefaultTextStyle.of(context).style,
    children: [
      TextSpan(text: 'مجموع پرداختی‌های من: ${formatMoney(summary.totalPaid)} تومان\n'),
      TextSpan(text: 'مجموع دریافتی‌های من: ${formatMoney(summary.totalReceived)} تومان\n'),
      TextSpan(
        text: summary.net > 0
            ? 'طلب شما از ${summary.personName}: ${formatMoney(summary.net)} تومان'
            : summary.net < 0
                ? 'بدهی شما به ${summary.personName}: ${formatMoney(summary.net.abs())} تومان'
                : 'وضعیت حساب: تسویه / بدون مانده',
        style: TextStyle(
          color: summary.net > 0
              ? Colors.green.shade700
              : summary.net < 0
                  ? Colors.red.shade700
                  : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}


List<_PersonAccountSummary> _buildAccountSummaries(
  List<PersonalAccountTransaction> items, {
  List<PersonalAccountPerson> persons = const <PersonalAccountPerson>[],
}) {
  final grouped = <String, List<PersonalAccountTransaction>>{};
  final personByKey = <String, PersonalAccountPerson>{};

  for (final person in persons) {
    final name = person.name.trim();
    if (name.isEmpty) continue;
    final key = 'id:${person.id}';
    grouped.putIfAbsent(key, () => <PersonalAccountTransaction>[]);
    personByKey[key] = person;
  }

  for (final item in items) {
    final normalizedName = _normalizeAccountPersonName(item.personName);
    if (normalizedName.isEmpty && item.personId == null) continue;
    final key = item.personId == null ? 'name:$normalizedName' : 'id:${item.personId}';
    grouped.putIfAbsent(key, () => <PersonalAccountTransaction>[]).add(item);
  }

  return grouped.entries.map((entry) {
    final person = personByKey[entry.key];
    final fallbackName = entry.value.isEmpty ? '' : entry.value.first.personName.trim();
    final displayName = person?.name.trim().isNotEmpty == true ? person!.name.trim() : fallbackName;
    final paid = entry.value.where((item) => item.type == 'پرداختی من').fold<double>(0, (sum, item) => sum + item.amount);
    final received = entry.value.where((item) => item.type == 'دریافتی من').fold<double>(0, (sum, item) => sum + item.amount);
    final notes = <String>[person?.notes ?? '', ...entry.value.map((item) => item.notes ?? '')].where((text) => text.trim().isNotEmpty).join('\n');
    return _PersonAccountSummary(
      personName: displayName,
      personId: person?.id ?? (entry.value.isEmpty ? null : entry.value.first.personId),
      totalPaid: paid,
      totalReceived: received,
      notes: notes,
    );
  }).where((summary) => summary.personName.isNotEmpty).toList();
}


Future<PersonalAccountPerson?> _showPersonalAccountPersonDialog(
  BuildContext context,
  AppDatabase db, {
  PersonalAccountPerson? person,
  String? fallbackName,
  required List<PersonalAccountPerson> existingPersons,
}) async {
  final oldName = (person?.name ?? fallbackName ?? '').trim();
  final nameController = TextEditingController(text: oldName);
  final notesController = TextEditingController(text: person?.notes ?? '');

  return showDialog<PersonalAccountPerson>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(person == null && oldName.isEmpty ? 'افزودن شخص' : 'ویرایش شخص'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'نام شخص',
                helperText: 'نام شخص را وارد کنید؛ بعد داخل حساب او تراکنش ثبت می‌شود.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'توضیحات اختیاری درباره شخص'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
        FilledButton(
          onPressed: () async {
            final newName = nameController.text.trim();
            if (newName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نام شخص را وارد کنید.')));
              return;
            }
            final normalizedNewName = _normalizeAccountPersonName(newName);
            final duplicate = existingPersons.any((p) => _normalizeAccountPersonName(p.name) == normalizedNewName && p.id != person?.id);
            if (duplicate) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این شخص قبلاً ثبت شده است.')));
              return;
            }

            PersonalAccountPerson result;
            if (person == null) {
              final id = await db.into(db.personalAccountPersons).insert(
                    PersonalAccountPersonsCompanion.insert(
                      name: newName,
                      notes: Value(notesController.text.trim()),
                    ),
                  );
              result = PersonalAccountPerson(
                id: id,
                name: newName,
                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
            } else {
              result = person.copyWith(
                name: newName,
                notes: Value(notesController.text.trim()),
                updatedAt: DateTime.now(),
              );
              await db.updatePersonalAccountPersonWithTransactions(
                result,
                previousName: oldName,
              );
            }

            if (dialogContext.mounted) Navigator.pop(dialogContext, result);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(person == null && oldName.isEmpty ? 'شخص جدید اضافه شد' : 'اطلاعات شخص ذخیره شد')));
            }
          },
          child: Text(person == null && oldName.isEmpty ? 'افزودن' : 'ذخیره'),
        ),
      ],
    ),
  );
}

Future<bool> _deletePersonalAccountPerson(
  BuildContext context,
  AppDatabase db,
  String personName, {
  PersonalAccountPerson? person,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حذف شخص'),
      content: Text('آیا «$personName» و همه تراکنش‌های مربوط به او حذف شود؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
      ],
    ),
  );
  if (confirmed != true) return false;

  await db.deletePersonalAccountPersonCascade(
    personId: person?.id,
    personName: personName,
  );
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شخص و تراکنش‌های او حذف شد')));
  return true;
}

void _showAccountTransactionDialog(
  BuildContext context,
  AppDatabase db, {
  required List<String> personSuggestions,
  PersonalAccountTransaction? item,
  String? fixedPersonName,
  int? fixedPersonId,
  String? initialType,
}) {
  final personController = TextEditingController(text: fixedPersonName ?? item?.personName ?? '');
  final amountController = TextEditingController(text: item == null ? '' : formatMoneyInput(item.amount.toStringAsFixed(0)));
  final notesController = TextEditingController(text: item?.notes ?? '');
  String selectedType = item?.type == 'دریافتی من'
      ? 'دریافتی من'
      : (initialType == 'دریافتی من' ? 'دریافتی من' : 'پرداختی من');
  DateTime selectedDate = item?.date ?? DateTime.now();

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(item == null ? 'ثبت تراکنش شخص' : 'ویرایش تراکنش شخص'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: personController,
                enabled: fixedPersonName == null,
                decoration: InputDecoration(
                  labelText: 'نام شخص',
                  helperText: fixedPersonName == null ? 'برای شخص جدید، بهتر است ابتدا از صفحه طلب و بدهی‌ها او را اضافه کنید.' : null,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedType,
                items: const [
                  DropdownMenuItem(value: 'پرداختی من', child: Text('پرداختی من به شخص')),
                  DropdownMenuItem(value: 'دریافتی من', child: Text('دریافتی من از شخص')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => selectedType = value);
                },
                decoration: const InputDecoration(labelText: 'نوع تراکنش'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                inputFormatters: const [MoneyInputFormatter()],
                decoration: const InputDecoration(labelText: 'مبلغ تومان'),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تاریخ'),
                subtitle: Text(formatPersianLongDate(selectedDate)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final picked = await _askAccountDate(dialogContext, selectedDate);
                  if (picked != null) setState(() => selectedDate = picked);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'توضیحات اختیاری'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
          FilledButton(
            onPressed: () async {
              final person = personController.text.trim();
              final amount = parseMoney(amountController.text);
              if (person.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نام شخص را وارد کنید.')));
                return;
              }
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مبلغ معتبر وارد کنید.')));
                return;
              }
              if (item == null) {
                await db.into(db.personalAccountTransactions).insert(
                      PersonalAccountTransactionsCompanion.insert(
                        personId: Value<int?>(fixedPersonId),
                        personName: person,
                        type: selectedType,
                        amount: amount,
                        date: Value(selectedDate),
                        notes: Value(notesController.text.trim()),
                      ),
                    );
              } else {
                await db.update(db.personalAccountTransactions).replace(
                      item.copyWith(
                        personId: Value<int?>(fixedPersonId ?? item.personId),
                        personName: person,
                        type: selectedType,
                        amount: amount,
                        date: selectedDate,
                        notes: Value(notesController.text.trim()),
                      ),
                    );
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(item == null ? 'تراکنش شخص ثبت شد' : 'تغییرات تراکنش ذخیره شد')));
              }
            },
            child: Text(item == null ? 'ثبت' : 'ذخیره'),
          ),
        ],
      ),
    ),
  );
}

Future<DateTime?> _askAccountDate(BuildContext context, DateTime current) async {
  final controller = TextEditingController(text: formatSimpleDate(current));
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تاریخ شمسی'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'تاریخ',
          helperText: 'مثال: ۱۴۰۵/۰۴/۲۰، امروز، فردا',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
        FilledButton(
          onPressed: () {
            final parsed = parsePersianDateInput(controller.text);
            if (parsed == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاریخ معتبر نیست.')));
              return;
            }
            Navigator.pop(dialogContext, parsed);
          },
          child: const Text('تأیید'),
        ),
      ],
    ),
  );
}

Future<void> _deleteAccountTransaction(BuildContext context, AppDatabase db, PersonalAccountTransaction item) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حذف تراکنش شخص'),
      content: const Text('آیا این تراکنش حذف شود؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
      ],
    ),
  );
  if (confirmed != true) return;
  await (db.delete(db.personalAccountTransactions)..where((t) => t.id.equals(item.id))).go();
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تراکنش حذف شد')));
}

class _PersonAccountSummary {
  const _PersonAccountSummary({required this.personName, this.personId, required this.totalPaid, required this.totalReceived, this.notes = ''});

  factory _PersonAccountSummary.empty(String personName) => _PersonAccountSummary(personName: personName, totalPaid: 0, totalReceived: 0);

  final String personName;
  final int? personId;
  final double totalPaid;
  final double totalReceived;
  final String notes;

  double get net => totalPaid - totalReceived;
  double get receivable => net > 0 ? net : 0;
  double get payable => net < 0 ? net.abs() : 0;
}

class _ParsedQuantity {
  const _ParsedQuantity(this.amount, this.unit);
  final double amount;
  final String unit;
}
