import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import 'ai/legal_text_ai_screen.dart';
import '../../core/widgets/global_search_button.dart';

class LegalTextDetailScreen extends StatelessWidget {
  final LegalText item;

  const LegalTextDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          const GlobalSearchButton(),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => LegalTextAiScreen(item: item)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('تحلیل هوشمند متن'),
              subtitle: const Text('ناشناس‌سازی، استخراج کلیدواژه، بهبود متن و تحلیل استراتژی'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LegalTextAiScreen(item: item)),
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('مشخصات متن'),
              subtitle: Text(
                'نوع: ${item.type}\n'
                'موضوع: ${item.subject ?? 'ثبت نشده'}\n'
                'برچسب‌ها: ${item.tags ?? 'ثبت نشده'}\n'
                'کد: ${item.code ?? 'ثبت نشده'}\n'
                'نسخه: ${item.versionNumber}\n'
                'امتیاز: ${item.qualityScore?.toString() ?? 'ثبت نشده'}\n'
                'کاربرد: ${item.usageNote ?? 'ثبت نشده'}\n'
                'نکته موفقیت: ${item.successReason ?? 'ثبت نشده'}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('متن کامل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(item.body),
        ],
      ),
    );
  }
}
