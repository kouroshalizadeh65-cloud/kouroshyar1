import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../cases/documents/case_document_detail_screen.dart';
import '../../core/widgets/global_search_button.dart';

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('اسناد'), actions: const [GlobalSearchButton()]),
      body: StreamBuilder(
        stream: db.select(db.caseDocuments).watch(),
        builder: (context, snapshot) {
          final docs = snapshot.data ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('هنوز سندی ثبت نشده است.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index];
              return Card(
                child: ListTile(
                  leading: Icon(d.aiSummary == null || d.aiSummary!.isEmpty ? Icons.attach_file : Icons.summarize),
                  title: Text(d.title),
                  subtitle: Text('${d.documentType ?? 'سند'} | ${d.aiSummary == null || d.aiSummary!.isEmpty ? 'بدون خلاصه' : 'دارای خلاصه'}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CaseDocumentDetailScreen(document: d)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
