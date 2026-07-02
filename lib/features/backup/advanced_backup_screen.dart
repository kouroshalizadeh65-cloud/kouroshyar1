import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';

class AdvancedBackupScreen extends ConsumerStatefulWidget {
  const AdvancedBackupScreen({super.key});
  @override
  ConsumerState<AdvancedBackupScreen> createState() => _AdvancedBackupScreenState();
}

class _AdvancedBackupScreenState extends ConsumerState<AdvancedBackupScreen> {
  String message = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پشتیبان‌گیری پیشرفته')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(child: ListTile(leading: Icon(Icons.backup), title: Text('خروجی JSON و TXT'), subtitle: Text('برای انتقال، نگهداری و بررسی دستی اطلاعات.'))),
          FilledButton.icon(onPressed: _exportJson, icon: const Icon(Icons.file_download), label: const Text('ساخت خروجی JSON')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _exportSummaryText, icon: const Icon(Icons.article), label: const Text('ساخت گزارش خلاصه TXT')),
          const SizedBox(height: 16),
          if (message.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(message))),
        ],
      ),
    );
  }

  Future<void> _exportJson() async {
    final db = ref.read(databaseProvider);
    final cases = await db.select(db.cases).get();
    final tasks = await db.select(db.tasks).get();
    final deadlines = await db.select(db.deadlines).get();
    final legalTexts = await db.select(db.legalTexts).get();
    final finance = await db.select(db.financeItems).get();
    final docs = await db.select(db.caseDocuments).get();
    final experiences = await db.select(db.experienceItems).get();
    final drafts = await db.select(db.generatedDrafts).get();

    final data = {
      'app': 'KouroshYar',
      'version': '3.4.0',
      'createdAt': DateTime.now().toIso8601String(),
      'cases': cases.map((c) => {'id': c.id, 'title': c.title, 'client': c.clientName, 'opponent': c.opponentName, 'subject': c.subject, 'court': c.court, 'branch': c.branch, 'judge': c.judge, 'caseNumber': c.caseNumber, 'stage': c.stage, 'clientRole': c.clientRole, 'currentRole': c.currentRole, 'status': c.status, 'nextAction': c.nextAction}).toList(),
      'tasks': tasks.map((t) => {'id': t.id, 'caseId': t.caseId, 'title': t.title, 'priority': t.priority, 'isDone': t.isDone, 'dueDate': t.dueDate?.toIso8601String()}).toList(),
      'deadlines': deadlines.map((d) => {'id': d.id, 'caseId': d.caseId, 'title': d.title, 'type': d.deadlineType, 'dueDate': d.dueDate.toIso8601String(), 'isDone': d.isDone}).toList(),
      'legalTexts': legalTexts.map((t) => {'id': t.id, 'title': t.title, 'type': t.type, 'subject': t.subject, 'tags': t.tags, 'qualityScore': t.qualityScore, 'usageNote': t.usageNote, 'successReason': t.successReason, 'body': t.body}).toList(),
      'finance': finance.map((f) => {'id': f.id, 'caseId': f.caseId, 'type': f.type, 'title': f.title, 'amount': f.amount, 'category': f.category}).toList(),
      'documents': docs.map((d) => {'id': d.id, 'caseId': d.caseId, 'title': d.title, 'type': d.documentType, 'filePath': d.filePath, 'notes': d.notes, 'extractedText': d.extractedText, 'aiSummary': d.aiSummary}).toList(),
      'experiences': experiences.map((e) => {'id': e.id, 'caseId': e.caseId, 'title': e.title, 'result': e.result, 'strategy': e.effectiveStrategy, 'futureTip': e.futureTip}).toList(),
      'drafts': drafts.map((d) => {'id': d.id, 'caseId': d.caseId, 'title': d.title, 'type': d.draftType, 'body': d.body}).toList(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kouroshyar_export_${DateTime.now().millisecondsSinceEpoch}.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    setState(() => message = 'خروجی JSON ساخته شد:\n${file.path}');
  }

  Future<void> _exportSummaryText() async {
    final db = ref.read(databaseProvider);
    final cases = await db.select(db.cases).get();
    final tasks = await db.select(db.tasks).get();
    final deadlines = await db.select(db.deadlines).get();
    final texts = await db.select(db.legalTexts).get();
    final buffer = StringBuffer()
      ..writeln('گزارش خلاصه کوروش‌یار')
      ..writeln('تاریخ: ${formatSimpleDateTime(DateTime.now())}')
      ..writeln('پرونده‌ها: ${cases.length}')
      ..writeln('کارها: ${tasks.length}')
      ..writeln('مهلت‌ها: ${deadlines.length}')
      ..writeln('متون حقوقی: ${texts.length}')
      ..writeln('')
      ..writeln('پرونده‌ها:');
    for (final c in cases) {
      buffer.writeln('- ${c.title} | ${c.subject ?? ''} | ${c.stage ?? ''}');
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kouroshyar_summary_${DateTime.now().millisecondsSinceEpoch}.txt'));
    await file.writeAsString(buffer.toString());
    setState(() => message = 'گزارش TXT ساخته شد:\n${file.path}');
  }
}
