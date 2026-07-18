import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/database/app_database.dart';

void main() {
  test('legacy calendar settings keep online updates disabled', () {
    final setting = CalendarSetting.fromJson(<String, dynamic>{
      'id': 1,
      'weekendMode': 'friday',
      'showOfficialHolidays': true,
      'defaultView': 'month',
      'updatedAt': DateTime.now().toIso8601String(),
    });

    expect(setting.onlineHolidayUpdatesEnabled, isFalse);
    expect(setting.holidayAutoUpdateEnabled, isTrue);
    expect(setting.holidayProvince, 'ایلام');
    expect(setting.holidayFeedRevision, 0);
    expect(setting.workingHoursFeedRevision, 0);
    expect(setting.workingHoursFeedData, isNull);
  });

  test('calendar settings preserve signed holiday and working-hours feeds', () {
    final setting = CalendarSetting.defaults().copyWith(
      onlineHolidayUpdatesEnabled: true,
      holidayFeedData: const Value<String?>('{"format":"kouroshyar-holiday-feed-v1"}'),
      holidayFeedRevision: 7,
      workingHoursFeedData: const Value<String?>('{"format":"kouroshyar-work-schedule-feed-v1"}'),
      workingHoursFeedRevision: 4,
      holidayLastError: const Value<String?>(null),
    );
    final restored = CalendarSetting.fromJson(setting.toJson());

    expect(restored.onlineHolidayUpdatesEnabled, isTrue);
    expect(restored.holidayFeedRevision, 7);
    expect(restored.holidayFeedData, contains('kouroshyar-holiday-feed-v1'));
    expect(restored.workingHoursFeedRevision, 4);
    expect(restored.workingHoursFeedData, contains('kouroshyar-work-schedule-feed-v1'));
  });
}
