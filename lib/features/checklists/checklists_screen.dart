import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class ChecklistsScreen extends ConsumerWidget {
  const ChecklistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('چک‌لیست‌ها')),
      body: StreamBuilder(
        stream: db.select(db.checklistTemplates).watch(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(child: ListTile(title: Text('هنوز چک‌لیستی ثبت نشده است.'))),
                FilledButton.icon(
                  onPressed: () => _createDefaults(db, context),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('ساخت چک‌لیست‌های کاری پایه'),
                ),
              ],
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final lines = item.items.split('\n').where((e) => e.trim().isNotEmpty).toList();
              return Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(item.title),
                  subtitle: Text(item.caseType ?? 'عمومی'),
                  children: [
                    for (final line in lines)
                      CheckboxListTile(
                        value: false,
                        onChanged: (_) {},
                        title: Text(line),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addChecklist(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createDefaults(AppDatabase db, BuildContext context) async {
    final defaults = {
      'جلسه دادگاه': [
        'مرور آخرین وضعیت پرونده',
        'بررسی مهلت‌ها',
        'آماده‌سازی مدارک اصلی',
        'آماده‌سازی نکات دفاعی',
        'بررسی ایرادات شکلی',
        'هماهنگی با موکل',
      ],
      'دادخواست مطالبه وجه': [
        'مشخصات کامل خواهان و خوانده',
        'تعیین دقیق خواسته و بهای خواسته',
        'دلایل و مستندات دین',
        'فاکتور، رسید یا قرارداد',
        'محاسبه خسارت تأخیر تأدیه',
        'شرح ماوقع کوتاه و منظم',
      ],
      'لایحه دفاعیه': [
        'خلاصه ادعای طرف مقابل',
        'ایرادات شکلی',
        'ایرادات ماهوی',
        'تحلیل ادله',
        'مواد قانونی و آراء مرتبط',
        'خواسته نهایی از دادگاه',
      ],
    };

    for (final e in defaults.entries) {
      await db.into(db.checklistTemplates).insert(
        ChecklistTemplatesCompanion.insert(
          title: e.key,
          caseType: const Value('پایه'),
          items: e.value.join('\n'),
        ),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('چک‌لیست‌های کاری پایه ساخته شد')),
      );
    }
  }

  void _addChecklist(BuildContext context, AppDatabase db) {
    final title = TextEditingController();
    final caseType = TextEditingController();
    final items = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('افزودن چک‌لیست'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان')),
              TextField(controller: caseType, decoration: const InputDecoration(labelText: 'نوع پرونده')),
              TextField(
                controller: items,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'موارد چک‌لیست؛ هر مورد در یک خط'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty || items.text.trim().isEmpty) return;

              await db.into(db.checklistTemplates).insert(
                ChecklistTemplatesCompanion.insert(
                  title: title.text.trim(),
                  caseType: Value(caseType.text.trim()),
                  items: items.text.trim(),
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
