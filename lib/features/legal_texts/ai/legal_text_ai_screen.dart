import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../database/app_database.dart';
import '../../../database/database_provider.dart';
import '../../ai/openai_service.dart';

class LegalTextAiScreen extends ConsumerStatefulWidget {
  final LegalText item;

  const LegalTextAiScreen({super.key, required this.item});

  @override
  ConsumerState<LegalTextAiScreen> createState() => _LegalTextAiScreenState();
}

class _LegalTextAiScreenState extends ConsumerState<LegalTextAiScreen> {
  String result = '';
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('هوش مصنوعی متن'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(widget.item.title),
              subtitle: Text('${widget.item.type} | ${widget.item.subject ?? 'بدون موضوع'}'),
            ),
          ),
          _ActionButton(
            title: 'ناشناس‌سازی متن',
            icon: Icons.privacy_tip,
            onTap: () => _run('این متن حقوقی را ناشناس‌سازی کن؛ نام اشخاص، شماره‌ها، کلاسه پرونده، شعبه و اطلاعات محرمانه را حذف و با جای‌خالی مناسب جایگزین کن.'),
          ),
          _ActionButton(
            title: 'استخراج برچسب و کلیدواژه',
            icon: Icons.sell,
            onTap: () => _run('از این متن، نوع متن، موضوع، کلیدواژه‌ها، برچسب‌ها، مواد قانونی احتمالی و کاربردهای عملی را استخراج کن.'),
          ),
          _ActionButton(
            title: 'خلاصه استراتژی حقوقی',
            icon: Icons.psychology,
            onTap: () => _run('استراتژی حقوقی، ایرادات شکلی، ایرادات ماهوی، نقاط قوت و نقاط ضعف این متن را خلاصه کن.'),
          ),
          _ActionButton(
            title: 'بهبود متن',
            icon: Icons.auto_fix_high,
            onTap: () => _run('این متن را از نظر ادبیات حقوقی، انسجام، اختصار، اثرگذاری و ساختار دفاعی بهتر کن؛ متن پیشنهادی نهایی بده.'),
          ),
          const SizedBox(height: 16),
          if (loading) const Center(child: CircularProgressIndicator()),
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

      final prompt = '''
تو دستیار حقوقی یک وکیل ایرانی هستی. پاسخ را فارسی، دقیق، کاربردی و منظم بده.
در ناشناس‌سازی، اطلاعات محرمانه را حذف کن و ساختار حقوقی متن را حفظ کن.

درخواست:
$instruction

مشخصات متن:
عنوان: ${widget.item.title}
نوع: ${widget.item.type}
موضوع: ${widget.item.subject ?? ''}
برچسب‌ها: ${widget.item.tags ?? ''}
کاربرد: ${widget.item.usageNote ?? ''}
نکته موفقیت: ${widget.item.successReason ?? ''}

متن:
${widget.item.body}
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
