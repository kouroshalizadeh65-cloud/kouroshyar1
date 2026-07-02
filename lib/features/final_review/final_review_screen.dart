import 'package:flutter/material.dart';

class FinalReviewScreen extends StatelessWidget {
  const FinalReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('پرونده‌ها', 'ثبت، ویرایش، اتاق پرونده، اسناد، خط زمان و کارها'),
      ('مهلت‌ها', 'ثبت و نمایش مهلت‌های نزدیک و فوری'),
      ('بانک متون', 'ذخیره، جستجو، امتیازدهی و تحلیل هوشمند'),
      ('هوش مصنوعی', 'تحلیل پرونده، تولید متن، خلاصه سند و جستجوی معنایی'),
      ('امنیت', 'قفل برنامه با رمز و اثر انگشت'),
      ('پشتیبان‌گیری', 'JSON، TXT و CSV'),
      ('گزارش‌ها', 'داشبورد، گزارش روزانه و خروجی قابل کپی'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('مرور نسخه ۲.۰')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified),
              title: Text('کوروش‌یار v2.0'),
              subtitle: Text('نسخه شخصی برای استفاده اولیه در دفتر وکالت.'),
            ),
          ),
          for (final item in items)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle),
                title: Text(item.$1),
                subtitle: Text(item.$2),
              ),
            ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('نکته قبل از استفاده واقعی'),
              subtitle: Text('پیش از ورود اطلاعات حساس، تنظیمات امنیتی و پشتیبان‌گیری را فعال کن.'),
            ),
          ),
        ],
      ),
    );
  }
}
