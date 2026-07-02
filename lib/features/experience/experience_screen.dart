import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class ExperienceScreen extends ConsumerWidget {
  const ExperienceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('بانک تجربه')),
      body: StreamBuilder(
        stream: db.select(db.experienceItems).watch(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('هنوز تجربه‌ای ثبت نشده است.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items.reversed.toList()[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb),
                  title: Text(item.title),
                  subtitle: Text(
                    'نتیجه: ${item.result ?? 'ثبت نشده'}\n'
                    'استراتژی مؤثر: ${item.effectiveStrategy ?? 'ثبت نشده'}',
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addExperience(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addExperience(BuildContext context, AppDatabase db) {
    final title = TextEditingController();
    final result = TextEditingController();
    final strategy = TextEditingController();
    final mistakes = TextEditingController();
    final judgeNotes = TextEditingController();
    final futureTip = TextEditingController();
    int rating = 3;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('ثبت تجربه پرونده'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان تجربه')),
                TextField(controller: result, decoration: const InputDecoration(labelText: 'نتیجه پرونده')),
                TextField(controller: strategy, decoration: const InputDecoration(labelText: 'استراتژی مؤثر')),
                TextField(controller: mistakes, decoration: const InputDecoration(labelText: 'اشتباهات یا ریسک‌ها')),
                TextField(controller: judgeNotes, decoration: const InputDecoration(labelText: 'نکات قاضی / دادگاه')),
                TextField(controller: futureTip, decoration: const InputDecoration(labelText: 'نکته برای آینده')),
                DropdownButtonFormField<int>(
                  initialValue: rating,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('۱')),
                    DropdownMenuItem(value: 2, child: Text('۲')),
                    DropdownMenuItem(value: 3, child: Text('۳')),
                    DropdownMenuItem(value: 4, child: Text('۴')),
                    DropdownMenuItem(value: 5, child: Text('۵')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => rating = v);
                  },
                  decoration: const InputDecoration(labelText: 'امتیاز تجربه'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;

                await db.into(db.experienceItems).insert(
                  ExperienceItemsCompanion.insert(
                    title: title.text.trim(),
                    result: Value(result.text.trim()),
                    effectiveStrategy: Value(strategy.text.trim()),
                    mistakes: Value(mistakes.text.trim()),
                    judgeNotes: Value(judgeNotes.text.trim()),
                    futureTip: Value(futureTip.text.trim()),
                    rating: Value(rating),
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
