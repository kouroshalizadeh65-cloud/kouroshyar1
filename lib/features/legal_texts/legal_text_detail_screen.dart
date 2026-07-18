import 'package:flutter/material.dart';

import '../../core/widgets/global_settings_button.dart';
import '../../database/app_database.dart';

class LegalTextDetailScreen extends StatelessWidget {
  final LegalText item;

  const LegalTextDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: const [GlobalSettingsButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
