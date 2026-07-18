import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/screen_capture_service.dart';
import '../../core/theme/app_theme_controller.dart';
import '../../core/utils/persian_numbers.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../app_info/app_info_screen.dart';
import '../backup/backup_screen.dart';
import '../health/app_health_screen.dart';
import '../notifications/notification_service.dart';
import '../profile/profile_screen.dart';
import '../security/security_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: StreamBuilder<List<SecuritySetting>>(
        stream: db.select(db.securitySettings).watch(),
        builder: (context, snapshot) {
          final settings = snapshot.data ?? const <SecuritySetting>[];
          final current = settings.isEmpty ? null : settings.first;
          final screenCaptureAllowed = current?.screenCaptureAllowed ?? false;
          return ListView(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 24 + MediaQuery.of(context).padding.bottom),
            children: [
              _section(context, 'حساب و اطلاعات کاربر', [
                _item(
                  Icons.person,
                  'پروفایل و اطلاعات وکیل',
                  'نام کاربری، عنوان وکیل، شماره پروانه و کانون / مرکز',
                  const ProfileScreen(),
                ),
              ]),
              _appearanceTile(context),
              Card(
                child: SwitchListTile(
                  secondary: Icon(screenCaptureAllowed ? Icons.screen_share_outlined : Icons.screenshot_monitor_outlined),
                  value: screenCaptureAllowed,
                  title: const Text('اجازه عکس و فیلم گرفتن از صفحه برنامه'),
                  subtitle: Text(
                    screenCaptureAllowed
                        ? 'اسکرین‌شات، ضبط صفحه و پیش‌نمایش برنامه‌های اخیر مجاز است.'
                        : 'برای حفاظت از اطلاعات پرونده‌ها، اسکرین‌شات و ضبط صفحه مسدود است.',
                  ),
                  onChanged: (value) async {
                    if (current == null) {
                      await db.into(db.securitySettings).insert(
                            SecuritySettingsCompanion.insert(
                              appLockEnabled: const Value(false),
                              biometricEnabled: const Value(false),
                              screenCaptureAllowed: Value(value),
                            ),
                          );
                    } else {
                      await db.update(db.securitySettings).replace(
                            current.copyWith(
                              screenCaptureAllowed: value,
                              updatedAt: DateTime.now(),
                            ),
                          );
                    }
                    await ScreenCaptureService.setAllowed(value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(value ? 'عکس و فیلم گرفتن از صفحه مجاز شد.' : 'عکس و فیلم گرفتن از صفحه مسدود شد.'),
                      ),
                    );
                  },
                ),
              ),
              _NotificationSettingsCard(db: db),
              _section(context, 'امنیت و نگهداری اطلاعات', [
                _item(
                  Icons.security,
                  'امنیت و حریم خصوصی برنامه',
                  'رمز، قفل، اثر انگشت و پاکسازی کامل اطلاعات',
                  const SecurityScreen(),
                ),
                _item(
                  Icons.backup,
                  'پشتیبان‌گیری و بازیابی',
                  'پشتیبان دستی و بازیابی فقط با تأیید شما',
                  const BackupScreen(),
                ),
              ]),
              _section(context, 'برنامه', [
                _item(Icons.health_and_safety, 'وضعیت سلامت برنامه', 'شمارش داده‌ها و عیب‌یابی سریع', const AppHealthScreen()),
                _item(Icons.info_outline, 'درباره کوروش‌یار', 'نسخه و وضعیت برنامه', const AppInfoScreen()),
              ]),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.phone_android),
                  title: Text('نسخه برنامه'),
                  subtitle: Text('کوروش‌یار v3.6.53'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _appearanceTile(BuildContext context) {
    return Card(
      child: AnimatedBuilder(
        animation: appThemeController,
        builder: (context, _) => ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('ظاهر و پس‌زمینه'),
          subtitle: Text(_themeModeLabel(appThemeController.mode)),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => _showAppearanceSheet(context),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<_SettingsItem> items) {
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
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.screen)),
              ),
            )
            .toList(),
      ),
    );
  }

  _SettingsItem _item(IconData icon, String title, String subtitle, Widget screen) => _SettingsItem(icon, title, subtitle, screen);

  String _themeModeLabel(String mode) {
    switch (mode) {
      case 'dark':
        return 'پس‌زمینه تیره';
      case 'system':
        return 'مطابق تنظیمات گوشی';
      case 'light':
      default:
        return 'پس‌زمینه روشن';
    }
  }

  Future<void> _showAppearanceSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        return SafeArea(
          child: AnimatedBuilder(
            animation: appThemeController,
            builder: (context, _) {
              final current = appThemeController.mode;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ظاهر و پس‌زمینه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('برای کاهش خستگی چشم می‌توانید پس‌زمینه روشن، تیره یا مطابق گوشی را انتخاب کنید.'),
                    const SizedBox(height: 12),
                    RadioListTile<String>(
                      value: 'light',
                      groupValue: current,
                      title: const Text('روشن'),
                      subtitle: const Text('پس‌زمینه روشن و رسمی'),
                      onChanged: (value) async {
                        await appThemeController.setMode(value ?? 'light');
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    RadioListTile<String>(
                      value: 'dark',
                      groupValue: current,
                      title: const Text('تیره'),
                      subtitle: const Text('ظاهر قبلی با پس‌زمینه تیره'),
                      onChanged: (value) async {
                        await appThemeController.setMode(value ?? 'dark');
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    RadioListTile<String>(
                      value: 'system',
                      groupValue: current,
                      title: const Text('مطابق گوشی'),
                      subtitle: const Text('بر اساس حالت روشن/تیره سیستم'),
                      onChanged: (value) async {
                        await appThemeController.setMode(value ?? 'system');
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SettingsItem {
  const _SettingsItem(this.icon, this.title, this.subtitle, this.screen);
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
}

class _NotificationSettingsCard extends StatefulWidget {
  const _NotificationSettingsCard({required this.db});

  final AppDatabase db;

  @override
  State<_NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<_NotificationSettingsCard> {
  late Future<NotificationHealth> _healthFuture = NotificationService.health();
  bool _working = false;

  void _refresh() {
    if (!mounted) return;
    setState(() => _healthFuture = NotificationService.health());
  }

  String _subtitle(NotificationHealth health) {
    if (!health.initialized) return 'راه‌اندازی اعلان با خطا روبه‌رو شد.';
    if (!health.notificationsAllowed) return 'مجوز اعلان در تنظیمات گوشی غیرفعال است.';
    final timing = health.exactAlarmAllowed ? 'زمان‌بندی دقیق' : 'زمان‌بندی عادی';
    final failure = health.lastSyncReport.failed > 0 ? '، ${toPersianDigits(health.lastSyncReport.failed)} خطا' : '';
    return 'فعال؛ ${toPersianDigits(health.pendingCount)} یادآوری زمان‌بندی‌شده، $timing$failure';
  }

  Future<void> _runAction(Future<String> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    String message;
    try {
      message = await action();
    } catch (error) {
      message = 'عملیات اعلان انجام نشد: $error';
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _healthFuture = NotificationService.health();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String> _enableAndTestNow() async {
    final permission = await NotificationService.health(requestPermissions: true);
    if (!permission.notificationsAllowed) {
      return 'مجوز اعلان فعال نشد. از گزینه «تنظیمات اعلان گوشی» استفاده کنید.';
    }
    await widget.db.syncNotifications();
    final shown = await NotificationService.showTestNotification();
    return shown
        ? 'اعلان فوری آزمایشی ارسال شد و یادآوری‌های آینده دوباره زمان‌بندی شدند.'
        : 'اعلان فوری ارسال نشد: ${NotificationService.lastError ?? 'علت نامشخص'}';
  }

  Future<String> _scheduleTest() async {
    final when = await NotificationService.scheduleTestNotification();
    if (when == null) {
      return 'اعلان آزمایشی زمان‌بندی نشد: ${NotificationService.lastError ?? 'مجوزهای گوشی را بررسی کنید.'}';
    }
    final hour = when.hour.toString().padLeft(2, '0');
    final minute = when.minute.toString().padLeft(2, '0');
    return 'یک اعلان آزمایشی برای ساعت ${toPersianDigits('$hour:$minute')} ثبت شد. برنامه را ببندید و نتیجه را بررسی کنید.';
  }

  Future<String> _resync() async {
    await widget.db.syncNotifications();
    final health = await NotificationService.health();
    final report = health.lastSyncReport;
    return 'زمان‌بندی مجدد انجام شد؛ ${toPersianDigits(report.scheduled)} ثبت، ${toPersianDigits(report.cancelled)} لغو و ${toPersianDigits(report.failed)} خطا.';
  }

  Future<void> _showTools() async {
    final health = await NotificationService.health();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(sheetContext).viewPadding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('اعلان‌ها و یادآوری‌های آفلاین', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_subtitle(health)),
              if (health.error != null && health.error!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(
                  'آخرین خطا: ${health.error}',
                  style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _working
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _runAction(_enableAndTestNow);
                      },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('فعال‌سازی و آزمایش فوری'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _runAction(_scheduleTest);
                      },
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('آزمایش زمان‌بندی یک دقیقه‌ای'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _runAction(_resync);
                      },
                icon: const Icon(Icons.sync),
                label: const Text('زمان‌بندی مجدد همه یادآوری‌ها'),
              ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('تنظیمات اعلان گوشی'),
                subtitle: const Text('فعال‌بودن اعلان، صدا و نمایش روی صفحه قفل'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  NotificationService.openSystemSettings(NotificationSettingsTarget.notifications);
                },
              ),
              ListTile(
                leading: const Icon(Icons.alarm_on_outlined),
                title: const Text('اجازه زمان‌بندی دقیق'),
                subtitle: const Text('برای اجرای یادآوری در ساعت دقیق در Android جدید'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  NotificationService.openSystemSettings(NotificationSettingsTarget.exactAlarms);
                },
              ),
              ListTile(
                leading: const Icon(Icons.battery_saver_outlined),
                title: const Text('محدودیت باتری و اجرای پس‌زمینه'),
                subtitle: const Text('در گوشی‌های سامسونگ و برخی سازندگان، کوروش‌یار را از محدودیت باتری خارج کنید.'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  NotificationService.openSystemSettings(NotificationSettingsTarget.battery);
                },
              ),
            ],
          ),
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: FutureBuilder<NotificationHealth>(
        future: _healthFuture,
        builder: (context, snapshot) {
          final health = snapshot.data;
          return ListTile(
            leading: Icon(
              health?.notificationsAllowed == true ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            ),
            title: const Text('اعلان‌ها و یادآوری‌های آفلاین'),
            subtitle: Text(
              snapshot.connectionState == ConnectionState.waiting
                  ? 'در حال بررسی وضعیت اعلان‌ها...'
                  : _subtitle(
                      health ??
                          const NotificationHealth(
                            initialized: false,
                            notificationsAllowed: false,
                            exactAlarmAllowed: false,
                            pendingCount: 0,
                          ),
                    ),
            ),
            trailing: _working
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_left),
            onTap: _working ? null : _showTools,
            onLongPress: _refresh,
          );
        },
      ),
    );
  }
}
