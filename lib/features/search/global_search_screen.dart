import 'package:flutter/material.dart';

import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/utils/search_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_format_fa.dart';
import '../../core/utils/money_format.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../cases/case_detail_screen.dart';
import '../deadlines/deadlines_screen.dart';
import '../deadlines/personal_deadline_utils.dart';
import '../personal/personal_screen.dart';
import '../legal_texts/legal_text_detail_screen.dart';
import '../tasks/tasks_screen.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  late final TextEditingController controller;
  late String query;

  @override
  void initState() {
    super.initState();
    query = normalizeSearchText(widget.initialQuery ?? '');
    controller = TextEditingController(text: widget.initialQuery ?? '');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جستجوی سراسری'), actions: const [GlobalSettingsButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: CompactSearchField(
              controller: controller,
              autofocus: true,
              hintText: 'جستجو در همه بخش‌ها...',
              onChanged: (value) => setState(() => query = normalizeSearchText(value)),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? const Center(child: Text('عبارت موردنظر را وارد کن.'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _Cases(query: query),
                      _Tasks(query: query),
                      _Deadlines(query: query),
                      _Finance(query: query),
                      _Timeline(query: query),
                      _People(query: query),
                      _PersonalAccounts(query: query),
                      _LegalTexts(query: query),
                      _ChecklistResults(query: query),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

bool _match(String query, Iterable<String?> values) {
  if (query.isEmpty) return false;
  return searchAnyContains(query, values);
}

Future<void> _openCase(BuildContext context, WidgetRef ref, int? caseId) async {
  if (caseId == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این نتیجه به پرونده مشخصی وصل نیست.')));
    return;
  }
  final db = ref.read(databaseProvider);
  final cases = await db.select(db.cases).get();
  final matched = cases.where((c) => c.id == caseId).toList();
  if (matched.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرونده مرتبط پیدا نشد.')));
    }
    return;
  }
  if (context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: matched.first)));
  }
}

class _Cases extends ConsumerWidget {
  const _Cases({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<Case>>(
      stream: db.select(db.cases).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <Case>[]).where((c) => _match(query, [
          c.title,
          c.clientName,
          c.opponentName,
          c.subject,
          c.court,
          c.branch,
          c.judge,
          c.caseNumber,
          c.stage,
          c.clientRole,
          c.currentRole,
          c.status,
          c.nextAction,
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '⚖️ پرونده‌ها', children: items.map((c) =>
          ListTile(
            title: Text(c.title),
            subtitle: Text('${c.subject ?? 'بدون موضوع'}${(c.nextAction ?? '').isEmpty ? '' : '\nاقدام بعدی: ${c.nextAction}'}'),
            leading: const Icon(Icons.gavel),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: c))),
          )
        ).toList());
      },
    );
  }
}

class _Tasks extends ConsumerWidget {
  const _Tasks({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<Task>>(
      stream: db.select(db.tasks).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <Task>[]).where((t) => _match(query, [
          t.title,
          t.priority,
          t.dueDate == null ? null : formatPersianLongDate(t.dueDate!),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '✅ کارها', children: items.map((t) =>
          ListTile(
            title: Text(t.title),
            subtitle: Text('${t.isDone ? 'انجام شده' : 'انجام نشده'}${t.dueDate == null ? '' : ' | ${formatPersianLongDate(t.dueDate!)}'}'),
            leading: const Icon(Icons.check_circle_outline),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TasksScreen(personalOnly: t.caseId == null, initialTaskId: t.id),
              ),
            ),
          )
        ).toList());
      },
    );
  }
}

class _Deadlines extends ConsumerWidget {
  const _Deadlines({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<Deadline>>(
      stream: db.select(db.deadlines).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <Deadline>[]).where((d) => _match(query, [
          d.title,
          d.deadlineType,
          d.caseId == null ? 'مهلت شخصی' : 'مهلت پرونده',
          d.notes,
          d.extractedText,
          d.aiSummary,
          formatPersianLongDate(d.dueDate),
          d.caseId == null
              ? personalDeadlineStatusLabel(
                  personalDeadlineStatus(dueDate: d.dueDate, isDone: d.isDone),
                )
              : deadlineStatusText(d.dueDate),
          if (d.caseId == null) personalDeadlineRemainingLabel(dueDate: d.dueDate, isDone: d.isDone),
          if (d.caseId == null) personalDeadlineReminderLabel(d.reminderMinutesBefore),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '⏰ مهلت‌ها', children: items.map((d) =>
          ListTile(
            title: Text(d.title),
            subtitle: Text(
              d.caseId == null
                  ? 'مهلت شخصی | ${formatPersianLongDate(d.dueDate)} | ${personalDeadlineStatusLabel(personalDeadlineStatus(dueDate: d.dueDate, isDone: d.isDone))}'
                  : '${d.deadlineType ?? 'مهلت پرونده'} | ${formatPersianLongDate(d.dueDate)} | ${d.isDone ? 'انجام شده' : deadlineStatusText(d.dueDate)}',
            ),
            leading: const Icon(Icons.alarm),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => d.caseId == null
                    ? TasksScreen(personalOnly: true, initialDeadlineId: d.id)
                    : const DeadlinesScreen(),
              ),
            ),
          )
        ).toList());
      },
    );
  }
}

