import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/database/app_database.dart';

void main() {
  test('مهلت شخصی با caseId خالی ذخیره و بازیابی می‌شود', () {
    final deadline = Deadline.fromJson({
      'id': 12,
      'caseId': null,
      'title': 'مهلت شخصی آزمایشی',
      'dueDate': '2026-07-20T09:30:00.000',
      'priority': 'زیاد',
      'reminderMinutesBefore': 60,
      'isDone': false,
      'createdAt': '2026-07-16T10:00:00.000',
    });

    expect(deadline.caseId, isNull);
    expect(deadline.dueDate.hour, 9);
    expect(deadline.dueDate.minute, 30);
    expect(deadline.reminderMinutesBefore, 60);
    expect(deadline.toJson()['reminderMinutesBefore'], 60);
    expect(deadline.toJson()['caseId'], isNull);
  });

  test('تنظیم اجازه ثبت تصویر با پیش‌فرض امن سازگار است', () {
    final legacy = SecuritySetting.fromJson({
      'id': 1,
      'appLockEnabled': true,
      'biometricEnabled': false,
      'updatedAt': '2026-07-16T10:00:00.000',
    });
    final allowed = SecuritySetting.fromJson({
      'id': 1,
      'appLockEnabled': true,
      'biometricEnabled': false,
      'screenCaptureAllowed': true,
      'updatedAt': '2026-07-16T10:00:00.000',
    });

    expect(legacy.screenCaptureAllowed, isFalse);
    expect(allowed.screenCaptureAllowed, isTrue);
    expect(allowed.toJson()['screenCaptureAllowed'], isTrue);
  });
}
