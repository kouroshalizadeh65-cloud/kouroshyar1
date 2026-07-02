import 'package:flutter/material.dart';

class AiPromptTemplatesScreen extends StatelessWidget {
  const AiPromptTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final templates = [
      'پرونده را از نظر نقاط قوت، نقاط ضعف، ریسک‌ها و اقدام بعدی تحلیل کن.',
      'برای این پرونده پیش‌نویس لایحه دفاعیه کوتاه و مؤثر تهیه کن.',
      'برای این موضوع دادخواست استاندارد با خواسته، دلایل و شرح ماوقع بنویس.',
      'این متن حقوقی را ناشناس‌سازی و برای ذخیره در بانک متون آماده کن.',
      'از این لایحه، استراتژی حقوقی، مواد قانونی و برچسب‌های مناسب استخراج کن.',
      'برای جلسه دادگاه، چک‌لیست مدارک و نکات دفاعی تهیه کن.',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('قالب‌های آماده هوش مصنوعی')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final text = templates[index];
          return Card(
            child: ListTile(
              title: Text(text),
              leading: const Icon(Icons.auto_awesome),
              onTap: () {
                Navigator.pop(context, text);
              },
            ),
          );
        },
      ),
    );
  }
}
