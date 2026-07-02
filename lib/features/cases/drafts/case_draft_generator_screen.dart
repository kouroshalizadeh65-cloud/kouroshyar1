import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../database/app_database.dart';
import '../../../database/database_provider.dart';
import '../../../core/utils/date_format_fa.dart';
import '../../ai/openai_service.dart';

class CaseDraftGeneratorScreen extends ConsumerStatefulWidget {
  final Case item;
  const CaseDraftGeneratorScreen({super.key, required this.item});

  @override
  ConsumerState<CaseDraftGeneratorScreen> createState() => _CaseDraftGeneratorScreenState();
}

class _CaseDraftGeneratorScreenState extends ConsumerState<CaseDraftGeneratorScreen> {
  final extraController = TextEditingController(text: 'متن را رسمی، خلاصه، مؤثر و آماده ویرایش نهایی تنظیم کن.');
  String selectedType = 'لایحه';
  String result = '';
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تولید متن از پرونده')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: ListTile(title: Text(widget.item.title), subtitle: Text('${widget.item.subject ?? 'بدون موضوع'} | ${widget.item.stage ?? 'مرحله ثبت نشده'}'))),
          DropdownButtonFormField<String>(
            initialValue: selectedType,
            items: const [
              DropdownMenuItem(value: 'لایحه', child: Text('لایحه')),
              DropdownMenuItem(value: 'دادخواست', child: Text('دادخواست')),
              DropdownMenuItem(value: 'شکواییه', child: Text('شکواییه')),
              DropdownMenuItem(value: 'اظهارنامه', child: Text('اظهارنامه')),
              DropdownMenuItem(value: 'قرارداد', child: Text('قرارداد')),
              DropdownMenuItem(value: 'خلاصه پرونده', child: Text('خلاصه پرونده')),
            ],
            onChanged: (v) { if (v != null) setState(() => selectedType = v); },
            decoration: const InputDecoration(labelText: 'نوع متن'),
          ),
          const SizedBox(height: 12),
          TextField(controller: extraController, maxLines: 5, decoration: const InputDecoration(labelText: 'دستور تکمیلی', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : _generate,
            icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
            label: Text(loading ? 'در حال تولید...' : 'تولید متن'),
          ),
          if (result.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _saveDraft, icon: const Icon(Icons.save), label: const Text('ذخیره پیش‌نویس')),
            OutlinedButton.icon(onPressed: _saveToLegalTexts, icon: const Icon(Icons.menu_book), label: const Text('ذخیره در بانک متون')),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(result))),
          ],
        ],
      ),
    );
  }

  Future<void> _generate() async {
    setState(() { loading = true; result = ''; });
    try {
      final db = ref.read(databaseProvider);
      final settings = await db.select(db.aiSettings).get();
      if (settings.isEmpty || !settings.first.isEnabled) throw Exception('هوش مصنوعی فعال نیست. ابتدا API Key را ثبت کن.');

      final tasks = await (db.select(db.tasks)..where((t) => t.caseId.equals(widget.item.id))).get();
      final deadlines = await (db.select(db.deadlines)..where((d) => d.caseId.equals(widget.item.id))).get();
      final docs = await (db.select(db.caseDocuments)..where((d) => d.caseId.equals(widget.item.id))).get();
      final events = await (db.select(db.caseTimelineEvents)..where((e) => e.caseId.equals(widget.item.id))).get();
      final legalTexts = await db.select(db.legalTexts).get();
      final profiles = await db.select(db.userProfiles).get();
      final profile = profiles.isNotEmpty ? profiles.first : null;
      final profileParts = <String>[];
      if (profile != null) {
        if (profile.useNameInLegalTexts && (profile.displayName ?? '').trim().isNotEmpty) {
          profileParts.add('نام کاربر/وکیل: ${profile.displayName}');
        }
        if (profile.useLicenseInLegalTexts && (profile.licenseNumber ?? '').trim().isNotEmpty) {
          profileParts.add('شماره پروانه: ${profile.licenseNumber}');
        }
        if (profile.useBarInLegalTexts && (profile.barAssociation ?? '').trim().isNotEmpty) {
          profileParts.add('کانون/مرکز: ${profile.barAssociation}');
        }
        if ((profile.legalTitle ?? '').trim().isNotEmpty) {
          profileParts.add('عنوان: ${profile.legalTitle}');
        }
      }
      final profileInstruction = profileParts.isEmpty
          ? 'اطلاعات هویتی کاربر را در متن وارد نکن مگر با جای خالی مناسب.'
          : 'در صورت تناسب، فقط از این اطلاعات پروفایل استفاده کن: ${profileParts.join(' | ')}';

      final prompt = '''
تو دستیار حقوقی یک وکیل ایرانی هستی.
یک «$selectedType» فارسی، منظم، رسمی، قابل ویرایش و آماده استفاده اولیه تنظیم کن.
از جعل ماده قانونی یا رأی خودداری کن. اگر اطلاعات کافی نیست، جای خالی مناسب بگذار.
$profileInstruction

دستور تکمیلی:
${extraController.text.trim()}

اطلاعات پرونده:
عنوان: ${widget.item.title}
موکل: ${widget.item.clientName ?? ''}
طرف مقابل: ${widget.item.opponentName ?? ''}
موضوع: ${widget.item.subject ?? ''}
مرجع: ${widget.item.court ?? ''}
شعبه: ${widget.item.branch ?? ''}
قاضی: ${widget.item.judge ?? ''}
شماره پرونده: ${widget.item.caseNumber ?? ''}
مرحله: ${widget.item.stage ?? ''}
اقدام بعدی: ${widget.item.nextAction ?? ''}

کارها:
${tasks.map((t) => '- ${t.title} | ${t.priority} | ${t.isDone ? 'انجام شده' : 'باز'}').join('\n')}

مهلت‌ها:
${deadlines.map((d) => '- ${d.title} | ${d.deadlineType ?? ''} | ${formatPersianLongDate(d.dueDate)}').join('\n')}

اسناد:
${docs.map((d) => '- ${d.title} | ${d.documentType ?? ''} | ${d.extractedText ?? ''} | خلاصه: ${d.aiSummary ?? ''}').join('\n')}

خط زمان:
${events.map((e) => '- ${formatPersianLongDate(e.eventDate)}: ${e.title} | ${e.eventType ?? ''} | ${e.description ?? ''}').join('\n')}

متون ذخیره‌شده مرتبط:
${legalTexts.take(10).map((t) => '- ${t.title} | ${t.type} | ${t.subject ?? ''} | ${t.usageNote ?? ''}').join('\n')}
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

  Future<void> _saveDraft() async {
    if (result.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    await db.into(db.generatedDrafts).insert(
      GeneratedDraftsCompanion.insert(
        caseId: Value(widget.item.id),
        title: '$selectedType - ${widget.item.title}',
        draftType: selectedType,
        body: result,
        prompt: Value(extraController.text.trim()),
      ),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پیش‌نویس ذخیره شد')));
  }

  Future<void> _saveToLegalTexts() async {
    if (result.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    await db.into(db.legalTexts).insert(
      LegalTextsCompanion.insert(
        title: '$selectedType - ${widget.item.title}',
        type: selectedType,
        body: result,
        subject: Value(widget.item.subject ?? ''),
        tags: const Value('تولیدشده با هوش مصنوعی'),
        usageNote: Value('تولیدشده از پرونده ${widget.item.title}'),
      ),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('در بانک متون ذخیره شد')));
  }
}