class _Finance extends ConsumerWidget {
  const _Finance({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<FinanceItem>>(
      stream: db.select(db.financeItems).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <FinanceItem>[]).where((f) => _match(query, [
          f.type,
          f.title,
          f.category,
          f.notes,
          f.attachmentName,
          f.amount.toStringAsFixed(0),
          formatMoney(f.amount),
          formatPersianLongDate(f.date),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '💰 هزینه و درآمدها', children: items.map((f) =>
          ListTile(
            title: Text(f.title),
            subtitle: Text('${f.type} | ${formatMoney(f.amount)} تومان | ${formatPersianLongDate(f.date)}'),
            leading: Icon(f.type == 'درآمد' ? Icons.trending_up : Icons.trending_down),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => f.caseId == null
                ? Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalFinanceScreen()))
                : _openCase(context, ref, f.caseId),
          )
        ).toList());
      },
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<CaseTimelineEvent>>(
      stream: db.select(db.caseTimelineEvents).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <CaseTimelineEvent>[]).where((e) => _match(query, [
          e.title,
          e.eventType,
          e.description,
          e.attachmentName,
          formatPersianLongDate(e.eventDate),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '🧭 تاریخچه پرونده', children: items.map((e) =>
          ListTile(
            title: Text(e.title),
            subtitle: Text('${e.eventType ?? 'رویداد'} | ${formatPersianLongDate(e.eventDate)}'),
            leading: const Icon(Icons.timeline),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _openCase(context, ref, e.caseId),
          )
        ).toList());
      },
    );
  }
}

class _People extends ConsumerWidget {
  const _People({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<CasePerson>>(
      stream: db.select(db.casePeople).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <CasePerson>[]).where((p) => _match(query, [
          p.name,
          p.role,
          p.phone,
          p.notes,
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '👥 اشخاص پرونده', children: items.map((p) =>
          ListTile(
            title: Text('${p.role}: ${p.name}'),
            subtitle: Text([(p.phone ?? ''), (p.notes ?? '')].where((e) => e.trim().isNotEmpty).join(' | ')),
            leading: const Icon(Icons.person_outline),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _openCase(context, ref, p.caseId),
          )
        ).toList());
      },
    );
  }
}

class _PersonalAccounts extends ConsumerWidget {
  const _PersonalAccounts({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<int>(
      stream: db.watchAny(),
      builder: (context, _) {
        return FutureBuilder<List<_AccountSearchRow>>(
          future: _load(db),
          builder: (context, snapshot) {
            final items = (snapshot.data ?? const <_AccountSearchRow>[])
                .where((item) => _match(query, [item.person.name, item.person.notes, item.transactionText]))
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return _Section(
              title: '🤝 طلب و بدهی‌ها',
              children: items
                  .map(
                    (item) => ListTile(
                      leading: const Icon(Icons.people_alt_outlined),
                      title: Text(item.person.name),
                      subtitle: Text(item.transactionText.isEmpty ? (item.person.notes ?? 'بدون توضیح') : item.transactionText),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalAccountsScreen())),
                    ),
                  )
                  .toList(),
            );
          },
        );
      },
    );
  }

  Future<List<_AccountSearchRow>> _load(AppDatabase db) async {
    final people = await db.select(db.personalAccountPersons).get();
    final transactions = await db.select(db.personalAccountTransactions).get();
    return people.map((person) {
      final related = transactions.where((item) => item.personId == person.id || item.personName == person.name).toList();
      final text = related
          .map((item) => '${item.type} ${formatMoney(item.amount)} تومان ${item.notes ?? ''}')
          .join(' | ');
      return _AccountSearchRow(person: person, transactionText: text);
    }).toList();
  }
}

class _AccountSearchRow {
  const _AccountSearchRow({required this.person, required this.transactionText});
  final PersonalAccountPerson person;
  final String transactionText;
}

class _LegalTexts extends ConsumerWidget {
  const _LegalTexts({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<LegalText>>(
      stream: db.select(db.legalTexts).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <LegalText>[]).where((t) => _match(query, [
          t.code,
          t.title,
          t.type,
          t.subject,
          t.tags,
          t.body,
          t.usageNote,
          t.successReason,
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '📚 بانک متون', children: items.map((t) =>
          ListTile(
            title: Text(t.title),
            subtitle: Text('${t.type} - ${t.subject ?? 'بدون موضوع'}'),
            leading: const Icon(Icons.menu_book),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalTextDetailScreen(item: t))),
          )
        ).toList());
      },
    );
  }
}

class _ChecklistResults extends ConsumerWidget {
  const _ChecklistResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<ChecklistTemplate>>(
      stream: db.select(db.checklistTemplates).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <ChecklistTemplate>[]).where((c) => _match(query, [
          c.title,
          c.caseType,
          c.items,
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '☑️ چک‌لیست‌ها', children: items.map((c) =>
          ListTile(title: Text(c.title), subtitle: Text(c.caseType ?? ''), leading: const Icon(Icons.checklist))
        ).toList());
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(title),
        children: children,
      ),
    );
  }
}
