import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../../core/widgets/global_search_button.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('کارها'), actions: const [GlobalSearchButton()]),
      body: StreamBuilder(
        stream: db.select(db.tasks).watch(),
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? [];

          if (tasks.isEmpty) {
            return const Center(child: Text('هنوز کاری ثبت نشده است.'));
          }

          final open = tasks.where((t) => !t.isDone).toList();
          final done = tasks.where((t) => t.isDone).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('کارهای انجام‌نشده', style: TextStyle(fontSize: 18)),
              if (open.isEmpty)
                const Card(child: ListTile(title: Text('کاری باقی نمانده است.'))),
              for (final task in open)
                _TaskTile(task: task),
              const SizedBox(height: 16),
              const Text('کارهای انجام‌شده', style: TextStyle(fontSize: 18)),
              if (done.isEmpty)
                const Card(child: ListTile(title: Text('هنوز کاری انجام نشده است.'))),
              for (final task in done)
                _TaskTile(task: task),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTask(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addTask(BuildContext context, AppDatabase db) {
    final titleController = TextEditingController();
    String priority = 'متوسط';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('افزودن کار'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'عنوان کار'),
              ),
              DropdownButtonFormField<String>(
                initialValue: priority,
                items: const [
                  DropdownMenuItem(value: 'خیلی زیاد', child: Text('خیلی زیاد')),
                  DropdownMenuItem(value: 'زیاد', child: Text('زیاد')),
                  DropdownMenuItem(value: 'متوسط', child: Text('متوسط')),
                  DropdownMenuItem(value: 'کم', child: Text('کم')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => priority = value);
                },
                decoration: const InputDecoration(labelText: 'اولویت'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                await db.into(db.tasks).insert(
                      TasksCompanion.insert(
                        title: title,
                        priority: Value(priority),
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

class _TaskTile extends ConsumerWidget {
  final Task task;

  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Card(
      child: CheckboxListTile(
        value: task.isDone,
        title: Text(task.title),
        subtitle: Text('اولویت: ${task.priority}'),
        onChanged: (value) async {
          await db.update(db.tasks).replace(task.copyWith(isDone: value ?? false));
        },
      ),
    );
  }
}
