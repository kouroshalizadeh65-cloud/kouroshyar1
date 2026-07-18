import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/features/notifications/notification_service.dart';

void main() {
  test('شناسه اعلان برای هر منبع پایدار و در بازه جداگانه است', () {
    expect(NotificationService.notificationIdFor('tasks', 12), 100012);
    expect(NotificationService.notificationIdFor('deadlines', 12), 200012);
    expect(NotificationService.notificationIdFor('caseTimelineEvents', 12), 300012);
  });

  test('فقط زمان آینده برای اعلان پذیرفته می‌شود', () {
    final now = DateTime(2026, 7, 16, 12);
    expect(NotificationService.isFutureReminder(now.add(const Duration(seconds: 6)), now: now), isTrue);
    expect(NotificationService.isFutureReminder(now.add(const Duration(seconds: 4)), now: now), isFalse);
    expect(NotificationService.isFutureReminder(now.subtract(const Duration(minutes: 1)), now: now), isFalse);
  });
}
