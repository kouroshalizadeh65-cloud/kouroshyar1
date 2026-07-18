import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../deadlines/personal_deadline_utils.dart';

/// Local-only reminders for tasks, deadlines and case sessions.
///
/// Notifications use stable ID ranges, so editing the source row updates the
/// existing reminder and deleting/completing it cancels the reminder.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const MethodChannel _systemChannel = MethodChannel('kouroshyar/notifications');
  static bool _initialized = false;
  static String? _lastError;
  static NotificationSyncReport _lastSyncReport = const NotificationSyncReport();
  static DateTime? _scheduledTestAt;

  static const int _taskBase = 100000;
  static const int _deadlineBase = 200000;
  static const int _sessionBase = 300000;
  static const int _testNotificationId = 99991;
  static const int _scheduledTestNotificationId = 99992;
  static const int _rangeSize = 100000;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'kouroshyar_reminders_v3',
    'یادآوری‌های کوروش‌یار',
    description: 'یادآوری آفلاین کارها، مهلت‌ها و جلسات',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'kouroshyar_reminders_v3',
      'یادآوری‌های کوروش‌یار',
      channelDescription: 'یادآوری آفلاین کارها، مهلت‌ها و جلسات',
      icon: 'ic_notification',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      ongoing: false,
    ),
  );

  static String? get lastError => _lastError;
  static NotificationSyncReport get lastSyncReport => _lastSyncReport;

  static void resetSyncReport() {
    _lastSyncReport = const NotificationSyncReport();
  }

  @visibleForTesting
  static int notificationIdFor(String tableName, int rowId) {
    final base = switch (tableName) {
      'tasks' => _taskBase,
      'deadlines' => _deadlineBase,
      'caseTimelineEvents' => _sessionBase,
      _ => throw ArgumentError.value(tableName, 'tableName', 'Unsupported notification table'),
    };
    return base + rowId.remainder(_rangeSize);
  }

  @visibleForTesting
  static bool isFutureReminder(DateTime when, {DateTime? now}) =>
      when.isAfter((now ?? DateTime.now()).add(const Duration(seconds: 5)));

  static Future<void> init() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        // Iran no longer observes DST. This fallback also avoids scheduling in
        // UTC when a vendor returns an unknown time-zone identifier.
        tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
      }

      const android = AndroidInitializationSettings('ic_notification');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings: settings);

      if (Platform.isAndroid) {
        await _androidImplementation()?.createNotificationChannel(_channel);
      }
      _lastError = null;
      _initialized = true;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Notification initialization failed: $error\n$stackTrace');
      rethrow;
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? _androidImplementation() =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<bool> requestPermission({bool requestExactAlarm = false}) async {
    await init();
    if (!Platform.isAndroid) return true;
    try {
      final android = _androidImplementation();
      final notificationsAllowed = await android?.requestNotificationsPermission() ?? true;
      if (!notificationsAllowed) {
        _lastError = 'مجوز اعلان در تنظیمات گوشی غیرفعال است.';
        return false;
      }
      if (requestExactAlarm) {
        final exactAllowed = await android?.canScheduleExactNotifications() ?? true;
        if (!exactAllowed) await android?.requestExactAlarmsPermission();
      }
      _lastError = null;
      return true;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Notification permission request failed: $error\n$stackTrace');
      return false;
    }
  }

  static Future<NotificationHealth> health({bool requestPermissions = false}) async {
    try {
      await init();
      var notificationsAllowed = true;
      var exactAlarmAllowed = true;
      if (Platform.isAndroid) {
        final android = _androidImplementation();
        if (requestPermissions) {
          notificationsAllowed = await requestPermission(requestExactAlarm: true);
        } else {
          notificationsAllowed = await android?.areNotificationsEnabled() ?? true;
        }
        exactAlarmAllowed = await android?.canScheduleExactNotifications() ?? true;
      }
      final pending = await _plugin.pendingNotificationRequests();
      return NotificationHealth(
        initialized: true,
        notificationsAllowed: notificationsAllowed,
        exactAlarmAllowed: exactAlarmAllowed,
        pendingCount: pending.length,
        error: _lastError,
        lastSyncReport: _lastSyncReport,
        scheduledTestAt: _scheduledTestAt,
      );
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Notification health check failed: $error\n$stackTrace');
      return NotificationHealth(
        initialized: false,
        notificationsAllowed: false,
        exactAlarmAllowed: false,
        pendingCount: 0,
        error: _lastError,
        lastSyncReport: _lastSyncReport,
        scheduledTestAt: _scheduledTestAt,
      );
    }
  }

  static Future<bool> showTestNotification() async {
    try {
      await init();
      final allowed = await requestPermission(requestExactAlarm: true);
      if (!allowed) return false;
      await _plugin.show(
        id: _testNotificationId,
        title: 'آزمایش فوری اعلان کوروش‌یار',
        body: 'اعلان فوری برنامه فعال است.',
        notificationDetails: _details,
      );
      _lastError = null;
      return true;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Test notification failed: $error\n$stackTrace');
      return false;
    }
  }

  static Future<DateTime?> scheduleTestNotification({Duration delay = const Duration(minutes: 1)}) async {
    try {
      await init();
      final allowed = await requestPermission(requestExactAlarm: true);
      if (!allowed) return null;
      final when = DateTime.now().add(delay);
      await _plugin.cancel(id: _scheduledTestNotificationId);
      await _schedule(
        id: _scheduledTestNotificationId,
        title: 'آزمایش زمان‌بندی اعلان کوروش‌یار',
        body: 'زمان‌بندی اعلان‌های آفلاین با موفقیت اجرا شد.',
        when: when,
        payload: 'diagnostic:scheduled-test',
      );
      _scheduledTestAt = when;
      _lastError = null;
      return when;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Scheduled test notification failed: $error\n$stackTrace');
      return null;
    }
  }

  static Future<void> showImmediate({required String title, required String body}) async {
    await init();
    final allowed = await requestPermission();
    if (!allowed) throw StateError('مجوز اعلان در تنظیمات گوشی غیرفعال است.');
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(90000),
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
    _scheduledTestAt = null;
  }

  static Future<void> openSystemSettings(NotificationSettingsTarget target) async {
    if (!Platform.isAndroid) return;
    try {
      await _systemChannel.invokeMethod<void>(
        switch (target) {
          NotificationSettingsTarget.notifications => 'openNotificationSettings',
          NotificationSettingsTarget.exactAlarms => 'openExactAlarmSettings',
          NotificationSettingsTarget.battery => 'openBatterySettings',
        },
      );
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('Opening notification settings failed: $error\n$stackTrace');
    }
  }

  static Future<NotificationSyncReport> syncTable(String tableName, List<Map<String, dynamic>> rows) async {
    if (tableName != 'tasks' && tableName != 'deadlines' && tableName != 'caseTimelineEvents') {
      return const NotificationSyncReport();
    }
    await init();

    final base = switch (tableName) {
      'tasks' => _taskBase,
      'deadlines' => _deadlineBase,
      _ => _sessionBase,
    };
    final desired = <int, _Reminder>{};
    for (final row in rows) {
      final reminder = _reminderFromRow(tableName, row);
      if (reminder != null) desired[reminder.id] = reminder;
    }

    var cancelled = 0;
    var scheduled = 0;
    var failed = 0;
    final errors = <String>[];
    final pending = await _plugin.pendingNotificationRequests();
    for (final item in pending) {
      if (item.id >= base && item.id < base + _rangeSize && !desired.containsKey(item.id)) {
        await _plugin.cancel(id: item.id);
        cancelled += 1;
      }
    }

    if (desired.isNotEmpty) {
      final allowed = await requestPermission();
      if (!allowed) {
        failed = desired.length;
        errors.add('مجوز اعلان غیرفعال است.');
      } else {
        for (final reminder in desired.values) {
          try {
            // Cancel first so an edited reminder can never leave two alarms on
            // vendor-customized Android builds.
            await _plugin.cancel(id: reminder.id);
            await _schedule(
              id: reminder.id,
              title: reminder.title,
              body: reminder.body,
              when: reminder.when,
              payload: reminder.payload,
            );
            scheduled += 1;
          } catch (error, stackTrace) {
            failed += 1;
            errors.add(error.toString());
            debugPrint('Notification scheduling failed: $error\n$stackTrace');
          }
        }
      }
    }

    final report = NotificationSyncReport(
      scheduled: scheduled,
      cancelled: cancelled,
      failed: failed,
      error: errors.isEmpty ? null : errors.first,
    );
    _lastSyncReport = _lastSyncReport + report;
    _lastError = failed == 0 ? null : report.error;
    return report;
  }

  static Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
  }) async {
    if (!isFutureReminder(when)) {
      throw StateError('زمان اعلان باید در آینده باشد.');
    }
    var scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (Platform.isAndroid) {
      final exactAllowed = await _androidImplementation()?.canScheduleExactNotifications() ?? false;
      if (exactAllowed) scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    }
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details,
        androidScheduleMode: scheduleMode,
        payload: payload,
      );
    } catch (_) {
      if (scheduleMode != AndroidScheduleMode.exactAllowWhileIdle) rethrow;
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  static _Reminder? _reminderFromRow(String tableName, Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt();
    if (id == null || id <= 0 || row['isDone'] == true) return null;

    if (tableName == 'caseTimelineEvents') {
      final eventType = (row['eventType'] ?? '').toString();
      final rowTitle = (row['title'] ?? '').toString();
      if (!eventType.contains('جلسه') && !rowTitle.contains('جلسه')) return null;
    }

    final dateKey = tableName == 'caseTimelineEvents' ? 'eventDate' : 'dueDate';
    final rawDate = row[dateKey]?.toString();
    if (rawDate == null || rawDate.trim().isEmpty) return null;
    var when = DateTime.tryParse(rawDate);
    if (when == null) return null;
    if (when.hour == 0 && when.minute == 0) {
      when = DateTime(when.year, when.month, when.day, 9);
    }

    var deadlineReminderMinutes = 0;
    if (tableName == 'deadlines') {
      deadlineReminderMinutes = (row['reminderMinutesBefore'] as num?)?.toInt() ?? 0;
      final reminderTime = personalDeadlineReminderTime(
        dueDate: when,
        reminderMinutesBefore: deadlineReminderMinutes,
      );
      if (reminderTime == null) return null;
      when = reminderTime;
    }
    if (!isFutureReminder(when)) return null;

    final titleText = (row['title'] ?? '').toString().trim();
    final isPersonalDeadline = tableName == 'deadlines' && row['caseId'] == null;
    final title = switch (tableName) {
      'tasks' => 'یادآوری کار شخصی',
      'deadlines' => isPersonalDeadline ? 'یادآوری مهلت شخصی' : 'یادآوری مهلت پرونده',
      _ => 'یادآوری جلسه پرونده',
    };
    final body = tableName == 'deadlines' && deadlineReminderMinutes > 0
        ? '${titleText.isEmpty ? 'مهلت ثبت‌شده' : titleText} — ${personalDeadlineReminderLabel(deadlineReminderMinutes)}'
        : (titleText.isEmpty ? title : titleText);
    return _Reminder(
      id: notificationIdFor(tableName, id),
      title: title,
      body: body,
      when: when,
      payload: '$tableName:$id',
    );
  }
}

enum NotificationSettingsTarget { notifications, exactAlarms, battery }

class NotificationHealth {
  const NotificationHealth({
    required this.initialized,
    required this.notificationsAllowed,
    required this.exactAlarmAllowed,
    required this.pendingCount,
    this.error,
    this.lastSyncReport = const NotificationSyncReport(),
    this.scheduledTestAt,
  });

  final bool initialized;
  final bool notificationsAllowed;
  final bool exactAlarmAllowed;
  final int pendingCount;
  final String? error;
  final NotificationSyncReport lastSyncReport;
  final DateTime? scheduledTestAt;
}

class NotificationSyncReport {
  const NotificationSyncReport({
    this.scheduled = 0,
    this.cancelled = 0,
    this.failed = 0,
    this.error,
  });

  final int scheduled;
  final int cancelled;
  final int failed;
  final String? error;

  NotificationSyncReport operator +(NotificationSyncReport other) => NotificationSyncReport(
        scheduled: scheduled + other.scheduled,
        cancelled: cancelled + other.cancelled,
        failed: failed + other.failed,
        error: other.error ?? error,
      );
}

class _Reminder {
  const _Reminder({required this.id, required this.title, required this.body, required this.when, required this.payload});

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String payload;
}
