import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class PersonalItemsScreen extends ConsumerWidget {
  const PersonalItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('کارهای شخصی')),
      body: StreamBuilder(
        stream: db.select(db.tasks).watch(),
        builder: (context, snapshot) {
          final tasks = (snapshot.data ?? [])
              .where((t) => t.caseId == null)
              .toList();

          if (tasks.isEmpty) {
            return const Center(child: Text('هنوز کار شخصی ثبت نشده است.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final t = tasks[index];
              return Card(
                child: CheckboxListTile(
                  value: t.isDone,
                  title: Text(t.title),
                  subtitle: Text('اولویت: ${t.priority}'),
                  onChanged: (value) async {
                    await db.update(db.tasks).replace(t.copyWith(isDone: value ?? false));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addPersonalTask(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addPersonalTask(BuildContext context, AppDatabase db) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('افزودن کار شخصی'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'عنوان کار'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              await db.into(db.tasks).insert(
                TasksCompanion.insert(
                  title: text,
                  priority: const Value('متوسط'),
                ),
              );

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
  }
}
