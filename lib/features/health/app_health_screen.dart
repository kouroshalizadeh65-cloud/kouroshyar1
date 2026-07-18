import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../database/app_database.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/widgets/global_settings_button.dart';

class AppHealthScreen extends ConsumerWidget {
  const AppHealthScreen({super.key});

  Future<_HealthData> _load(AppDatabase db) async {
    final results = await Future.wait<Object>([
      db.select(db.cases).get(),
      db.select(db.tasks).get(),
      db.select(db.deadlines).get(),
      db.select(db.financeItems).get(),
      db.select(db.caseTimelineEvents).get(),
      db.select(db.inboxItems).get(),
    ]);
    return _HealthData(
      cases: results[0] as List<Case>,
      tasks: results[1] as List<Task>,
      deadlines: results[2] as List<Deadline>,
      financeItems: results[3] as List<FinanceItem>,
      timelineEvents: results[4] as List<CaseTimelineEvent>,
      inboxItems: results[5] as List<InboxItem>,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('وضعیت سلامت برنامه'), actions: const [GlobalSettingsButton()]),
      body: FutureBuilder<_HealthData>(
        future: _load(db),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('وضعیت سلامت در حال بارگذاری دوباره است.'),
                    subtitle: Text('در خواندن داده‌ها خطا رخ داد. دوباره تلاش کنید.'),
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final openTasks = data.tasks.where((e) => !e.isDone).length;
          final openDeadlines = data.deadlines.where((e) => !e.isDone).length;
          final activeCases = data.cases.where((e) => e.status != 'مختومه' && e.status != 'غیرفعال').length;
          final attachedFiles = data.timelineEvents.where((e) => (e.attachmentPath ?? '').trim().isNotEmpty).length +
              data.financeItems.where((e) => (e.attachmentPath ?? '').trim().isNotEmpty).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.health_and_safety),
                  title: Text('خلاصه سلامت داده‌ها'),
                  subtitle: Text('این صفحه برای عیب‌یابی سریع و تشخیص خالی بودن یا وجود داده‌هاست.'),
                ),
              ),
              _row('پرونده‌ها', data.cases.length, 'فعال: ${toPersianDigits(activeCases)}'),
              _row('کارها', data.tasks.length, 'باز: ${toPersianDigits(openTasks)}'),
              _row('مهلت‌ها', data.deadlines.length, 'باز: ${toPersianDigits(openDeadlines)}'),
              _row('مالی', data.financeItems.length, 'ثبت‌های درآمد و هزینه'),
              _row('پیوست‌ها', attachedFiles, 'مدارک متصل به تاریخچه و مالی'),
              _row('تاریخچه پرونده', data.timelineEvents.length, 'رویدادها و جلسات پرونده'),
              _row('ورودی‌ها', data.inboxItems.length, 'ورودی‌های ثبت‌شده در برنامه'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('پاکسازی فایل‌های بلااستفاده'),
                  subtitle: const Text('فقط فایل‌هایی حذف می‌شوند که هیچ رکوردی در مدارک، تاریخچه یا امور مالی به آن‌ها متصل نیست.'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _cleanupOrphanFiles(context, db),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('قاعده نسخه پایدارسازی'),
                  subtitle: Text('صفحات اصلی باید حالت خالی، بارگذاری و خطا را جدا نشان دهند و نباید خطای گذرا به‌عنوان شکست صفحه نمایش داده شود.'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }


  Future<void> _cleanupOrphanFiles(BuildContext context, AppDatabase db) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('پاکسازی فایل‌های بلااستفاده'),
            content: const Text('فایل‌های دارای رکورد حذف نمی‌شوند. ادامه می‌دهید؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('پاکسازی')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final result = await db.cleanupOrphanAttachments();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${toPersianDigits(result.deleted)} فایل بلااستفاده حذف شد؛ '
          '${toPersianDigits(result.kept)} فایل متصل حفظ شد'
          '${result.failed == 0 ? '.' : '؛ حذف ${toPersianDigits(result.failed)} فایل ناموفق بود.'}',
        ),
      ),
    );
  }

  Widget _row(String title, int count, String subtitle) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.data_usage),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text(toPersianDigits(count), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _HealthData {
  const _HealthData({
    required this.cases,
    required this.tasks,
    required this.deadlines,
    required this.financeItems,
    required this.timelineEvents,
    required this.inboxItems,
  });

  final List<Case> cases;
  final List<Task> tasks;
  final List<Deadline> deadlines;
  final List<FinanceItem> financeItems;
  final List<CaseTimelineEvent> timelineEvents;
  final List<InboxItem> inboxItems;
}
