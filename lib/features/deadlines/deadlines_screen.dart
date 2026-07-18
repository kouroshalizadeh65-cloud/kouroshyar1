import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/persian_date_picker.dart';

class DeadlinesScreen extends ConsumerWidget {
  const DeadlinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('مهلت‌ها'), actions: const [GlobalSettingsButton()]),
      body: StreamBuilder(
        stream: db.select(db.deadlines).watch(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? [];
          final items = [...all]..sort((a, b) => a.dueDate.compareTo(b.dueDate));

          if (items.isEmpty) {
            return const Center(child: Text('هنوز مهلتی ثبت نشده است.'));
          }

          final open = items.where((d) => !d.isDone).toList();
          final done = items.where((d) => d.isDone).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('مهلت‌های باز', style: TextStyle(fontSize: 18)),
              if (open.isEmpty)
                const Card(child: ListTile(title: Text('مهلت بازی وجود ندارد.'))),
              for (final item in open) _DeadlineTile(item: item),
              const SizedBox(height: 16),
              const Text('مهلت‌های انجام‌شده', style: TextStyle(fontSize: 18)),
              if (done.isEmpty)
                const Card(child: ListTile(title: Text('مهلتی انجام نشده است.'))),
              for (final item in done) _DeadlineTile(item: item),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addDeadline(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addDeadline(BuildContext context, AppDatabase db) {
    final titleController = TextEditingController();
    final typeController = TextEditingController();
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('افزودن مهلت'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'عنوان مهلت'),
                ),
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(labelText: 'نوع مهلت'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تاریخ مهلت'),
                  subtitle: Text(formatPersianLongDate(selectedDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final input = await pickPersianDate(context, initialDate: selectedDate, title: 'انتخاب تاریخ مهلت');
                    if (input != null) setState(() => selectedDate = input);
                  },
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'توضیحات'),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان مهلت را وارد کنید.')));
                  return;
                }

                await db.into(db.deadlines).insert(
                      DeadlinesCompanion.insert(
                        title: title,
                        dueDate: selectedDate,
                        deadlineType: Value(typeController.text.trim()),
                        notes: Value(notesController.text.trim()),
                      ),
                    );

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ثبت شد')));
                }
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineTile extends ConsumerWidget {
  final Deadline item;

  const _DeadlineTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final days = daysUntil(item.dueDate);
    final urgent = !item.isDone && days <= 3;

    return Card(
      child: CheckboxListTile(
        value: item.isDone,
        secondary: Icon(
          urgent ? Icons.warning_amber : Icons.event_available,
          color: urgent ? Colors.redAccent : null,
        ),
        title: Text(item.title),
        subtitle: Text(
          '${item.deadlineType ?? 'مهلت'} | ${formatPersianLongDate(item.dueDate)} | ${deadlineStatusText(item.dueDate)}',
        ),
        onChanged: (value) async {
          await db.setDeadlineDone(item, value ?? false);
        },
      ),
    );
  }
}
