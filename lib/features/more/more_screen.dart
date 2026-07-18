import 'package:flutter/material.dart';

import '../../core/widgets/global_settings_button.dart';

import '../app_info/app_info_screen.dart';
import '../checklists/checklists_screen.dart';
import '../health/app_health_screen.dart';
import '../legal_knowledge/legal_knowledge_screen.dart';
import '../legal_texts/legal_texts_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('بیشتر'), actions: const [GlobalSettingsButton()]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 24),
        children: [
          _section(context, 'ابزارهای حقوقی آفلاین', [
            _item(Icons.menu_book, 'بانک متون حقوقی', 'آرشیو آفلاین متون و نمونه‌های حقوقی', const LegalTextsScreen()),
            _item(Icons.checklist, 'چک‌لیست‌ها', 'چک‌لیست‌های کاربردی وکالتی؛ بازطراحی کامل در نسخه‌های بعدی', const ChecklistsScreen()),
            _item(Icons.school, 'دانش حقوقی', 'دانش و یادداشت‌های حقوقی آفلاین؛ بازطراحی کامل در نسخه‌های بعدی', const LegalKnowledgeScreen()),
          ]),
          _section(context, 'برنامه', [
            _item(Icons.person, 'ثبت‌نام / پروفایل', 'نام کاربری و اطلاعات لازم برای متون حقوقی', const ProfileScreen()),
            _item(Icons.settings, 'تنظیمات', 'تنظیمات عمومی برنامه', const SettingsScreen()),
            _item(Icons.health_and_safety, 'وضعیت سلامت برنامه', 'شمارش داده‌ها و عیب‌یابی سریع', const AppHealthScreen()),
            _item(Icons.info_outline, 'درباره کوروش‌یار', 'نسخه و وضعیت برنامه', const AppInfoScreen()),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<_MoreItem> items) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: items
            .map(
              (item) => ListTile(
                leading: Icon(item.icon),
                title: Text(item.title),
                subtitle: Text(item.subtitle),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.screen)),
              ),
            )
            .toList(),
      ),
    );
  }

  _MoreItem _item(IconData icon, String title, String subtitle, Widget screen) => _MoreItem(icon, title, subtitle, screen);
}

class _MoreItem {
  const _MoreItem(this.icon, this.title, this.subtitle, this.screen);
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
}
