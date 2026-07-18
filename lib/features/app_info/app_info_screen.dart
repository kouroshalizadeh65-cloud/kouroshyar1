import 'package:flutter/material.dart';

import '../../core/app_info/app_version_service.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/widgets/global_settings_button.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('درباره کوروش‌یار'), actions: const [GlobalSettingsButton()]),
      body: FutureBuilder<AppVersionInfo>(
        future: AppVersionService.getInfo(),
        builder: (context, snapshot) {
          final version = snapshot.data;
          final versionText = snapshot.connectionState == ConnectionState.waiting
              ? 'در حال خواندن نسخه نصب‌شده…'
              : toPersianDigits((version ?? const AppVersionInfo.unavailable()).compactDisplay);
          final items = [
            ('نسخه', versionText),
            ('نام برنامه', 'کوروش‌یار'),
            ('نوع استفاده', 'نسخه شخصی برای مدیریت وکالت و کارهای روزانه'),
            ('اینترنت', 'فقط به‌روزرسانی اختیاری و امضاشده تعطیلات؛ اطلاعات شخصی ارسال نمی‌شود'),
            ('ذخیره‌سازی', 'اطلاعات اصلی به‌صورت محلی روی گوشی ذخیره می‌شود'),
            ('وضعیت', 'پایدارسازی داده، پشتیبان رمزگذاری‌شده و تعطیلات اختیاری امضاشده'),
          ];

          return ListView(
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
          );
        },
      ),
    );
  }
}
