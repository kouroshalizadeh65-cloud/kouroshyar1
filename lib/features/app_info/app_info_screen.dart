import 'package:flutter/material.dart';

import '../../core/widgets/global_settings_button.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('نسخه', '۳.۶.۶۰+۱۳۲'),
      ('نام برنامه', 'کوروش‌یار'),
      ('نوع استفاده', 'نسخه شخصی برای مدیریت وکالت و کارهای روزانه'),
      ('هوش آنلاین', 'مسیرهای دستیار آنلاین در رابط کاربری نسخه فعلی حذف شده‌اند'),
      ('ذخیره‌سازی', 'اطلاعات اصلی به‌صورت محلی روی گوشی ذخیره می‌شود'),
      ('وضعیت', 'پشتیبان رمزگذاری‌شده، بازیابی امن و عیب‌یابی اعلان‌ها'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('درباره کوروش‌یار'), actions: const [GlobalSettingsButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.gavel),
              title: Text('کوروش‌یار'),
              subtitle: Text('دستیار شخصی و حقوقی کوروش'),
            ),
          ),
          for (final item in items)
            Card(
              child: ListTile(
                title: Text(item.$1),
                subtitle: Text(item.$2),
              ),
            ),
        ],
      ),
    );
  }
}
