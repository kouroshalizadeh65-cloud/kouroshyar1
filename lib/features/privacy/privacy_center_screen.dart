import 'package:flutter/material.dart';

class PrivacyCenterScreen extends StatelessWidget {
  const PrivacyCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('اطلاعات محلی', 'پرونده‌ها و اطلاعات اصلی روی گوشی ذخیره می‌شوند.'),
      ('هوش آنلاین با اجازه', 'هیچ متن حساس بدون تأیید شما برای هوش آنلاین ارسال نمی‌شود.'),
      ('قفل برنامه', 'برای ورود می‌توان رمز و اثر انگشت فعال کرد.'),
      ('پشتیبان‌گیری', 'قبل از ورود اطلاعات واقعی، خروجی پشتیبان تهیه کن.'),
      ('حالت محرمانه', 'برای پرونده‌های حساس، بعداً امکان محدودسازی نمایش و ارسال اضافه می‌شود.'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('امنیت و حریم خصوصی')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.security),
              title: Text('حریم خصوصی کوروش‌یار'),
              subtitle: Text('هیچ اطلاعات حقوقی حساس بدون اجازه روشن و آگاهانه شما ارسال نمی‌شود.'),
            ),
          ),
          for (final item in items)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(item.$1),
                subtitle: Text(item.$2),
              ),
            ),
        ],
      ),
    );
  }
}
