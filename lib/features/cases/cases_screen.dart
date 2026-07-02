import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import 'case_detail_screen.dart';
import '../../core/widgets/global_search_button.dart';

class CasesScreen extends ConsumerWidget {
  const CasesScreen({super.key});

  static const roleOptions = [
    'خواهان',
    'خوانده',
    'شاکی',
    'متهم',
    'تجدیدنظرخواه',
    'تجدیدنظرخوانده',
    'محکوم‌له',
    'محکوم‌علیه',
    'معترض ثالث',
    'سایر',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('پرونده‌ها'), actions: const [GlobalSearchButton()]),
      body: StreamBuilder<List<Case>>(
        stream: db.select(db.cases).watch(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('در دریافت فهرست پرونده‌ها خطا رخ داد. دوباره تلاش کنید.'));
          }
          final cases = List<Case>.of(snapshot.data ?? const <Case>[]);
          if (cases.isEmpty) return const Center(child: Text('هنوز پرونده‌ای ثبت نشده است.'));

          cases.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: cases.length,
            itemBuilder: (context, index) {
              final item = cases[index];
              final subtitleParts = [
                if ((item.clientName ?? '').isNotEmpty) 'موکل: ${item.clientName}',
                if ((item.currentRole ?? item.clientRole ?? '').isNotEmpty) 'سمت: ${item.currentRole ?? item.clientRole}',
                if ((item.stage ?? '').isNotEmpty) 'مرحله: ${item.stage}',
              ];
              return Card(
                child: ListTile(
                  title: Text(item.title),
                  subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join('\n')),
                  leading: const Icon(Icons.gavel),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CaseDetailScreen(item: item)),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCaseDialog(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddCaseDialog(BuildContext context, AppDatabase db) {
    final titleController = TextEditingController();
    final clientController = TextEditingController();
    final subjectController = TextEditingController();
    final courtController = TextEditingController();
    final branchController = TextEditingController();
    final caseNumberController = TextEditingController();
    String? clientRole;
    String? currentRole;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('افزودن پرونده'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان پرونده')),
                TextField(controller: clientController, decoration: const InputDecoration(labelText: 'نام موکل')),
                TextField(controller: subjectController, decoration: const InputDecoration(labelText: 'موضوع')),
                TextField(controller: courtController, decoration: const InputDecoration(labelText: 'مرجع قضایی')),
                TextField(controller: branchController, decoration: const InputDecoration(labelText: 'شعبه')),
                TextField(controller: caseNumberController, decoration: const InputDecoration(labelText: 'شماره پرونده')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: clientRole,
                  decoration: const InputDecoration(labelText: 'سمت موکل در دعوای اصلی', border: OutlineInputBorder()),
                  items: roleOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => clientRole = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: currentRole,
                  decoration: const InputDecoration(labelText: 'سمت موکل در مرحله فعلی', border: OutlineInputBorder()),
                  items: roleOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => currentRole = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                await db.into(db.cases).insert(
                      CasesCompanion.insert(
                        title: title,
                        clientName: Value(clientController.text.trim()),
                        subject: Value(subjectController.text.trim()),
                        court: Value(courtController.text.trim()),
                        branch: Value(branchController.text.trim()),
                        caseNumber: Value(caseNumberController.text.trim()),
                        clientRole: Value(clientRole),
                        currentRole: Value(currentRole),
                      ),
                    );

                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}
