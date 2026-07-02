import 'package:flutter/material.dart';

class LegalKnowledgeScreen extends StatelessWidget {
  const LegalKnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = {
      'ایرادات شکلی رایج': [
        'عدم توجه دعوا به خوانده',
        'ذی‌نفع نبودن خواهان',
        'عدم احراز سمت',
        'طرح نادرست خواسته',
        'عدم قابلیت استماع دعوا',
        'اعتبار امر مختومه',
      ],
      'چک‌لیست دعاوی مالی': [
        'احراز منشأ دین',
        'بررسی قرارداد، رسید، فاکتور یا اقرار',
        'محاسبه دقیق خواسته',
        'بررسی خسارت تأخیر تأدیه',
        'بررسی صلاحیت محلی و ذاتی',
      ],
      'چک‌لیست تجدیدنظر': [
        'تشخیص رأی شکلی یا ماهوی',
        'بررسی جهات تجدیدنظرخواهی',
        'تمرکز بر همان حدود رأی بدوی',
        'بررسی اظهارات شهود و ادله جدید',
        'طرح ایرادات شکلی نسبت به تجدیدنظرخواهی',
      ],
      'بانک ایده دفاعی': [
        'تأکید بر بار اثبات دعوا',
        'تفکیک دین شخصی از تعهد شرکتی',
        'ایراد به کلی‌گویی خواسته',
        'ایراد به نقل‌قولی بودن شهادت',
        'ارجاع به فقدان دلیل مستقیم',
      ],
    };

    return Scaffold(
      appBar: AppBar(title: const Text('بانک دانش حقوقی')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info),
              title: Text('نسخه اولیه بانک دانش'),
              subtitle: Text('بعداً با قوانین، آراء وحدت رویه و نظریات مشورتی قابل توسعه است.'),
            ),
          ),
          for (final entry in categories.entries)
            Card(
              child: ExpansionTile(
                title: Text(entry.key),
                children: [
                  for (final item in entry.value)
                    ListTile(leading: const Icon(Icons.check), title: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
