import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../database/database_provider.dart';

class CsvExportScreen extends ConsumerStatefulWidget {
  const CsvExportScreen({super.key});
  @override
  ConsumerState<CsvExportScreen> createState() => _CsvExportScreenState();
}

class _CsvExportScreenState extends ConsumerState<CsvExportScreen> {
  String message = '';
  String _clean(String? value) => '"${(value ?? '').replaceAll('"', '""').replaceAll('\n', ' ')}"';
  Future<File> _file(String name) async => File(p.join((await getApplicationDocumentsDirectory()).path, name));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خروجی CSV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(child: ListTile(leading: Icon(Icons.table_chart), title: Text('خروجی برای Excel'), subtitle: Text('پرونده‌ها، کارها و مالی را به CSV تبدیل می‌کند.'))),
          FilledButton.icon(onPressed: _exportCases, icon: const Icon(Icons.gavel), label: const Text('خروجی پرونده‌ها')),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _exportTasks, icon: const Icon(Icons.check_circle_outline), label: const Text('خروجی کارها')),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _exportFinance, icon: const Icon(Icons.payments), label: const Text('خروجی مالی')),
          const SizedBox(height: 16),
          if (message.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(message))),
        ],
      ),
    );
  }

  Future<void> _exportCases() async {
    final db = ref.read(databaseProvider);
    final items = await db.select(db.cases).get();
    final lines = ['title,client,opponent,subject,court,branch,judge,caseNumber,stage,status,nextAction',
      ...items.map((c) => [c.title,c.clientName,c.opponentName,c.subject,c.court,c.branch,c.judge,c.caseNumber,c.stage,c.status,c.nextAction].map(_clean).join(','))];
    final file = await _file('kouroshyar_cases.csv');
    await file.writeAsString(lines.join('\n'));
    setState(() => message = 'فایل ساخته شد:\n${file.path}');
  }

  Future<void> _exportTasks() async {
    final db = ref.read(databaseProvider);
    final items = await db.select(db.tasks).get();
    final lines = ['title,priority,isDone,dueDate,caseId',
      ...items.map((t) => [t.title,t.priority,t.isDone.toString(),t.dueDate?.toIso8601String(),t.caseId?.toString()].map(_clean).join(','))];
    final file = await _file('kouroshyar_tasks.csv');
    await file.writeAsString(lines.join('\n'));
    setState(() => message = 'فایل ساخته شد:\n${file.path}');
  }

  Future<void> _exportFinance() async {
    final db = ref.read(databaseProvider);
    final items = await db.select(db.financeItems).get();
    final lines = ['type,title,amount,category,caseId',
      ...items.map((f) => [f.type,f.title,f.amount.toStringAsFixed(0),f.category,f.caseId?.toString()].map(_clean).join(','))];
    final file = await _file('kouroshyar_finance.csv');
    await file.writeAsString(lines.join('\n'));
    setState(() => message = 'فایل ساخته شد:\n${file.path}');
  }
}
