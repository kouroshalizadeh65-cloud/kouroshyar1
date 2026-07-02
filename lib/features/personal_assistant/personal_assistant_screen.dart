import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';
import '../ai/openai_service.dart';

class PersonalAssistantScreen extends ConsumerStatefulWidget {
  const PersonalAssistantScreen({super.key});

  @override
  ConsumerState<PersonalAssistantScreen> createState() => _PersonalAssistantScreenState();
}

class _PersonalAssistantScreenState extends ConsumerState<PersonalAssistantScreen> {
  final controller = TextEditingController();
  final messages = <_AssistantMessage>[];
  bool loading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دستیار شخصی کوروش‌یار'),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'اینجا می‌توانی درباره پرونده‌ها، مهلت‌ها، متون حقوقی، تجربه‌ها و کارهای دفتر از کوروش‌یار سؤال کنی.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final m = messages[index];
                      return Align(
                        alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(m.text),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (loading) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'سؤال یا درخواستت را بنویس',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: loading ? null : _send,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add(_AssistantMessage(text: text, isUser: true));
      controller.clear();
      loading = true;
    });

    try {
      final db = ref.read(databaseProvider);
      final settings = await db.select(db.aiSettings).get();
      if (settings.isEmpty || !settings.first.isEnabled) {
        throw Exception('هوش مصنوعی فعال نیست. ابتدا API Key را در تنظیمات هوش مصنوعی وارد کن.');
      }

      final cases = await db.select(db.cases).get();
      final tasks = await db.select(db.tasks).get();
      final deadlines = await db.select(db.deadlines).get();
      final legalTexts = await db.select(db.legalTexts).get();
      final experiences = await db.select(db.experienceItems).get();
      final finance = await db.select(db.financeItems).get();

      final contextText = '''
پرونده‌ها:
${cases.map((c) => '- ${c.title} | ${c.subject ?? ''} | ${c.stage ?? ''} | اقدام بعدی: ${c.nextAction ?? ''}').join('\n')}

کارها:
${tasks.map((t) => '- ${t.title} | اولویت: ${t.priority} | انجام: ${t.isDone ? 'بله' : 'خیر'} | مهلت: ${t.dueDate == null ? '' : formatPersianLongDate(t.dueDate!)}').join('\n')}

مهلت‌ها:
${deadlines.map((d) => '- ${d.title} | ${d.deadlineType ?? ''} | ${formatPersianLongDate(d.dueDate)} | انجام: ${d.isDone ? 'بله' : 'خیر'}').join('\n')}

بانک متون:
${legalTexts.take(30).map((t) => '- ${t.title} | ${t.type} | ${t.subject ?? ''} | ${t.tags ?? ''}').join('\n')}

بانک تجربه:
${experiences.map((e) => '- ${e.title} | نتیجه: ${e.result ?? ''} | استراتژی: ${e.effectiveStrategy ?? ''} | نکته آینده: ${e.futureTip ?? ''}').join('\n')}

مالی:
${finance.map((f) => '- ${f.type} | ${f.title} | ${f.amount}').join('\n')}
''';

      final prompt = '''
تو کوروش‌یار هستی؛ دستیار شخصی یک وکیل ایرانی.
فقط بر اساس اطلاعات موجود و با احتیاط پاسخ بده.
اگر اطلاعات ناقص است صریح بگو.
پاسخ فارسی، عملی، کوتاه و قابل اجرا بده.

اطلاعات داخلی برنامه:
$contextText

گفت‌وگوی اخیر:
${messages.map((m) => '${m.isUser ? 'کاربر' : 'کوروش‌یار'}: ${m.text}').join('\n')}

درخواست جدید:
$text
''';

      final service = OpenAiService(
        apiKey: settings.first.apiKey ?? '',
        model: settings.first.model,
      );

      final response = await service.sendPrompt(prompt);
      setState(() => messages.add(_AssistantMessage(text: response, isUser: false)));
    } catch (e) {
      setState(() => messages.add(_AssistantMessage(text: e.toString(), isUser: false)));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

class _AssistantMessage {
  final String text;
  final bool isUser;

  _AssistantMessage({
    required this.text,
    required this.isUser,
  });
}
