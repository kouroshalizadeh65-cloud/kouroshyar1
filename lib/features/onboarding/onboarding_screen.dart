import 'package:flutter/material.dart';

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onStart;

  const OnboardingScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('پرونده‌ها', 'پرونده، اسناد، خط زمان، کارها و مهلت‌ها را یکجا مدیریت کن.'),
      ('بانک متون', 'لوایح، دادخواست‌ها و متون موفق را ذخیره و جستجو کن.'),
      ('هوش مصنوعی', 'با API شخصی، تحلیل پرونده و تولید متن را مستقیم روی گوشی انجام بده.'),
      ('پشتیبان‌گیری', 'از داده‌ها خروجی JSON، TXT و CSV بگیر.'),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('به کوروش‌یار خوش آمدی')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.gavel, size: 72),
            const SizedBox(height: 16),
            const Text(
              'کوروش‌یار؛ دستیار مدیریت دفتر وکالت',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            for (final item in items)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(item.$1),
                  subtitle: Text(item.$2),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.arrow_back),
              label: const Text('شروع استفاده'),
            ),
          ],
        ),
      ),
    );
  }
}
