import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_format_fa.dart';
import '../../core/utils/kourosh_datetime_parser.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/global_search_field.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../cases/case_detail_screen.dart';
import '../deadlines/personal_deadline_utils.dart';
import '../notifications/notification_service.dart';
import 'holiday_update_service.dart';

const List<String> _iranProvinces = <String>[
  'آذربایجان شرقی',
  'آذربایجان غربی',
  'اردبیل',
  'اصفهان',
  'البرز',
  'ایلام',
  'بوشهر',
  'تهران',
  'چهارمحال و بختیاری',
  'خراسان جنوبی',
  'خراسان رضوی',
  'خراسان شمالی',
  'خوزستان',
  'زنجان',
  'سمنان',
  'سیستان و بلوچستان',
  'فارس',
  'قزوین',
  'قم',
  'کردستان',
  'کرمان',
  'کرمانشاه',
  'کهگیلویه و بویراحمد',
  'گلستان',
  'گیلان',
  'لرستان',
  'مازندران',
  'مرکزی',
  'هرمزگان',
  'همدان',
  'یزد',
];

enum _CalendarViewMode { day, week, month, year }

enum _CalendarItemType { task, deadline, session }

class CalendarBackController {
  bool Function()? _handler;

  bool handleBack() => _handler?.call() ?? false;

  void _attach(bool Function() handler) {
    _handler = handler;
  }

  void _detach(bool Function() handler) {
    if (_handler == handler) _handler = null;
  }
}

class _CalendarHistoryEntry {
  const _CalendarHistoryEntry(this.mode, this.anchorDate);

