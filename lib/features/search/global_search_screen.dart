import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../cases/case_detail_screen.dart';
import '../cases/documents/case_document_detail_screen.dart';
import '../deadlines/deadlines_screen.dart';
import '../finance/finance_screen.dart';
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
    query = (widget.initialQuery ?? '').trim().toLowerCase();
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
      appBar: AppBar(title: const Text('جستجوی سراسری')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'جستجو در پرونده، مهلت، مالی، اسناد، خط زمان و متون...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value.trim().toLowerCase()),
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
                      _Documents(query: query),
                      _Timeline(query: query),
                      _People(query: query),
                      _LegalTexts(query: query),
                      _GeneratedDrafts(query: query),
                      _ExperienceResults(query: query),
                      _ChecklistResults(query: query),
                      _Inbox(query: query),
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
  return values.any((value) => (value ?? '').toLowerCase().contains(query));
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen())),
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
          d.priority,
          d.notes,
          d.extractedText,
          d.aiSummary,
          formatPersianLongDate(d.dueDate),
          deadlineStatusText(d.dueDate),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '⏰ مهلت‌ها', children: items.map((d) =>
          ListTile(
            title: Text(d.title),
            subtitle: Text('${d.deadlineType ?? 'مهلت'} | ${formatPersianLongDate(d.dueDate)} | ${d.isDone ? 'انجام شده' : deadlineStatusText(d.dueDate)}'),
            leading: const Icon(Icons.alarm),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeadlinesScreen())),
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
          f.amount.toStringAsFixed(0),
          toPersianDigits(f.amount.toStringAsFixed(0)),
          formatPersianLongDate(f.date),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '💰 مالی', children: items.map((f) =>
          ListTile(
            title: Text(f.title),
            subtitle: Text('${f.type} | ${toPersianDigits(f.amount.toStringAsFixed(0))} تومان | ${formatPersianLongDate(f.date)}'),
            leading: Icon(f.type == 'درآمد' ? Icons.trending_up : Icons.trending_down),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => f.caseId == null
                ? Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceScreen()))
                : _openCase(context, ref, f.caseId),
          )
        ).toList());
      },
    );
  }
}

class _Documents extends ConsumerWidget {
  const _Documents({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<CaseDocument>>(
      stream: db.select(db.caseDocuments).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <CaseDocument>[]).where((d) => _match(query, [
          d.title,
          d.documentType,
          d.notes,
          d.filePath,
          d.extractedText,
          d.aiSummary,
          formatPersianLongDate(d.createdAt),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '📎 اسناد', children: items.map((d) =>
          ListTile(
            title: Text(d.title),
            subtitle: Text(d.documentType ?? 'سند'),
            leading: const Icon(Icons.attach_file),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDocumentDetailScreen(document: d))),
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
          formatPersianLongDate(e.eventDate),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '🧭 خط زمان پرونده', children: items.map((e) =>
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

class _GeneratedDrafts extends ConsumerWidget {
  const _GeneratedDrafts({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<GeneratedDraft>>(
      stream: db.select(db.generatedDrafts).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <GeneratedDraft>[]).where((d) => _match(query, [
          d.title,
          d.draftType,
          d.body,
          d.prompt,
          formatPersianLongDate(d.createdAt),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '📝 پیش‌نویس‌ها', children: items.map((d) =>
          ListTile(
            title: Text(d.title),
            subtitle: Text(d.draftType),
            leading: const Icon(Icons.article),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _openCase(context, ref, d.caseId),
          )
        ).toList());
      },
    );
  }
}

class _ExperienceResults extends ConsumerWidget {
  const _ExperienceResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<ExperienceItem>>(
      stream: db.select(db.experienceItems).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <ExperienceItem>[]).where((e) => _match(query, [
          e.title,
          e.result,
          e.effectiveStrategy,
          e.mistakes,
          e.judgeNotes,
          e.futureTip,
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '💡 بانک تجربه', children: items.map((e) =>
          ListTile(title: Text(e.title), subtitle: Text(e.effectiveStrategy ?? ''), leading: const Icon(Icons.lightbulb))
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

class _Inbox extends ConsumerWidget {
  const _Inbox({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<InboxItem>>(
      stream: db.select(db.inboxItems).watch(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <InboxItem>[]).where((i) => _match(query, [
          i.rawText,
          i.detectedType,
          formatPersianLongDate(i.createdAt),
        ])).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return _Section(title: '📥 ثبت‌های سریع', children: items.map((i) =>
          ListTile(title: Text(i.rawText), subtitle: Text(i.detectedType ?? 'ثبت سریع'), leading: const Icon(Icons.inbox))
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
