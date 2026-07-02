import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../database/app_database.dart';
import '../../../database/database_provider.dart';
import '../../ai/openai_service.dart';
import '../../../core/widgets/global_search_button.dart';

class CaseDocumentDetailScreen extends ConsumerStatefulWidget {
  final CaseDocument document;

  const CaseDocumentDetailScreen({
    super.key,
    required this.document,
  });

  @override
  ConsumerState<CaseDocumentDetailScreen> createState() => _CaseDocumentDetailScreenState();
}

class _CaseDocumentDetailScreenState extends ConsumerState<CaseDocumentDetailScreen> {
  late TextEditingController extractedController;
  String result = '';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    extractedController = TextEditingController(text: widget.document.extractedText ?? '');
    result = widget.document.aiSummary ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.document.title), actions: const [GlobalSearchButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('مشخصات سند'),
              subtitle: Text(
                'نوع: ${widget.document.documentType ?? 'ثبت نشده'}\n'
                'مسیر: ${widget.document.filePath ?? 'ثبت نشده'}\n'
                'توضیح: ${widget.document.notes ?? 'ثبت نشده'}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: extractedController,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'متن استخراج‌شده / متن سند',
              hintText: 'متن سند را اینجا وارد کن یا بعداً از OCR/PDF استخراج می‌شود.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await db.update(db.caseDocuments).replace(
                    widget.document.copyWith(
                      extractedText: Value(extractedController.text.trim()),
                    ),
                  );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('متن سند ذخیره شد')),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('ذخیره متن سند'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: loading ? null : _summarize,
            icon: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(loading ? 'در حال خلاصه‌سازی...' : 'خلاصه و استخراج نکات با AI'),
          ),
          const SizedBox(height: 16),
          if (result.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(result),
              ),
            ),
        ],
      ),
    );
  }


  String _anonymize(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'\b\d{10}\b'), '[شماره ملی]');
    text = text.replaceAll(RegExp(r'09\d{9}'), '[شماره تماس]');
    text = text.replaceAll(RegExp(r'\b\d{16}\b'), '[شماره کارت]');
    text = text.replaceAll(RegExp(r'\b\d{5,}\b'), '[شماره/شناسه]');
    text = text.replaceAll(RegExp(r'دادنامه\s*شماره\s*[^\s،.]+'), 'دادنامه شماره [حذف شد]');
    text = text.replaceAll(RegExp(r'پرونده\s*شماره\s*[^\s،.]+'), 'پرونده شماره [حذف شد]');
    return text;
  }

  Future<void> _summarize() async {
    final text = extractedController.text.trim();
    if (text.isEmpty) {
      setState(() => result = 'ابتدا متن سند را وارد یا ذخیره کن.');
      return;
    }

    setState(() {
      loading = true;
      result = '';
    });

    try {
      final db = ref.read(databaseProvider);
      final settings = await db.select(db.aiSettings).get();
      if (settings.isEmpty || !settings.first.isEnabled) {
        throw Exception('هوش مصنوعی فعال نیست. ابتدا API Key را ثبت کن.');
      }

      final safeText = _anonymize(text);
      final prompt = '''
تو دستیار حقوقی یک وکیل ایرانی هستی.
متن زیر قبل از ارسال به صورت اولیه ناشناس‌سازی شده است. با همین متن کار کن و اگر اطلاعات کافی نیست صریح بگو.
متن سند زیر را خلاصه کن و این موارد را استخراج کن:
۱. موضوع اصلی
۲. تاریخ‌ها و مهلت‌های مهم
۳. اشخاص و سمت‌ها
۴. نکات مؤثر برای دعوا
۵. ایرادات یا ریسک‌ها
۶. اقدام پیشنهادی بعدی

متن سند ناشناس‌شده:
$safeText
''';

      final service = OpenAiService(
        apiKey: settings.first.apiKey ?? '',
        model: settings.first.model,
      );

      final response = await service.sendPrompt(prompt);
      await db.update(db.caseDocuments).replace(
            widget.document.copyWith(
              extractedText: Value(text),
              aiSummary: Value(response),
            ),
          );

      setState(() => result = response);
    } catch (e) {
      setState(() => result = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}
