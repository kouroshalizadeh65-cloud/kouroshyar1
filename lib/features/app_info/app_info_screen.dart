import 'package:flutter/material.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('نسخه', '۳.۵.۰'),
      ('نام برنامه', 'کوروش‌یار'),
      ('نوع استفاده', 'نسخه شخصی برای مدیریت وکالت و کارهای روزانه'),
      ('هوش آنلاین', 'فقط با اجازه کاربر و پس از تنظیم API Key'),
      ('ذخیره‌سازی', 'اطلاعات اصلی به‌صورت محلی روی گوشی ذخیره می‌شود'),
      ('وضعیت', 'بازطراحی هسته تجربه کاربری: خانه جدید، ثبت سریع شناور، نوار پایین ساده‌تر و دسترسی دائمی به جستجو'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('درباره کوروش‌یار')),
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
