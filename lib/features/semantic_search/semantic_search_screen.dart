import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';
import '../ai/openai_service.dart';

class SemanticSearchScreen extends ConsumerStatefulWidget {
  const SemanticSearchScreen({super.key});

  @override
  ConsumerState<SemanticSearchScreen> createState() => _SemanticSearchScreenState();
}

class _SemanticSearchScreenState extends ConsumerState<SemanticSearchScreen> {
  final queryController = TextEditingController();
  String result = '';
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جستجوی هوشمند AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.search),
              title: Text('جستجوی معنایی'),
              subtitle: Text('اطلاعات برنامه را خلاصه کرده و از هوش مصنوعی برای یافتن ارتباط‌ها کمک می‌گیرد.'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: queryController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'درخواست جستجو', hintText: 'عبارت یا موضوع موردنظر را وارد کن', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : _run,
            icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
            label: Text(loading ? 'در حال جستجو...' : 'جستجوی هوشمند'),
          ),
          const SizedBox(height: 16),
          if (result.isNotEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(result))),
        ],
      ),
    );
  }

  Future<void> _run() async {
    setState(() { loading = true; result = ''; });
    try {
      final db = ref.read(databaseProvider);
      final settings = await db.select(db.aiSettings).get();
      if (settings.isEmpty || !settings.first.isEnabled) {
        throw Exception('هوش مصنوعی فعال نیست. ابتدا API Key را ثبت کن.');
      }
      final cases = await db.select(db.cases).get();
      final texts = await db.select(db.legalTexts).get();
      final experiences = await db.select(db.experienceItems).get();
      final deadlines = await db.select(db.deadlines).get();

      final prompt = '''
تو دستیار حقوقی و مدیریتی یک وکیل ایرانی هستی.
در اطلاعات زیر جستجوی معنایی انجام بده و فقط تطبیق کلمه‌ای نکن.
نتایج را دسته‌بندی کن و موارد مشابه، مهم، قابل استفاده و اقدام پیشنهادی را بگو.

درخواست کاربر:
${queryController.text.trim()}

پرونده‌ها:
${cases.map((c) => '- ${c.title} | موکل: ${c.clientName ?? ''} | طرف مقابل: ${c.opponentName ?? ''} | موضوع: ${c.subject ?? ''} | مرحله: ${c.stage ?? ''} | اقدام بعدی: ${c.nextAction ?? ''}').join('\n')}

بانک متون:
${texts.map((t) => '- ${t.title} | نوع: ${t.type} | موضوع: ${t.subject ?? ''} | برچسب: ${t.tags ?? ''} | کاربرد: ${t.usageNote ?? ''} | نکته موفقیت: ${t.successReason ?? ''}').join('\n')}

بانک تجربه:
${experiences.map((e) => '- ${e.title} | نتیجه: ${e.result ?? ''} | استراتژی: ${e.effectiveStrategy ?? ''} | نکته آینده: ${e.futureTip ?? ''}').join('\n')}

مهلت‌های باز:
${deadlines.where((d) => !d.isDone).map((d) => '- ${d.title} | نوع: ${d.deadlineType ?? ''} | تاریخ: ${formatPersianLongDate(d.dueDate)}').join('\n')}
''';
      final service = OpenAiService(apiKey: settings.first.apiKey ?? '', model: settings.first.model);
      final response = await service.sendPrompt(prompt);
      setState(() => result = response);
    } catch (e) {
      setState(() => result = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}
