import 'package:flutter/material.dart';
import '../ai/ai_assistant_screen.dart';
import '../ai/ai_settings_screen.dart';
import '../app_info/app_info_screen.dart';
import '../backup/advanced_backup_screen.dart';
import '../backup/backup_screen.dart';
import '../calendar/calendar_screen.dart';
import '../checklists/checklists_screen.dart';
import '../deadlines/deadlines_screen.dart';
import '../documents/documents_screen.dart';
import '../drafts/generated_drafts_screen.dart';
import '../experience/experience_screen.dart';
import '../export/csv_export_screen.dart';
import '../export/export_text_screen.dart';
import '../finance/finance_screen.dart';
import '../kourosh_suggestions/kourosh_suggestions_screen.dart';
import '../legal_knowledge/legal_knowledge_screen.dart';
import '../personal_assistant/personal_assistant_screen.dart';
import '../privacy/privacy_center_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/reports_screen.dart';
import '../search/global_search_screen.dart';
import '../security/security_screen.dart';
import '../settings/settings_screen.dart';
import '../health/app_health_screen.dart';
import '../home/home_screen.dart';
import '../kourosh_command/kourosh_command_screen.dart';
import '../legal_texts/legal_texts_screen.dart';
import '../quick_entry/quick_entry_screen.dart';
import '../tasks/tasks_screen.dart';
import '../../core/widgets/global_search_button.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بیشتر'), actions: const [GlobalSearchButton()]),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section(context, 'مسیرهای اصلی', [
            _item(Icons.home, 'خانه', 'مرکز تصمیم روزانه و مسیرهای اصلی', const HomeScreen()),
            _item(Icons.add_circle, 'فرمان سریع', 'ثبت متنی یا هدایت سریع به ثبت کار، مهلت، جلسه و مالی', const KouroshCommandScreen()),
            _item(Icons.inbox, 'ثبت سریع دستی', 'ثبت سریع ورودی‌ها بدون ورود به چند صفحه', const QuickEntryScreen()),
            _item(Icons.menu_book, 'بانک متون حقوقی', 'جستجو و استفاده از متون حقوقی آماده', const LegalTextsScreen()),
          ]),
          _section(context, 'کارها و مهلت‌ها', [
            _item(Icons.task_alt, 'کارها', 'مدیریت کارهای شخصی و پرونده‌ای', const TasksScreen()),
            _item(Icons.alarm, 'مهلت‌ها', 'مهلت‌های حقوقی و اداری', const DeadlinesScreen()),
            _item(Icons.calendar_month, 'تقویم', 'نمای شمسی کارها و مهلت‌ها', const CalendarScreen()),
            _item(Icons.bar_chart, 'گزارش‌ها', 'جمع‌بندی پرونده‌ها، کارها و مالی', const ReportsScreen()),
            _item(Icons.payments, 'مالی', 'هزینه‌ها و دریافت‌ها', const FinanceScreen()),
          ]),
          _section(context, 'پرونده و وکالت', [
            _item(Icons.folder_copy, 'مدارک پرونده‌ها', 'فهرست مدارک و پیوست‌ها', const DocumentsScreen()),
            _item(Icons.psychology, 'بانک تجربه', 'نکته‌ها و تجربه‌های پرونده‌ای', const ExperienceScreen()),
            _item(Icons.checklist, 'چک‌لیست‌ها', 'چک‌لیست‌های کاربردی وکالتی', const ChecklistsScreen()),
            _item(Icons.school, 'دانش حقوقی', 'یادداشت‌های حقوقی و چارچوب‌های کاربردی', const LegalKnowledgeScreen()),
            _item(Icons.article, 'پیش‌نویس‌های تولیدشده', 'متون ذخیره‌شده از دستیار', const GeneratedDraftsScreen()),
          ]),
          _section(context, 'جستجو و دستیار', [
            _item(Icons.search, 'جستجوی سراسری', 'جستجو در داده‌های اصلی برنامه', const GlobalSearchScreen()),
            _item(Icons.lightbulb, 'پیشنهاد کوروش‌یار', 'پیشنهادهای کوتاه و قابل اقدام', const KouroshSuggestionsScreen()),
            _item(Icons.assistant, 'دستیار شخصی کوروش‌یار', 'کمک برای جمع‌بندی و برنامه‌ریزی', const PersonalAssistantScreen()),
            _item(Icons.smart_toy, 'دستیار هوش مصنوعی', 'تحلیل و تولید متن با اجازه کاربر', const AiAssistantScreen()),
            _item(Icons.key, 'تنظیمات هوش مصنوعی', 'فعال‌سازی اختیاری اتصال هوشمند', const AiSettingsScreen()),
          ]),
          _section(context, 'امنیت، پشتیبان و خروجی', [
            _item(Icons.lock, 'امنیت', 'رمز، اثر انگشت و قفل خودکار', const SecurityScreen()),
            _item(Icons.privacy_tip, 'حریم خصوصی', 'اصول محرمانگی و ذخیره‌سازی محلی', const PrivacyCenterScreen()),
            _item(Icons.backup, 'پشتیبان‌گیری', 'پشتیبان خودکار و بازیابی', const BackupScreen()),
            _item(Icons.cloud_download, 'پشتیبان‌گیری پیشرفته', 'خروجی JSON و گزارش TXT', const AdvancedBackupScreen()),
            _item(Icons.description, 'خروجی متنی', 'خروجی قابل کپی از اطلاعات اصلی', const ExportTextScreen()),
            _item(Icons.file_download, 'خروجی CSV', 'خروجی برای Excel', const CsvExportScreen()),
          ]),
          _section(context, 'برنامه', [
            _item(Icons.person, 'ثبت‌نام / پروفایل', 'نام کاربری و تنظیمات استفاده در متون حقوقی', const ProfileScreen()),
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
        initiallyExpanded: title == 'کارها و مهلت‌ها',
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
