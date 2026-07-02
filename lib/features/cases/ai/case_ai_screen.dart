import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../database/app_database.dart';
import '../../../database/database_provider.dart';
import '../../../core/utils/date_format_fa.dart';
import '../../ai/openai_service.dart';

class CaseAiScreen extends ConsumerStatefulWidget {
  final Case item;

  const CaseAiScreen({super.key, required this.item});

  @override
  ConsumerState<CaseAiScreen> createState() => _CaseAiScreenState();
}

class _CaseAiScreenState extends ConsumerState<CaseAiScreen> {
  String result = '';
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تحلیل هوشمند ${widget.item.title}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('پرونده'),
              subtitle: Text(
                'عنوان: ${widget.item.title}\n'
                'موکل: ${widget.item.clientName ?? 'ثبت نشده'}\n'
                'طرف مقابل: ${widget.item.opponentName ?? 'ثبت نشده'}\n'
                'موضوع: ${widget.item.subject ?? 'ثبت نشده'}\n'
                'مرحله: ${widget.item.stage ?? 'ثبت نشده'}\n'
                'اقدام بعدی: ${widget.item.nextAction ?? 'ثبت نشده'}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionButton(
            title: 'تحلیل پرونده',
            icon: Icons.psychology,
            onTap: () => _run('پرونده را از نظر نقاط قوت، نقاط ضعف، ریسک‌ها، نقص مدارک و اقدام بعدی تحلیل کن.'),
          ),
          _ActionButton(
            title: 'پیشنهاد دفاع',
            icon: Icons.shield,
            onTap: () => _run('برای این پرونده دفاعیات احتمالی و ایرادات شکلی و ماهوی قابل طرح را پیشنهاد بده.'),
          ),
          _ActionButton(
            title: 'پیش‌نویس لایحه',
            icon: Icons.description,
            onTap: () => _run('بر اساس اطلاعات موجود، یک پیش‌نویس لایحه کوتاه، مؤثر و قابل تکمیل تهیه کن.'),
          ),
          _ActionButton(
            title: 'تجربه‌های مشابه',
            icon: Icons.lightbulb,
            onTap: () => _run('با توجه به بانک تجربه و اطلاعات پرونده، تجربه‌های مشابه، استراتژی‌های مؤثر قبلی و نکات قابل تکرار را پیشنهاد بده.'),
          ),
          _ActionButton(
            title: 'چک‌لیست جلسه',
            icon: Icons.checklist,
            onTap: () => _run('برای جلسه دادگاه این پرونده، چک‌لیست مدارک، نکات دفاعی و پرسش‌های مهم را تهیه کن.'),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(child: CircularProgressIndicator()),
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

  Future<void> _run(String instruction) async {
    setState(() {
      loading = true;
      result = '';
    });

    try {
      final db = ref.read(databaseProvider);
      final settings = await db.select(db.aiSettings).get();
      if (settings.isEmpty || !settings.first.isEnabled) {
        throw Exception('هوش مصنوعی فعال نیست. ابتدا از تنظیمات، API Key را ثبت و فعال کن.');
      }

      final tasks = await (db.select(db.tasks)..where((t) => t.caseId.equals(widget.item.id))).get();
      final deadlines = await (db.select(db.deadlines)..where((d) => d.caseId.equals(widget.item.id))).get();
      final docs = await (db.select(db.caseDocuments)..where((d) => d.caseId.equals(widget.item.id))).get();
      final events = await (db.select(db.caseTimelineEvents)..where((e) => e.caseId.equals(widget.item.id))).get();
      final experiences = await db.select(db.experienceItems).get();

      final prompt = '''
تو دستیار حقوقی یک وکیل ایرانی هستی. پاسخ باید فارسی، دقیق، کاربردی، منظم و قابل استفاده برای وکیل باشد.
تصمیم نهایی با وکیل است؛ اگر اطلاعات ناقص است صریحاً بگو.

درخواست:
$instruction

اطلاعات پرونده:
عنوان: ${widget.item.title}
سمت اصلی موکل: ${widget.item.clientRole ?? ''}
سمت در مرحله فعلی: ${widget.item.currentRole ?? ''}
موضوع: ${widget.item.subject ?? ''}
مرجع رسیدگی: ${widget.item.court == null ? '' : 'ثبت شده'}
شعبه: ${widget.item.branch == null ? '' : 'ثبت شده'}
شماره پرونده: ${widget.item.caseNumber == null ? '' : 'ثبت شده'}
مرحله: ${widget.item.stage ?? ''}
اقدام بعدی: ${widget.item.nextAction ?? ''}

کارهای پرونده:
${tasks.map((t) => '- ${t.title} | اولویت: ${t.priority} | انجام: ${t.isDone ? 'بله' : 'خیر'}').join('\n')}

مهلت‌ها:
${deadlines.map((d) => '- ${d.title} | ${d.deadlineType ?? ''} | ${formatPersianLongDate(d.dueDate)} | انجام: ${d.isDone ? 'بله' : 'خیر'}').join('\n')}

اسناد ثبت‌شده:
${docs.map((d) => '- ${d.title} | ${d.documentType ?? ''} | ${d.notes ?? ''}').join('\n')}

خط زمان:
${events.map((e) => '- ${formatPersianLongDate(e.eventDate)}: ${e.title} | ${e.eventType ?? ''} | ${e.description ?? ''}').join('\n')}

بانک تجربه:
${experiences.map((e) => '- ${e.title} | نتیجه: ${e.result ?? ''} | استراتژی: ${e.effectiveStrategy ?? ''} | نکته آینده: ${e.futureTip ?? ''}').join('\n')}
''';

      final service = OpenAiService(
        apiKey: settings.first.apiKey ?? '',
        model: settings.first.model,
      );

      final response = await service.sendPrompt(prompt);
      setState(() => result = response);
    } catch (e) {
      setState(() => result = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.arrow_back_ios_new),
        onTap: onTap,
      ),
    );
  }
}
