import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';

class GeneratedDraftsScreen extends ConsumerWidget {
  const GeneratedDraftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('پیش‌نویس‌های تولیدشده')),
      body: StreamBuilder(
        stream: db.select(db.generatedDrafts).watch(),
        builder: (context, snapshot) {
          final drafts = snapshot.data ?? [];
          if (drafts.isEmpty) return const Center(child: Text('هنوز پیش‌نویسی تولید نشده است.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: drafts.length,
            itemBuilder: (context, index) {
              final d = drafts.reversed.toList()[index];
              return Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.description),
                  title: Text(d.title),
                  subtitle: Text(d.draftType),
                  children: [Padding(padding: const EdgeInsets.all(16), child: SelectableText(d.body))],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