  final _CalendarViewMode mode;
  final DateTime anchorDate;
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.backController});

  final CalendarBackController? backController;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  _CalendarViewMode _viewMode = _CalendarViewMode.month;
  DateTime _anchorDate = _dateOnlyStatic(DateTime.now());
  bool _defaultViewApplied = false;
  final List<_CalendarHistoryEntry> _history = <_CalendarHistoryEntry>[];

  static DateTime _dateOnlyStatic(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime _dateOnly(DateTime value) => _dateOnlyStatic(value);

  @override
  void initState() {
    super.initState();
    widget.backController?._attach(_handleCalendarBackFromShell);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoUpdateHolidays());
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backController != widget.backController) {
      oldWidget.backController?._detach(_handleCalendarBackFromShell);
      widget.backController?._attach(_handleCalendarBackFromShell);
    }
  }

  @override
  void dispose() {
    widget.backController?._detach(_handleCalendarBackFromShell);
    super.dispose();
  }

  bool _sameCalendarState(_CalendarHistoryEntry a, _CalendarHistoryEntry b) {
    return a.mode == b.mode && _dateOnly(a.anchorDate) == _dateOnly(b.anchorDate);
  }

  void _pushCalendarHistory() {
    final current = _CalendarHistoryEntry(_viewMode, _anchorDate);
    if (_history.isNotEmpty && _sameCalendarState(_history.last, current)) return;
    _history.add(current);
    if (_history.length > 50) _history.removeAt(0);
  }

  void _setCalendarState({required _CalendarViewMode mode, required DateTime anchorDate, bool remember = true}) {
    final current = _CalendarHistoryEntry(_viewMode, _anchorDate);
    final next = _CalendarHistoryEntry(mode, _dateOnly(anchorDate));
    if (_sameCalendarState(current, next)) return;
    if (remember) _pushCalendarHistory();
    setState(() {
      _viewMode = mode;
      _anchorDate = next.anchorDate;
    });
  }

  bool _restoreCalendarHistory() {
    if (_history.isEmpty) return false;
    final previous = _history.removeLast();
    setState(() {
      _viewMode = previous.mode;
      _anchorDate = _dateOnly(previous.anchorDate);
    });
    return true;
  }

  bool _handleCalendarBackFromShell() {
    return _restoreCalendarHistory();
  }

  bool _sameDay(DateTime a, DateTime b) => _dateOnly(a) == _dateOnly(b);

  DateTime _startOfWeek(DateTime value) {
    final date = _dateOnly(value);
    final daysFromSaturday = _persianWeekdayIndex(date);
    return date.subtract(Duration(days: daysFromSaturday));
  }

  DateTime _addJalaliMonths(DateTime value, int delta) {
    final j = gregorianToJalali(value);
    var year = j.year;
    var month = j.month + delta;
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    final day = math.min(j.day, _jalaliMonthLength(year, month));
    return jalaliToGregorian(year, month, day);
  }

  DateTime _addJalaliYears(DateTime value, int delta) {
    final j = gregorianToJalali(value);
    final year = j.year + delta;
    final day = math.min(j.day, _jalaliMonthLength(year, j.month));
    return jalaliToGregorian(year, j.month, day);
  }

  int _jalaliMonthLength(int year, int month) {
    final start = jalaliToGregorian(year, month, 1);
    final next = month == 12 ? jalaliToGregorian(year + 1, 1, 1) : jalaliToGregorian(year, month + 1, 1);
    return next.difference(start).inDays;
  }

  DateTime _effectiveDate(DateTime base, String title) {
    final parsedTime = parseKouroshTime(title);
    if (parsedTime == null) return _dateOnly(base);
    final parts = parsedTime.split(':');
    final hour = int.tryParse(parts.first) ?? base.hour;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? base.minute;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  bool _hasRealTime(DateTime value) => value.hour != 0 || value.minute != 0;

  String _timeText(DateTime value) {
    if (!_hasRealTime(value)) return 'تمام روز';
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return toPersianDigits('$hh:$mm');
  }

  String _rangeTitle() {
    switch (_viewMode) {
      case _CalendarViewMode.day:
        return formatPersianLongDate(_anchorDate);
      case _CalendarViewMode.week:
        final start = _startOfWeek(_anchorDate);
        final end = start.add(const Duration(days: 6));
        return '${formatSimpleDate(start)} تا ${formatSimpleDate(end)}';
      case _CalendarViewMode.month:
        final j = gregorianToJalali(_anchorDate);
        return '${_monthName(j.month)} ${toPersianDigits(j.year.toString())}';
      case _CalendarViewMode.year:
        final j = gregorianToJalali(_anchorDate);
        return 'سال ${toPersianDigits(j.year.toString())}';
    }
  }

  void _goToday() => _setCalendarState(mode: _viewMode, anchorDate: DateTime.now());

  void _goPrevious() {
    DateTime next;
    switch (_viewMode) {
      case _CalendarViewMode.day:
        next = _anchorDate.subtract(const Duration(days: 1));
        break;
      case _CalendarViewMode.week:
        next = _anchorDate.subtract(const Duration(days: 7));
        break;
      case _CalendarViewMode.month:
        next = _addJalaliMonths(_anchorDate, -1);
        break;
      case _CalendarViewMode.year:
        next = _addJalaliYears(_anchorDate, -1);
        break;
    }
    _setCalendarState(mode: _viewMode, anchorDate: next);
  }

  void _goNext() {
    DateTime next;
    switch (_viewMode) {
      case _CalendarViewMode.day:
        next = _anchorDate.add(const Duration(days: 1));
        break;
      case _CalendarViewMode.week:
        next = _anchorDate.add(const Duration(days: 7));
        break;
      case _CalendarViewMode.month:
        next = _addJalaliMonths(_anchorDate, 1);
        break;
      case _CalendarViewMode.year:
        next = _addJalaliYears(_anchorDate, 1);
        break;
    }
    _setCalendarState(mode: _viewMode, anchorDate: next);
  }

  _CalendarViewMode _modeFromSetting(String value) {
    switch (value) {
      case 'day':
        return _CalendarViewMode.day;
      case 'month':
        return _CalendarViewMode.month;
      case 'year':
        return _CalendarViewMode.year;
      case 'week':
        return _CalendarViewMode.week;
      default:
        return _CalendarViewMode.month;
    }
  }

  Future<CalendarSetting> _readCalendarSetting(AppDatabase db) async {
    final rows = await db.select(db.calendarSettings).get();
    if (rows.isEmpty) return CalendarSetting.defaults();
    return rows.first;
  }

  Future<CalendarSetting> _persistCalendarSetting(AppDatabase db, CalendarSetting setting) async {
    final existing = await db.select(db.calendarSettings).get();
    final updated = setting.copyWith(
      id: existing.isEmpty ? setting.id : existing.first.id,
      updatedAt: DateTime.now(),
    );
    if (existing.isEmpty) {
      final id = await db.into(db.calendarSettings).insert(
            CalendarSettingsCompanion.insert(
              weekendMode: Value(updated.weekendMode),
              showOfficialHolidays: Value(updated.showOfficialHolidays),
              defaultView: Value(updated.defaultView),
              onlineHolidayUpdatesEnabled: Value(updated.onlineHolidayUpdatesEnabled),
              holidayAutoUpdateEnabled: Value(updated.holidayAutoUpdateEnabled),
              holidayProvince: Value(updated.holidayProvince),
              holidayFeedData: Value<String?>(updated.holidayFeedData),
              holidayFeedRevision: Value(updated.holidayFeedRevision),
              workingHoursFeedData: Value<String?>(updated.workingHoursFeedData),
              workingHoursFeedRevision: Value(updated.workingHoursFeedRevision),
              holidayLastCheckedAt: Value<DateTime?>(updated.holidayLastCheckedAt),
              holidayLastSuccessAt: Value<DateTime?>(updated.holidayLastSuccessAt),
              holidayLastError: Value<String?>(updated.holidayLastError),
            ),
          );
      return updated.copyWith(id: id);
    }
    await db.update(db.calendarSettings).replace(updated);
    return updated;
  }

  CalendarSetting _calendarSettingsDraft(
    CalendarSetting base, {
    required String weekendMode,
    required bool showOfficialHolidays,
    required String defaultView,
    required bool onlineHolidayUpdatesEnabled,
    required bool holidayAutoUpdateEnabled,
    required String holidayProvince,
  }) {
    return base.copyWith(
      weekendMode: weekendMode,
      showOfficialHolidays: showOfficialHolidays,
      defaultView: defaultView,
      onlineHolidayUpdatesEnabled: onlineHolidayUpdatesEnabled,
      holidayAutoUpdateEnabled: holidayAutoUpdateEnabled,
      holidayProvince: holidayProvince,
      updatedAt: DateTime.now(),
    );
  }

  String _holidayUpdateTime(DateTime? value) {
    if (value == null) return 'ثبت نشده';
    final hh = toPersianDigits(value.hour.toString().padLeft(2, '0'));
    final mm = toPersianDigits(value.minute.toString().padLeft(2, '0'));
    return '${formatPersianLongDate(value)}، ساعت $hh:$mm';
  }

  Future<CalendarSetting> _checkHolidayUpdates(
    AppDatabase db,
    CalendarSetting setting, {
    required bool showFeedback,
  }) async {
    final holidayService = HolidayUpdateService();
    final workScheduleService = WorkScheduleUpdateService();
    final checkedAt = DateTime.now();
    var updated = setting;
    var addedHolidayCount = 0;
    var addedScheduleCount = 0;
    var holidaySucceeded = false;
    var scheduleSucceeded = false;
    final errors = <String>[];

    try {
      final previous = HolidayFeedSnapshot.tryDecodeStored(setting.holidayFeedData);
      final snapshot = await holidayService.fetchAndVerify(currentRevision: setting.holidayFeedRevision);
      final previousIds = previous?.activeIdsForProvince(setting.holidayProvince) ?? const <String>{};
      final nextIds = snapshot.activeIdsForProvince(setting.holidayProvince);
      addedHolidayCount = nextIds.difference(previousIds).length;
      updated = updated.copyWith(
        holidayFeedData: Value<String?>(snapshot.encodeForStorage()),
        holidayFeedRevision: snapshot.revision,
      );
      holidaySucceeded = true;
    } catch (error) {
      errors.add('تعطیلات: $error');
    }

    try {
      final previous = WorkScheduleFeedSnapshot.tryDecodeStored(setting.workingHoursFeedData);
      final snapshot = await workScheduleService.fetchAndVerify(
        currentRevision: setting.workingHoursFeedRevision,
      );
      final previousIds = previous?.activeIdsForProvince(setting.holidayProvince) ?? const <String>{};
      final nextIds = snapshot.activeIdsForProvince(setting.holidayProvince);
      addedScheduleCount = nextIds.difference(previousIds).length;
      updated = updated.copyWith(
        workingHoursFeedData: Value<String?>(snapshot.encodeForStorage()),
        workingHoursFeedRevision: snapshot.revision,
      );
      scheduleSucceeded = true;
    } catch (error) {
      errors.add('ساعات کاری: $error');
    }

    final anySuccess = holidaySucceeded || scheduleSucceeded;
    final saved = await _persistCalendarSetting(
      db,
      updated.copyWith(
        holidayLastCheckedAt: Value<DateTime?>(checkedAt),
        holidayLastSuccessAt: anySuccess
            ? Value<DateTime?>(checkedAt)
            : Value<DateTime?>(setting.holidayLastSuccessAt),
        holidayLastError: Value<String?>(errors.isEmpty ? null : errors.join('\n')),
        updatedAt: checkedAt,
      ),
    );

    final totalAdded = addedHolidayCount + addedScheduleCount;
    if (totalAdded > 0) {
      try {
        final parts = <String>[
          if (addedHolidayCount > 0) '${toPersianDigits(addedHolidayCount.toString())} تعطیلی',
          if (addedScheduleCount > 0) '${toPersianDigits(addedScheduleCount.toString())} تغییر ساعات کاری',
        ];
        await NotificationService.showImmediate(
          title: 'به‌روزرسانی جدید تقویم کوروش‌یار',
          body: '${parts.join(' و ')} برای ${setting.holidayProvince} دریافت شد.',
        );
      } catch (_) {
        // دریافت اطلاعات تقویم نباید به مجوز اعلان وابسته باشد.
      }
    }

    if (showFeedback && mounted) {
      String message;
      if (errors.isEmpty) {
        if (totalAdded > 0) {
          final parts = <String>[
            if (addedHolidayCount > 0) '${toPersianDigits(addedHolidayCount.toString())} تعطیلی جدید',
            if (addedScheduleCount > 0) '${toPersianDigits(addedScheduleCount.toString())} تغییر ساعات کاری جدید',
          ];
          message = '${parts.join(' و ')} دریافت و ذخیره شد.';
        } else {
          message = 'تعطیلات و تغییر ساعات کاری بررسی شد و اطلاعات ذخیره‌شده به‌روز است.';
        }
      } else if (anySuccess) {
        message = 'بخشی از اطلاعات دریافت شد؛ ${errors.join(' | ')}';
      } else {
        message = errors.join(' | ');
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    return saved;
  }

  Future<void> _maybeAutoUpdateHolidays() async {
    if (!mounted) return;
    try {
      final db = ref.read(databaseProvider);
      final setting = await _readCalendarSetting(db);
      final service = HolidayUpdateService();
      if (!setting.onlineHolidayUpdatesEnabled ||
          !setting.holidayAutoUpdateEnabled ||
          !service.isConfigured) {
        return;
      }
      final lastCheck = setting.holidayLastCheckedAt;
      if (lastCheck != null && DateTime.now().difference(lastCheck) < const Duration(hours: 24)) {
        return;
      }
      await _checkHolidayUpdates(db, setting, showFeedback: false);
    } catch (_) {
      // تقویم آفلاین حتی در خطای شبکه یا تنظیمات باید بدون وقفه کار کند.
    }
  }

  Future<void> _openCalendarSettings() async {
    final db = ref.read(databaseProvider);
    var working = await _readCalendarSetting(db);
    if (!mounted) return;

    var weekendMode = working.weekendMode;
    var showOfficialHolidays = working.showOfficialHolidays;
    var defaultView = working.defaultView;
    var onlineHolidayUpdatesEnabled = working.onlineHolidayUpdatesEnabled;
    var holidayAutoUpdateEnabled = working.holidayAutoUpdateEnabled;
    var holidayProvince = working.holidayProvince;
    var checkingUpdates = false;
    final updateService = HolidayUpdateService();
    final workScheduleService = WorkScheduleUpdateService();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottom = math.max(MediaQuery.of(context).viewInsets.bottom, MediaQuery.of(context).padding.bottom);
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('تنظیمات تقویم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text('تعطیلات آخر هفته'),
                    RadioListTile<String>(
                      value: 'friday',
                      groupValue: weekendMode,
                      title: const Text('فقط جمعه'),
                      onChanged: (value) => setSheetState(() => weekendMode = value ?? 'friday'),
                    ),
                    RadioListTile<String>(
                      value: 'thuFri',
                      groupValue: weekendMode,
                      title: const Text('پنجشنبه و جمعه'),
                      onChanged: (value) => setSheetState(() => weekendMode = value ?? 'thuFri'),
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: showOfficialHolidays,
                      title: const Text('نمایش تعطیلات رسمی ایران'),
                      subtitle: const Text('تعطیلات داخلی برنامه آفلاین باقی می‌مانند و بدون اینترنت نمایش داده می‌شوند.'),
                      onChanged: (value) => setSheetState(() => showOfficialHolidays = value),
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: onlineHolidayUpdatesEnabled,
                      title: const Text('به‌روزرسانی اینترنتی تعطیلات و ساعات کاری'),
                      subtitle: const Text('اختیاری؛ فقط فایل‌های امضاشده تعطیلات و تغییر ساعات کاری دریافت می‌شوند و هیچ پرونده، مدرک یا داده شخصی برنامه ارسال نمی‌شود.'),
                      onChanged: (value) => setSheetState(() => onlineHolidayUpdatesEnabled = value),
                    ),
                    if (onlineHolidayUpdatesEnabled) ...[
                      DropdownButtonFormField<String>(
                        value: _iranProvinces.contains(holidayProvince) ? holidayProvince : 'ایلام',
                        decoration: const InputDecoration(labelText: 'استان منتخب'),
                        items: _iranProvinces
                            .map((province) => DropdownMenuItem<String>(value: province, child: Text(province)))
                            .toList(growable: false),
                        onChanged: (value) => setSheetState(() => holidayProvince = value ?? 'ایلام'),
                      ),
                      SwitchListTile(
                        value: holidayAutoUpdateEnabled,
                        title: const Text('بررسی خودکار روزانه'),
                        subtitle: const Text('حداکثر یک‌بار در ۲۴ ساعت و فقط هنگام بازشدن تقویم.'),
                        onChanged: (value) => setSheetState(() => holidayAutoUpdateEnabled = value),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                updateService.isConfigured && workScheduleService.isConfigured
                                    ? 'منابع امضاشده تعطیلات و ساعات کاری تنظیم شده‌اند.'
                                    : 'منبع امضاشده هنوز کامل تنظیم نشده است.',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: updateService.isConfigured && workScheduleService.isConfigured
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('آخرین بررسی: ${_holidayUpdateTime(working.holidayLastCheckedAt)}'),
                              Text('آخرین دریافت موفق: ${_holidayUpdateTime(working.holidayLastSuccessAt)}'),
                              Text('بازبینی تعطیلات: ${toPersianDigits(working.holidayFeedRevision.toString())}'),
                              Text('بازبینی ساعات کاری: ${toPersianDigits(working.workingHoursFeedRevision.toString())}'),
                              if ((working.holidayLastError ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  working.holidayLastError!,
                                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: checkingUpdates
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_download_outlined),
                        label: const Text('بررسی به‌روزرسانی اکنون'),
                        onPressed: checkingUpdates || !updateService.isConfigured || !workScheduleService.isConfigured
                            ? null
                            : () async {
                                setSheetState(() => checkingUpdates = true);
                                try {
                                  final draft = _calendarSettingsDraft(
                                    working,
                                    weekendMode: weekendMode,
                                    showOfficialHolidays: showOfficialHolidays,
                                    defaultView: defaultView,
                                    onlineHolidayUpdatesEnabled: onlineHolidayUpdatesEnabled,
                                    holidayAutoUpdateEnabled: holidayAutoUpdateEnabled,
                                    holidayProvince: holidayProvince,
                                  );
                                  working = await _persistCalendarSetting(db, draft);
                                  working = await _checkHolidayUpdates(db, working, showFeedback: true);
                                } finally {
                                  if (context.mounted) setSheetState(() => checkingUpdates = false);
                                }
                              },
                      ),
                      const Text(
                        'تعطیلی یا تغییر ساعات کاری هیچ مهلتی را خودکار جابه‌جا نمی‌کند؛ فقط هشدار بررسی مرجع یا ساعت مراجعه نمایش داده می‌شود.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                    const Divider(),
                    const Text('نمای پیش‌فرض تقویم'),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(label: const Text('روزانه'), selected: defaultView == 'day', onSelected: (_) => setSheetState(() => defaultView = 'day')),
                        ChoiceChip(label: const Text('هفتگی'), selected: defaultView == 'week', onSelected: (_) => setSheetState(() => defaultView = 'week')),
                        ChoiceChip(label: const Text('ماهیانه'), selected: defaultView == 'month', onSelected: (_) => setSheetState(() => defaultView = 'month')),
                        ChoiceChip(label: const Text('سالیانه'), selected: defaultView == 'year', onSelected: (_) => setSheetState(() => defaultView = 'year')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('ذخیره تنظیمات تقویم'),
                      onPressed: checkingUpdates
                          ? null
                          : () async {
                              final draft = _calendarSettingsDraft(
                                working,
                                weekendMode: weekendMode,
                                showOfficialHolidays: showOfficialHolidays,
                                defaultView: defaultView,
                                onlineHolidayUpdatesEnabled: onlineHolidayUpdatesEnabled,
                                holidayAutoUpdateEnabled: holidayAutoUpdateEnabled,
                                holidayProvince: holidayProvince,
                              );
                              working = await _persistCalendarSetting(db, draft);
                              if (context.mounted) Navigator.pop(context);
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _viewMode = _modeFromSetting(defaultView);
      _defaultViewApplied = true;
    });
  }

  Future<_CalendarData> _load(AppDatabase db) async {
    final results = await Future.wait<Object>([
      db.select(db.cases).get(),
      db.select(db.tasks).get(),
      db.select(db.deadlines).get(),
      db.select(db.caseTimelineEvents).get(),
      _readCalendarSetting(db),
    ]);

    final cases = results[0] as List<Case>;
    final tasks = results[1] as List<Task>;
    final deadlines = results[2] as List<Deadline>;
    final timeline = results[3] as List<CaseTimelineEvent>;
    final settings = results[4] as CalendarSetting;
    final caseById = {for (final item in cases) item.id: item};
    final items = <_CalendarItem>[];

    for (final task in tasks.where((task) => task.dueDate != null)) {
      final date = _effectiveDate(task.dueDate!, task.title);
      final caseTitle = task.caseId == null ? null : caseById[task.caseId!]?.title;
      items.add(_CalendarItem(
        type: _CalendarItemType.task,
        title: task.title.trim().isEmpty ? 'کار بدون عنوان' : task.title.trim(),
        date: date,
        caseId: task.caseId,
        caseTitle: caseTitle,
        priority: task.priority,
        isDone: task.isDone,
        notes: null,
        holidayWarning: null,
      ));
    }

    for (final deadline in deadlines) {
      final caseTitle = deadline.caseId == null ? null : caseById[deadline.caseId!]?.title;
      items.add(_CalendarItem(
        type: _CalendarItemType.deadline,
        title: deadline.title.trim().isEmpty ? 'مهلت بدون عنوان' : deadline.title.trim(),
        date: deadline.dueDate,
        caseId: deadline.caseId,
        caseTitle: caseTitle,
        priority: deadline.priority,
        isDone: deadline.isDone,
        notes: deadline.notes,
        holidayWarning: deadline.caseId != null && !deadline.isDone && _isHoliday(deadline.dueDate, settings)
            ? 'هشدار: روز سررسید با تعطیلی تقویم مصادف است؛ وضعیت فعالیت مرجع قضایی بررسی شود. تاریخ مهلت خودکار تغییر نکرده است.'
            : null,
      ));
    }

    for (final event in timeline.where(_isSessionEvent)) {
      final date = _effectiveDate(event.eventDate, '${event.title} ${event.description ?? ''}');
      final caseTitle = caseById[event.caseId]?.title;
      items.add(_CalendarItem(
        type: _CalendarItemType.session,
        title: event.title.trim().isEmpty ? 'جلسه رسیدگی' : event.title.trim(),
        date: date,
        caseId: event.caseId,
        caseTitle: caseTitle,
        priority: 'زیاد',
        isDone: event.isDone,
        notes: event.description,
        holidayWarning: null,
      ));
    }

    items.sort(_compareCalendarItems);
    return _CalendarData(items: items, settings: settings);
  }

  bool _isSessionEvent(CaseTimelineEvent event) {
    final type = event.eventType?.trim() ?? '';
    return type.contains('جلسه') || event.title.contains('جلسه') || (event.description ?? '').contains('جلسه');
  }

  int _compareCalendarItems(_CalendarItem a, _CalendarItem b) {
    final dayCompare = _dateOnly(a.date).compareTo(_dateOnly(b.date));
    if (dayCompare != 0) return dayCompare;

    final aHasTime = _hasRealTime(a.date);
    final bHasTime = _hasRealTime(b.date);
    if (aHasTime != bHasTime) return aHasTime ? -1 : 1;

    final timeCompare = a.date.compareTo(b.date);
    if (timeCompare != 0) return timeCompare;

    final rankCompare = _typeRank(a.type).compareTo(_typeRank(b.type));
    if (rankCompare != 0) return rankCompare;

    return a.title.compareTo(b.title);
  }

  int _typeRank(_CalendarItemType type) {
    switch (type) {
      case _CalendarItemType.deadline:
        return 0;
      case _CalendarItemType.session:
        return 1;
      case _CalendarItemType.task:
        return 2;
    }
  }

  List<_CalendarItem> _itemsForDay(List<_CalendarItem> items, DateTime day) {
    return items.where((item) => _sameDay(item.date, day)).toList()..sort(_compareCalendarItems);
  }

  List<_CalendarItem> _itemsBetween(List<_CalendarItem> items, DateTime start, DateTime end) {
    final s = _dateOnly(start);
    final e = _dateOnly(end);
    return items.where((item) {
      final d = _dateOnly(item.date);
      return !d.isBefore(s) && !d.isAfter(e);
    }).toList()
      ..sort(_compareCalendarItems);
  }

  int _countType(List<_CalendarItem> items, _CalendarItemType type) => items.where((item) => item.type == type).length;

  Future<void> _openCase(int caseId) async {
    final db = ref.read(databaseProvider);
    final cases = await db.select(db.cases).get();
    Case? selected;
    for (final item in cases) {
      if (item.id == caseId) {
        selected = item;
        break;
      }
    }

    if (!mounted) return;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرونده مرتبط پیدا نشد.')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDetailScreen(item: selected!)));
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          children: [
            Text('تقویم'),
            SizedBox(width: 8),
            Expanded(child: GlobalSearchField()),
          ],
        ),
        actions: [
          const GlobalSettingsButton(),
          IconButton(
            tooltip: 'تنظیمات تقویم',
            onPressed: _openCalendarSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'امروز',
            onPressed: _goToday,
            icon: const Icon(Icons.today),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<int>(
          stream: db.watchAny(),
          builder: (context, _) {
            return FutureBuilder<_CalendarData>(
              future: _load(db),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _CalendarErrorBox(message: snapshot.error.toString());
                }

                final data = snapshot.data ?? _CalendarData(items: const <_CalendarItem>[], settings: CalendarSetting.defaults());
                if (!_defaultViewApplied) {
                  _defaultViewApplied = true;
                  final preferred = _modeFromSetting(data.settings.defaultView);
                  if (preferred != _viewMode) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _viewMode = preferred);
                    });
                  }
                }
                final visibleItems = _visibleItems(data.items);

                return Column(
                  children: [
                    _CalendarHeader(
                      viewMode: _viewMode,
                      title: _rangeTitle(),
                      visibleItems: visibleItems,
                      taskCount: _countType(visibleItems, _CalendarItemType.task),
                      deadlineCount: _countType(visibleItems, _CalendarItemType.deadline),
                      sessionCount: _countType(visibleItems, _CalendarItemType.session),
                      onModeChanged: (mode) => _setCalendarState(mode: mode, anchorDate: _anchorDate),
                      onPrevious: _goPrevious,
                      onNext: _goNext,
                    ),
                    Expanded(child: _buildCalendarBody(data.items, data.settings)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<_CalendarItem> _visibleItems(List<_CalendarItem> items) {
    switch (_viewMode) {
      case _CalendarViewMode.day:
        return _itemsForDay(items, _anchorDate);
      case _CalendarViewMode.week:
        final start = _startOfWeek(_anchorDate);
        return _itemsBetween(items, start, start.add(const Duration(days: 6)));
      case _CalendarViewMode.month:
        final j = gregorianToJalali(_anchorDate);
        final start = jalaliToGregorian(j.year, j.month, 1);
        final end = start.add(Duration(days: _jalaliMonthLength(j.year, j.month) - 1));
        return _itemsBetween(items, start, end);
      case _CalendarViewMode.year:
        final j = gregorianToJalali(_anchorDate);
        final start = jalaliToGregorian(j.year, 1, 1);
        final end = jalaliToGregorian(j.year + 1, 1, 1).subtract(const Duration(days: 1));
        return _itemsBetween(items, start, end);
    }
  }

  Widget _buildCalendarBody(List<_CalendarItem> items, CalendarSetting settings) {
    switch (_viewMode) {
      case _CalendarViewMode.day:
        return _DayCalendarView(
          day: _anchorDate,
          items: _itemsForDay(items, _anchorDate),
          settings: settings,
          timeText: _timeText,
          onOpenCase: _openCase,
        );
      case _CalendarViewMode.week:
        final start = _startOfWeek(_anchorDate);
        return _WeekCalendarView(
          start: start,
          selectedDay: _anchorDate,
          settings: settings,
          itemsForDay: (day) => _itemsForDay(items, day),
          timeText: _timeText,
          onSelectDay: (day) => _setCalendarState(mode: _viewMode, anchorDate: day),
          onOpenCase: _openCase,
        );
      case _CalendarViewMode.month:
        return _MonthCalendarView(
          anchorDate: _anchorDate,
          settings: settings,
          itemsForDay: (day) => _itemsForDay(items, day),
          onSelectDay: (day) => _setCalendarState(mode: _CalendarViewMode.day, anchorDate: day, remember: true),
        );
      case _CalendarViewMode.year:
        return _YearCalendarView(
          anchorDate: _anchorDate,
          settings: settings,
          items: items,
          itemsBetween: _itemsBetween,
          onSelectMonth: (monthStart) => _setCalendarState(mode: _CalendarViewMode.month, anchorDate: monthStart, remember: true),
        );
    }
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.viewMode,
    required this.title,
    required this.visibleItems,
    required this.taskCount,
    required this.deadlineCount,
    required this.sessionCount,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final _CalendarViewMode viewMode;
  final String title;
  final List<_CalendarItem> visibleItems;
  final int taskCount;
  final int deadlineCount;
  final int sessionCount;
  final ValueChanged<_CalendarViewMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  String _previousTooltip() {
    switch (viewMode) {
      case _CalendarViewMode.day:
        return 'روز قبل';
      case _CalendarViewMode.week:
        return 'هفته قبل';
      case _CalendarViewMode.month:
        return 'ماه قبل';
      case _CalendarViewMode.year:
        return 'سال قبل';
    }
  }

  String _nextTooltip() {
    switch (viewMode) {
      case _CalendarViewMode.day:
        return 'روز بعد';
      case _CalendarViewMode.week:
        return 'هفته بعد';
      case _CalendarViewMode.month:
        return 'ماه بعد';
      case _CalendarViewMode.year:
        return 'سال بعد';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ModeButton(
                      label: 'روزانه',
                      selected: viewMode == _CalendarViewMode.day,
                      onTap: () => onModeChanged(_CalendarViewMode.day),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ModeButton(
                      label: 'هفتگی',
                      selected: viewMode == _CalendarViewMode.week,
                      onTap: () => onModeChanged(_CalendarViewMode.week),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ModeButton(
                      label: 'ماهیانه',
                      selected: viewMode == _CalendarViewMode.month,
                      onTap: () => onModeChanged(_CalendarViewMode.month),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ModeButton(
                      label: 'سالیانه',
                      selected: viewMode == _CalendarViewMode.year,
                      onTap: () => onModeChanged(_CalendarViewMode.year),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: _previousTooltip(),
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          visibleItems.isEmpty ? 'موردی در این بازه نیست' : '${toPersianDigits(visibleItems.length.toString())} مورد ثبت‌شده',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: _nextTooltip(),
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _CountChip(icon: Icons.task_alt, label: 'کار', count: taskCount),
                  _CountChip(icon: Icons.warning_amber, label: 'مهلت', count: deadlineCount),
                  _CountChip(icon: Icons.groups, label: 'جلسه', count: sessionCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest.withOpacity(0.70),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _WeekCalendarView extends StatelessWidget {
  const _WeekCalendarView({
    required this.start,
    required this.selectedDay,
    required this.settings,
    required this.itemsForDay,
    required this.timeText,
    required this.onSelectDay,
    required this.onOpenCase,
  });

  final DateTime start;
  final DateTime selectedDay;
  final CalendarSetting settings;
  final List<_CalendarItem> Function(DateTime day) itemsForDay;
  final String Function(DateTime value) timeText;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<int> onOpenCase;

  @override
  Widget build(BuildContext context) {
    final days = List<DateTime>.generate(7, (index) => start.add(Duration(days: index)));
    final selectedItems = itemsForDay(selectedDay);
    final bottom = math.max(MediaQuery.of(context).padding.bottom, 16.0);

    return ListView(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottom + 72),
      children: [
        SizedBox(
          height: 154,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  _WeekDayCard(
                    day: days[i],
                    title: _weekDayName(days[i]),
                    items: itemsForDay(days[i]),
                    settings: settings,
                    isToday: _sameDate(days[i], DateTime.now()),
                    isSelected: _sameDate(days[i], selectedDay),
                    onTap: () => onSelectDay(days[i]),
                  ),
                  if (i != days.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _HolidayBanner(day: selectedDay, settings: settings),
        _PeriodicWorkScheduleText(day: selectedDay, settings: settings),
        _WorkScheduleBanner(day: selectedDay, settings: settings),
        _DayAgendaCard(
          title: 'برنامه ${formatPersianLongDate(selectedDay)}',
          emptyText: 'برای این روز کار، مهلت یا جلسه‌ای ثبت نشده است.',
          items: selectedItems,
          timeText: timeText,
          onOpenCase: onOpenCase,
        ),
      ],
    );
  }
}

class _MonthCalendarView extends StatelessWidget {
  const _MonthCalendarView({
    required this.anchorDate,
    required this.settings,
    required this.itemsForDay,
    required this.onSelectDay,
  });

  final DateTime anchorDate;
  final CalendarSetting settings;
  final List<_CalendarItem> Function(DateTime day) itemsForDay;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = math.max(media.padding.bottom, 16.0);
    final j = gregorianToJalali(anchorDate);
    final monthStart = jalaliToGregorian(j.year, j.month, 1);
    final monthLength = _jalaliMonthLengthStatic(j.year, j.month);
    final gridStart = monthStart.subtract(Duration(days: _persianWeekdayIndex(monthStart)));
    final cells = List<DateTime>.generate(42, (index) => gridStart.add(Duration(days: index)));
    const weekDayLabels = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];
    const weekDayFullNames = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];
    final availableWidth = math.max(240.0, media.size.width - 58);
    final cellWidth = availableWidth / 7;
    final cellHeight = math.max(56.0, cellWidth * 1.18);
    final gridAspectRatio = cellWidth / cellHeight;

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 72),
      children: [
        Card(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    children: List<Widget>.generate(weekDayLabels.length, (index) {
                      final fullName = weekDayFullNames[index];
                      final isWeekendHeader = fullName == 'جمعه' || (settings.weekendMode == 'thuFri' && fullName == 'پنجشنبه');
                      return Expanded(
                        child: Center(
                          child: Text(
                            weekDayLabels[index],
                            semanticsLabel: fullName,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isWeekendHeader ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 5),
                  GridView.builder(
                    itemCount: cells.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: gridAspectRatio,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                    ),
                    itemBuilder: (context, index) {
                      final day = cells[index];
                      final dayJ = gregorianToJalali(day);
                      return _MonthDayCell(
                        jalaliDay: dayJ.day,
                        inCurrentMonth: dayJ.month == j.month,
                        isToday: _sameDate(day, DateTime.now()),
                        isHoliday: _isHoliday(day, settings),
                        holidayTitle: _holidayTitle(day, settings),
                        hasWorkSchedule: _hasWorkSchedule(day, settings),
                        items: itemsForDay(day),
                        onTap: () => onSelectDay(day),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _MonthlyPeriodicWorkScheduleText(anchorDate: anchorDate, settings: settings),
        Text(
          'برای دیدن جزئیات یک روز، روی خانه همان روز بزنید. این ماه ${toPersianDigits(monthLength.toString())} روز دارد.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _DayCalendarView extends StatelessWidget {
  const _DayCalendarView({
    required this.day,
    required this.items,
    required this.settings,
    required this.timeText,
    required this.onOpenCase,
  });

  final DateTime day;
  final List<_CalendarItem> items;
  final CalendarSetting settings;
  final String Function(DateTime value) timeText;
  final ValueChanged<int> onOpenCase;

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(MediaQuery.of(context).padding.bottom, 16.0);

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 72),
      children: [
        _HolidayBanner(day: day, settings: settings),
        _PeriodicWorkScheduleText(day: day, settings: settings),
        _WorkScheduleBanner(day: day, settings: settings),
        _DayAgendaCard(
          title: formatPersianLongDate(day),
          emptyText: 'برای این روز برنامه‌ای ثبت نشده است.',
          items: items,
          timeText: timeText,
          onOpenCase: onOpenCase,
        ),
      ],
    );
  }
}

class _YearCalendarView extends StatelessWidget {
  const _YearCalendarView({
    required this.anchorDate,
    required this.settings,
    required this.items,
    required this.itemsBetween,
    required this.onSelectMonth,
  });

  final DateTime anchorDate;
  final CalendarSetting settings;
  final List<_CalendarItem> items;
  final List<_CalendarItem> Function(List<_CalendarItem> items, DateTime start, DateTime end) itemsBetween;
  final ValueChanged<DateTime> onSelectMonth;

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(MediaQuery.of(context).padding.bottom, 16.0);
    final j = gregorianToJalali(anchorDate);
    final months = List<int>.generate(12, (index) => index + 1);

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 72),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.15,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final month = months[index];
        final start = jalaliToGregorian(j.year, month, 1);
        final end = month == 12 ? jalaliToGregorian(j.year + 1, 1, 1).subtract(const Duration(days: 1)) : jalaliToGregorian(j.year, month + 1, 1).subtract(const Duration(days: 1));
        final monthItems = itemsBetween(items, start, end);
        final holidayCount = _holidayCountInRange(start, end, settings);
        final workScheduleCount = _workScheduleCountInRange(start, end, settings);
        return _YearMonthCard(
          year: j.year,
          month: month,
          items: monthItems,
          holidayCount: holidayCount,
          workScheduleCount: workScheduleCount,
          onTap: () => onSelectMonth(start),
        );
      },
    );
  }
}

class _WeekDayCard extends StatelessWidget {
  const _WeekDayCard({
    required this.day,
    required this.title,
    required this.items,
    required this.settings,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final String title;
  final List<_CalendarItem> items;
  final CalendarSetting settings;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final j = gregorianToJalali(day);
    final holiday = _isHoliday(day, settings);
    final hasWorkSchedule = _hasWorkSchedule(day, settings);
    final error = Theme.of(context).colorScheme.error;
    final workColor = Colors.orange.shade700;
    final titleColor = holiday ? error : null;
    return SizedBox(
      width: 94,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Card(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.55) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isToday
                  ? Theme.of(context).colorScheme.primary
                  : holiday
                      ? error.withOpacity(0.65)
                      : hasWorkSchedule
                          ? workColor.withOpacity(0.65)
                          : Colors.transparent,
              width: isToday || holiday || hasWorkSchedule ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: titleColor),
                ),
                const SizedBox(height: 4),
                Text(
                  toPersianDigits(j.day.toString()),
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: titleColor),
                ),
                Text('${_monthName(j.month)} ${toPersianDigits(j.year.toString())}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const Spacer(),
                if (holiday || hasWorkSchedule)
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (holiday)
                        Text('تعطیل', style: TextStyle(fontSize: 10, color: error, fontWeight: FontWeight.bold)),
                      if (hasWorkSchedule) Icon(Icons.access_time_filled, size: 14, color: workColor),
                    ],
                  )
                else if (items.isEmpty)
                  Text('خالی', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(.55)))
                else
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: [
                      if (items.any((item) => item.type == _CalendarItemType.deadline)) const _TinyDot(icon: Icons.warning_amber),
                      if (items.any((item) => item.type == _CalendarItemType.session)) const _TinyDot(icon: Icons.groups),
                      if (items.any((item) => item.type == _CalendarItemType.task)) const _TinyDot(icon: Icons.task_alt),
                    ],
                  ),
                const SizedBox(height: 2),
                Text('${toPersianDigits(items.length.toString())} مورد', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.jalaliDay,
    required this.inCurrentMonth,
    required this.isToday,
    required this.isHoliday,
    required this.holidayTitle,
    required this.hasWorkSchedule,
    required this.items,
    required this.onTap,
  });

  final int jalaliDay;
  final bool inCurrentMonth;
  final bool isToday;
  final bool isHoliday;
  final String? holidayTitle;
  final bool hasWorkSchedule;
  final List<_CalendarItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opacity = inCurrentMonth ? 1.0 : 0.62;
    final error = scheme.error;
    final workColor = Colors.orange.shade700;
    final borderColor = isToday
        ? scheme.primary
        : isHoliday
            ? error.withOpacity(0.7)
            : hasWorkSchedule
                ? workColor.withOpacity(0.65)
                : scheme.outlineVariant;
    final fill = isToday
        ? scheme.primaryContainer.withOpacity(0.55)
        : isHoliday
            ? scheme.errorContainer.withOpacity(0.36)
            : scheme.surfaceContainerHighest.withOpacity(inCurrentMonth ? 0.46 : 0.25);
    final dayTextColor = isHoliday
        ? error
        : inCurrentMonth
            ? scheme.onSurface
            : scheme.onSurfaceVariant;
    return Opacity(
      opacity: opacity,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
            color: fill,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    toPersianDigits(jalaliDay.toString()),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dayTextColor),
                  ),
                  const Spacer(),
                  if (hasWorkSchedule) Icon(Icons.access_time_filled, size: 13, color: workColor),
                  if (hasWorkSchedule && isHoliday) const SizedBox(width: 2),
                  if (isHoliday) Icon(Icons.circle, size: 7, color: error),
                ],
              ),
              const SizedBox(height: 2),
              if (holidayTitle != null)
                Text('تعطیل', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8, color: error, fontWeight: FontWeight.bold)),
              if (items.isEmpty)
                const Spacer()
              else ...[
                _MonthMiniLine(items: items, type: _CalendarItemType.deadline, label: 'مهلت'),
                _MonthMiniLine(items: items, type: _CalendarItemType.session, label: 'جلسه'),
                _MonthMiniLine(items: items, type: _CalendarItemType.task, label: 'کار'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _YearMonthCard extends StatelessWidget {
  const _YearMonthCard({
    required this.year,
    required this.month,
    required this.items,
    required this.holidayCount,
    required this.workScheduleCount,
    required this.onTap,
  });

  final int year;
  final int month;
  final List<_CalendarItem> items;
  final int holidayCount;
  final int workScheduleCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final taskCount = items.where((item) => item.type == _CalendarItemType.task).length;
    final deadlineCount = items.where((item) => item.type == _CalendarItemType.deadline).length;
    final sessionCount = items.where((item) => item.type == _CalendarItemType.session).length;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${_monthName(month)} ${toPersianDigits(year.toString())}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _YearLine(icon: Icons.warning_amber, label: 'مهلت', count: deadlineCount),
              _YearLine(icon: Icons.groups, label: 'جلسه', count: sessionCount),
              _YearLine(icon: Icons.task_alt, label: 'کار', count: taskCount),
              _YearLine(icon: Icons.event_busy, label: 'تعطیل', count: holidayCount),
              _YearLine(icon: Icons.access_time_filled, label: 'تغییر ساعت', count: workScheduleCount),
              const Spacer(),
              Text('ورود به ماه', textAlign: TextAlign.left, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _YearLine extends StatelessWidget {
  const _YearLine({required this.icon, required this.label, required this.count});

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text('$label: ${toPersianDigits(count.toString())}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _HolidayBanner extends StatelessWidget {
  const _HolidayBanner({required this.day, required this.settings});

  final DateTime day;
  final CalendarSetting settings;

  @override
  Widget build(BuildContext context) {
    final title = _holidayTitle(day, settings);
    if (title == null) return const SizedBox.shrink();
    final error = Theme.of(context).colorScheme.error;
    return Card(
      color: error.withOpacity(0.12),
      child: ListTile(
        leading: Icon(Icons.event_busy, color: error),
        title: Text('روز تعطیل', style: TextStyle(color: error, fontWeight: FontWeight.bold)),
        subtitle: Text(title),
        dense: true,
      ),
    );
  }
}


class _PeriodicWorkScheduleText extends StatelessWidget {
  const _PeriodicWorkScheduleText({required this.day, required this.settings});

  final DateTime day;
  final CalendarSetting settings;

  @override
  Widget build(BuildContext context) {
    final schedules = _periodicWorkSchedulesForDate(day, settings);
    if (schedules.isEmpty) return const SizedBox.shrink();
    return _PeriodicScheduleLines(schedules: schedules, settings: settings);
  }
}

class _MonthlyPeriodicWorkScheduleText extends StatelessWidget {
  const _MonthlyPeriodicWorkScheduleText({required this.anchorDate, required this.settings});

  final DateTime anchorDate;
  final CalendarSetting settings;

  @override
  Widget build(BuildContext context) {
    final schedules = _periodicWorkSchedulesForMonth(anchorDate, settings);
    if (schedules.isEmpty) return const SizedBox.shrink();
    return _PeriodicScheduleLines(schedules: schedules, settings: settings);
  }
}

class _PeriodicScheduleLines extends StatelessWidget {
  const _PeriodicScheduleLines({required this.schedules, required this.settings});

  final List<WorkScheduleUpdate> schedules;
  final CalendarSetting settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final schedule in schedules)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                _periodicScheduleDescription(schedule, settings.holidayProvince),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkScheduleBanner extends StatelessWidget {
  const _WorkScheduleBanner({required this.day, required this.settings});

  final DateTime day;
  final CalendarSetting settings;

  @override
  Widget build(BuildContext context) {
    final schedules = _exceptionWorkSchedulesForDate(day, settings);
    if (schedules.isEmpty) return const SizedBox.shrink();
    final periodicSchedules = _periodicWorkSchedulesForDate(day, settings);
    String? fallbackStartTime;
    for (final periodic in periodicSchedules) {
      if (periodic.startTime != null && periodic.startTime!.trim().isNotEmpty) {
        fallbackStartTime = periodic.startTime;
        break;
      }
    }
    final workColor = Colors.orange.shade800;
    return Column(
      children: [
        for (final schedule in schedules)
          Card(
            color: workColor.withOpacity(0.10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: workColor.withOpacity(0.45)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showWorkScheduleDetails(
                context,
                day: day,
                schedule: schedule,
                fallbackStartTime: fallbackStartTime,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        toPersianDigits(schedule.administrativeSummary(fallbackStartTime: fallbackStartTime)),
                        style: TextStyle(color: workColor, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_left_rounded, color: workColor),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _showWorkScheduleDetails(
  BuildContext context, {
  required DateTime day,
  required WorkScheduleUpdate schedule,
  String? fallbackStartTime,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final summary = toPersianDigits(schedule.administrativeSummary(fallbackStartTime: fallbackStartTime));
  final published = schedule.publishedAt.toLocal();
  final publishedText = toPersianDigits(
    '${published.year.toString().padLeft(4, '0')}/${published.month.toString().padLeft(2, '0')}/${published.day.toString().padLeft(2, '0')} '
    '${published.hour.toString().padLeft(2, '0')}:${published.minute.toString().padLeft(2, '0')}',
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            4,
            18,
            18 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(summary, style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              _WorkScheduleDetailLine(label: 'تاریخ اجرا', value: formatPersianLongDate(day)),
              _WorkScheduleDetailLine(label: 'عنوان اطلاعیه', value: schedule.title),
              _WorkScheduleDetailLine(label: 'نوع', value: schedule.typeLabel),
              _WorkScheduleDetailLine(label: 'ساعت', value: toPersianDigits(schedule.timeLabel)),
              _WorkScheduleDetailLine(label: 'محدوده اجرا', value: schedule.scopeLabel),
              if (schedule.includedOrganizations.isNotEmpty)
                _WorkScheduleDetailLine(label: 'مشمولان', value: schedule.includedOrganizations.join('، ')),
              if (schedule.excludedOrganizations.isNotEmpty)
                _WorkScheduleDetailLine(label: 'موارد مستثنا', value: schedule.excludedOrganizations.join('، ')),
              _WorkScheduleDetailLine(label: 'مرجع رسمی', value: schedule.authority),
              _WorkScheduleDetailLine(label: 'زمان انتشار', value: publishedText),
              if (schedule.note != null && schedule.note!.trim().isNotEmpty)
                _WorkScheduleDetailLine(label: 'توضیحات', value: schedule.note!.trim()),
              if (schedule.sourceUrl != null && schedule.sourceUrl!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('منبع رسمی', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                const SizedBox(height: 4),
                SelectableText(schedule.sourceUrl!.trim(), style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 14),
              Text(
                'این تغییر، روز را تعطیل نمی‌کند و هیچ کار، جلسه یا مهلتی را خودکار جابه‌جا نمی‌کند.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _WorkScheduleDetailLine extends StatelessWidget {
  const _WorkScheduleDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(height: 1.55),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _MonthMiniLine extends StatelessWidget {
  const _MonthMiniLine({required this.items, required this.type, required this.label});

  final List<_CalendarItem> items;
  final _CalendarItemType type;
  final String label;

  @override
  Widget build(BuildContext context) {
    final count = items.where((item) => item.type == type).length;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: _typeColor(context, type).withOpacity(0.16),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$label ${toPersianDigits(count.toString())}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 8, color: _typeColor(context, type), fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _DayAgendaCard extends StatelessWidget {
  const _DayAgendaCard({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.timeText,
    required this.onOpenCase,
  });

  final String title;
  final String emptyText;
  final List<_CalendarItem> items;
  final String Function(DateTime value) timeText;
  final ValueChanged<int> onOpenCase;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(emptyText, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else
              ...items.map((item) => _CalendarAgendaTile(item: item, timeText: timeText, onOpenCase: onOpenCase)),
          ],
        ),
      ),
    );
  }
}

class _CalendarAgendaTile extends StatelessWidget {
  const _CalendarAgendaTile({required this.item, required this.timeText, required this.onOpenCase});

  final _CalendarItem item;
  final String Function(DateTime value) timeText;
  final ValueChanged<int> onOpenCase;

  @override
  Widget build(BuildContext context) {
    final hasCase = item.caseId != null;
    final color = _typeColor(context, item.type);
    final isPersonalDeadline = item.type == _CalendarItemType.deadline && item.caseId == null;
    final status = isPersonalDeadline
        ? personalDeadlineStatusLabel(
            personalDeadlineStatus(dueDate: item.date, isDone: item.isDone),
          )
        : (item.isDone ? 'انجام‌شده' : _typeLabel(item.type));
    final subtitleParts = <String>[
      timeText(item.date),
      status,
      if (isPersonalDeadline)
        personalDeadlineRemainingLabel(dueDate: item.date, isDone: item.isDone)
      else if (item.priority.trim().isNotEmpty)
        'اولویت: ${item.priority}',
      if (item.caseTitle != null && item.caseTitle!.trim().isNotEmpty) 'پرونده: ${item.caseTitle}',
      if (item.notes != null && item.notes!.trim().isNotEmpty) item.notes!.trim(),
      if (item.holidayWarning != null && item.holidayWarning!.trim().isNotEmpty) item.holidayWarning!.trim(),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.42),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.22),
          child: Icon(_typeIcon(item.type), color: color),
        ),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(decoration: item.isDone ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text(subtitleParts.join(' | '), maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: hasCase ? const Icon(Icons.chevron_left) : null,
        onTap: hasCase ? () => onOpenCase(item.caseId!) : null,
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.label, required this.count});

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: ${toPersianDigits(count.toString())}'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TinyDot extends StatelessWidget {
  const _TinyDot({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant);
  }
}

class _CalendarErrorBox extends StatelessWidget {
  const _CalendarErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 8),
              const Text('در نمایش تقویم خطا رخ داد.', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarData {
  const _CalendarData({required this.items, required this.settings});

  final List<_CalendarItem> items;
  final CalendarSetting settings;
}

class _CalendarItem {
  const _CalendarItem({
    required this.type,
    required this.title,
    required this.date,
    required this.caseId,
    required this.caseTitle,
    required this.priority,
    required this.isDone,
    required this.notes,
    this.holidayWarning,
  });

  final _CalendarItemType type;
  final String title;
  final DateTime date;
  final int? caseId;
  final String? caseTitle;
  final String priority;
  final bool isDone;
  final String? notes;
  final String? holidayWarning;
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

int _persianWeekdayIndex(DateTime date) {
  return (date.weekday + 1) % 7;
}

int _jalaliMonthLengthStatic(int year, int month) {
  final start = jalaliToGregorian(year, month, 1);
  final next = month == 12 ? jalaliToGregorian(year + 1, 1, 1) : jalaliToGregorian(year, month + 1, 1);
  return next.difference(start).inDays;
}

String _weekDayName(DateTime date) {
  switch (date.weekday) {
    case DateTime.saturday:
      return 'شنبه';
    case DateTime.sunday:
      return 'یکشنبه';
    case DateTime.monday:
      return 'دوشنبه';
    case DateTime.tuesday:
      return 'سه‌شنبه';
    case DateTime.wednesday:
      return 'چهارشنبه';
    case DateTime.thursday:
      return 'پنجشنبه';
    case DateTime.friday:
      return 'جمعه';
  }
  return '';
}

IconData _typeIcon(_CalendarItemType type) {
  switch (type) {
    case _CalendarItemType.deadline:
      return Icons.warning_amber;
    case _CalendarItemType.session:
      return Icons.groups;
    case _CalendarItemType.task:
      return Icons.task_alt;
  }
}

String _typeLabel(_CalendarItemType type) {
  switch (type) {
    case _CalendarItemType.deadline:
      return 'مهلت';
    case _CalendarItemType.session:
      return 'جلسه';
    case _CalendarItemType.task:
      return 'کار';
  }
}

Color _typeColor(BuildContext context, _CalendarItemType type) {
  final scheme = Theme.of(context).colorScheme;
  switch (type) {
    case _CalendarItemType.deadline:
      return scheme.error;
    case _CalendarItemType.session:
      return scheme.primary;
    case _CalendarItemType.task:
      return scheme.tertiary;
  }
}

String _monthName(int month) {
  const names = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];
  return names[month - 1];
}

bool _isWeekend(DateTime date, CalendarSetting settings) {
  if (settings.weekendMode == 'thuFri') {
    return date.weekday == DateTime.thursday || date.weekday == DateTime.friday;
  }
  return date.weekday == DateTime.friday;
}

String? _holidayTitle(DateTime date, CalendarSetting settings) {
  final titles = <String>[];
  if (_isWeekend(date, settings)) titles.add('تعطیلی آخر هفته');
  if (settings.showOfficialHolidays) {
    final official = _officialHolidayTitle(date);
    if (official != null && !titles.contains(official)) titles.add(official);
  }
  if (settings.onlineHolidayUpdatesEnabled) {
    final online = _onlineHolidayTitle(date, settings);
    if (online != null && !titles.contains(online)) titles.add(online);
  }
  if (titles.isEmpty) return null;
  return titles.join(' | ');
}

bool _isHoliday(DateTime date, CalendarSetting settings) => _holidayTitle(date, settings) != null;

int _holidayCountInRange(DateTime start, DateTime end, CalendarSetting settings) {
  var count = 0;
  var day = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!day.isAfter(last)) {
    if (_isHoliday(day, settings)) count += 1;
    day = day.add(const Duration(days: 1));
  }
  return count;
}

String _holidayKey(int year, int month, int day) {
  final y = year.toString().padLeft(4, '0');
  final m = month.toString().padLeft(2, '0');
  final d = day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String? _cachedHolidayFeedSource;
HolidayFeedSnapshot? _cachedHolidayFeedSnapshot;

HolidayFeedSnapshot? _onlineHolidayFeed(CalendarSetting settings) {
  final source = settings.holidayFeedData;
  if (source == null || source.trim().isEmpty) return null;
  if (_cachedHolidayFeedSource != source) {
    _cachedHolidayFeedSource = source;
    _cachedHolidayFeedSnapshot = HolidayFeedSnapshot.tryDecodeStored(source);
  }
  return _cachedHolidayFeedSnapshot;
}

String? _onlineHolidayTitle(DateTime date, CalendarSetting settings) {
  final feed = _onlineHolidayFeed(settings);
  if (feed == null) return null;
  final j = gregorianToJalali(date);
  final key = _holidayKey(j.year, j.month, j.day);
  final matches = feed.holidays
      .where((item) => item.jalaliDate == key && item.appliesToProvince(settings.holidayProvince))
      .toList(growable: false)
    ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  if (matches.isEmpty) return null;
  return matches
      .map((item) => '${item.typeLabel}: ${item.title} — مرجع: ${item.authority}')
      .toSet()
      .join(' | ');
}


String? _cachedWorkScheduleFeedSource;
WorkScheduleFeedSnapshot? _cachedWorkScheduleFeedSnapshot;

WorkScheduleFeedSnapshot? _onlineWorkScheduleFeed(CalendarSetting settings) {
  final source = settings.workingHoursFeedData;
  if (source == null || source.trim().isEmpty) return null;
  if (_cachedWorkScheduleFeedSource != source) {
    _cachedWorkScheduleFeedSource = source;
    _cachedWorkScheduleFeedSnapshot = WorkScheduleFeedSnapshot.tryDecodeStored(source);
  }
  return _cachedWorkScheduleFeedSnapshot;
}

List<WorkScheduleUpdate> _workSchedulesForDate(DateTime date, CalendarSetting settings) {
  if (!settings.onlineHolidayUpdatesEnabled) return const <WorkScheduleUpdate>[];
  final feed = _onlineWorkScheduleFeed(settings);
  if (feed == null) return const <WorkScheduleUpdate>[];
  final j = gregorianToJalali(date);
  final key = _holidayKey(j.year, j.month, j.day);
  return feed.schedulesForProvinceAndDate(settings.holidayProvince, key);
}

List<WorkScheduleUpdate> _periodicWorkSchedulesForDate(DateTime date, CalendarSetting settings) =>
    _workSchedulesForDate(date, settings).where((item) => item.isPeriodicSchedule).toList(growable: false);

List<WorkScheduleUpdate> _exceptionWorkSchedulesForDate(DateTime date, CalendarSetting settings) =>
    _workSchedulesForDate(date, settings).where((item) => !item.isPeriodicSchedule).toList(growable: false);

List<WorkScheduleUpdate> _periodicWorkSchedulesForMonth(DateTime anchorDate, CalendarSetting settings) {
  if (!settings.onlineHolidayUpdatesEnabled) return const <WorkScheduleUpdate>[];
  final feed = _onlineWorkScheduleFeed(settings);
  if (feed == null) return const <WorkScheduleUpdate>[];
  final j = gregorianToJalali(anchorDate);
  final first = _holidayKey(j.year, j.month, 1);
  final last = _holidayKey(j.year, j.month, _jalaliMonthLengthStatic(j.year, j.month));
  final matches = feed.schedules.where((item) {
    if (!item.isPeriodicSchedule || !item.appliesToProvince(settings.holidayProvince)) return false;
    final end = item.endJalaliDate ?? item.jalaliDate;
    return item.jalaliDate.compareTo(last) <= 0 && end.compareTo(first) >= 0;
  }).toList(growable: false)
    ..sort((a, b) => a.jalaliDate.compareTo(b.jalaliDate));
  return matches;
}

bool _hasWorkSchedule(DateTime date, CalendarSetting settings) =>
    _exceptionWorkSchedulesForDate(date, settings).isNotEmpty;

String _periodicScheduleDescription(WorkScheduleUpdate schedule, String selectedProvince) {
  final start = _formatJalaliKeyLong(schedule.jalaliDate);
  final end = schedule.endJalaliDate == null ? null : _formatJalaliKeyLong(schedule.endJalaliDate!);
  final range = end == null || end == start ? 'در $start' : 'از $start تا $end';
  final startTime = schedule.startTime == null ? null : toPersianDigits(schedule.startTime!);
  final endTime = schedule.endTime == null ? null : toPersianDigits(schedule.endTime!);
  final time = startTime != null && endTime != null
      ? '، از ساعت $startTime تا $endTime'
      : startTime != null
          ? '، از ساعت $startTime'
          : endTime != null
              ? '، تا ساعت $endTime'
              : '';
  return 'ساعت کاری ادارات استان $selectedProvince $range$time است.';
}

String _formatJalaliKeyLong(String key) {
  final parts = key.split('-').map(int.parse).toList(growable: false);
  return '${toPersianDigits(parts[2].toString())} ${_monthName(parts[1])} ${toPersianDigits(parts[0].toString())}';
}

int _workScheduleCountInRange(DateTime start, DateTime end, CalendarSetting settings) {
  var count = 0;
  var day = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!day.isAfter(last)) {
    if (_hasWorkSchedule(day, settings)) count += 1;
    day = day.add(const Duration(days: 1));
  }
  return count;
}

String? _officialHolidayTitle(DateTime date) {
  final j = gregorianToJalali(date);
  final exact = _iranOfficialHolidays[_holidayKey(j.year, j.month, j.day)];
  if (exact != null) return exact;
  return _fixedIranSolarHolidays[_holidayKey(0, j.month, j.day).substring(5)];
}

// دیتاست داخلی آفلاین تعطیلات رسمی ۱۴۰۵ بر اساس تقویم رسمی کشور
// منتشرشده توسط مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران.
const Map<String, String> _iranOfficialHolidays = {
  '1405-01-01': 'عید سعید فطر و آغاز نوروز',
  '1405-01-02': 'تعطیل به مناسبت عید سعید فطر و عید نوروز',
  '1405-01-03': 'عید نوروز',
  '1405-01-04': 'عید نوروز',
  '1405-01-12': 'روز جمهوری اسلامی ایران',
  '1405-01-13': 'روز طبیعت',
  '1405-01-25': 'شهادت امام جعفر صادق (ع)',
  '1405-03-06': 'عید سعید قربان',
  '1405-03-14': 'عید غدیر خم و رحلت امام خمینی',
  '1405-03-15': 'قیام ۱۵ خرداد',
  '1405-04-03': 'تاسوعای حسینی',
  '1405-04-04': 'عاشورای حسینی',
  '1405-04-14': 'تعطیلی رسمی سراسری برای مراسم وداع و تشییع رهبر فقید انقلاب',
  '1405-04-15': 'تعطیلی رسمی سراسری برای مراسم تشییع رهبر فقید انقلاب',
  '1405-05-13': 'اربعین حسینی',
  '1405-05-21': 'رحلت پیامبر اکرم (ص) و شهادت امام حسن مجتبی (ع)',
  '1405-05-22': 'شهادت امام رضا (ع)',
  '1405-05-30': 'شهادت امام حسن عسکری (ع)',
  '1405-06-08': 'ولادت پیامبر اکرم (ص) و امام جعفر صادق (ع)',
  '1405-08-22': 'شهادت حضرت فاطمه زهرا (س)',
  '1405-10-02': 'ولادت امام علی (ع)',
  '1405-10-16': 'مبعث پیامبر اکرم (ص)',
  '1405-11-04': 'ولادت حضرت قائم (عج)',
  '1405-11-22': 'پیروزی انقلاب اسلامی ایران',
  '1405-12-09': 'شهادت امام علی (ع)',
  '1405-12-19': 'عید سعید فطر',
  '1405-12-20': 'تعطیل به مناسبت عید سعید فطر',
  '1405-12-29': 'روز ملی شدن صنعت نفت ایران',
};

const Map<String, String> _fixedIranSolarHolidays = {
  '01-01': 'آغاز نوروز',
  '01-02': 'عید نوروز',
  '01-03': 'عید نوروز',
  '01-04': 'عید نوروز',
  '01-12': 'روز جمهوری اسلامی ایران',
  '01-13': 'روز طبیعت',
  '03-14': 'رحلت امام خمینی',
  '03-15': 'قیام ۱۵ خرداد',
  '11-22': 'پیروزی انقلاب اسلامی ایران',
  '12-29': 'روز ملی شدن صنعت نفت ایران',
};
