import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import 'legal_text_detail_screen.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/utils/search_text.dart';

class LegalTextsScreen extends ConsumerStatefulWidget {
  const LegalTextsScreen({super.key});

  @override
  ConsumerState<LegalTextsScreen> createState() => _LegalTextsScreenState();
}

class _LegalTextsScreenState extends ConsumerState<LegalTextsScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('بانک متون'), actions: const [GlobalSettingsButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: CompactSearchField(
              hintText: 'جستجو در عنوان، موضوع، نوع یا متن...',
              onChanged: (value) => setState(() => query = normalizeSearchText(value)),
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: db.select(db.legalTexts).watch(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? [];
                final texts = all.where((item) {
                  if (query.isEmpty) return true;
                  return searchAnyContains(query, [
                    item.title,
                    item.type,
                    item.subject,
                    item.body,
                    item.tags,
                  ]);
                }).toList();

                if (texts.isEmpty) return const Center(child: Text('متنی پیدا نشد.'));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: texts.length,
                  itemBuilder: (context, index) {
                    final item = texts[index];
                    return Card(
                      child: ListTile(
                        title: Text(item.title),
                        subtitle: Text('${item.type} - ${item.subject ?? 'بدون موضوع'}'),
                        leading: const Icon(Icons.menu_book),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => LegalTextDetailScreen(item: item)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addLegalText(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addLegalText(BuildContext context, AppDatabase db) {
    final titleController = TextEditingController();
    final subjectController = TextEditingController();
    final bodyController = TextEditingController();
    final tagsController = TextEditingController();
    final usageController = TextEditingController();
    final successController = TextEditingController();
    int qualityScore = 3;

    String selectedType = 'لایحه';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('افزودن متن حقوقی'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'لایحه', child: Text('لایحه')),
                    DropdownMenuItem(value: 'دادخواست', child: Text('دادخواست')),
                    DropdownMenuItem(value: 'شکواییه', child: Text('شکواییه')),
                    DropdownMenuItem(value: 'اظهارنامه', child: Text('اظهارنامه')),
                    DropdownMenuItem(value: 'قرارداد', child: Text('قرارداد')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => selectedType = value);
                  },
                  decoration: const InputDecoration(labelText: 'نوع متن'),
                ),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان')),
                TextField(controller: subjectController, decoration: const InputDecoration(labelText: 'موضوع')),
                TextField(controller: tagsController, decoration: const InputDecoration(labelText: 'برچسب‌ها')),
                DropdownButtonFormField<int>(
                  initialValue: qualityScore,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('۱ ستاره')),
                    DropdownMenuItem(value: 2, child: Text('۲ ستاره')),
                    DropdownMenuItem(value: 3, child: Text('۳ ستاره')),
                    DropdownMenuItem(value: 4, child: Text('۴ ستاره')),
                    DropdownMenuItem(value: 5, child: Text('۵ ستاره')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => qualityScore = value);
                  },
                  decoration: const InputDecoration(labelText: 'امتیاز کیفیت'),
                ),
                TextField(controller: usageController, decoration: const InputDecoration(labelText: 'کاربرد متن')),
                TextField(controller: successController, decoration: const InputDecoration(labelText: 'دلیل موفقیت یا نکته مهم')),
                TextField(controller: bodyController, maxLines: 6, decoration: const InputDecoration(labelText: 'متن کامل')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final body = bodyController.text.trim();
                if (title.isEmpty || body.isEmpty) return;

                await db.into(db.legalTexts).insert(
                      LegalTextsCompanion.insert(
                        title: title,
                        type: selectedType,
                        body: body,
                        subject: Value(subjectController.text.trim()),
                        tags: Value(tagsController.text.trim()),
                        qualityScore: Value(qualityScore),
                        usageNote: Value(usageController.text.trim()),
                        successReason: Value(successController.text.trim()),
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
