import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/database/app_database.dart';
import 'package:kouroshyar/features/deadlines/personal_deadline_utils.dart';

void main() {
  test('مهلت شخصی قدیمی بدون حذف داده با یادآوری هم‌زمان مهاجرت می‌کند', () {
    final deadline = Deadline.fromJson({
      'id': 12,
      'caseId': null,
      'title': 'مهلت شخصی قدیمی',
      'dueDate': '2026-07-20T09:30:00.000',
      'priority': 'زیاد',
      'isDone': false,
      'createdAt': '2026-07-16T10:00:00.000',
    });

    expect(deadline.caseId, isNull);
    expect(deadline.reminderMinutesBefore, 0);
    expect(deadline.toJson()['reminderMinutesBefore'], 0);
  });

  test('وضعیت مهلت مستقل از اولویت کار محاسبه می‌شود', () {
    final now = DateTime(2026, 7, 16, 12);

    expect(
      personalDeadlineStatus(
        dueDate: DateTime(2026, 7, 17, 10),
        isDone: false,
        now: now,
      ),
      PersonalDeadlineStatus.active,
    );
    expect(
      personalDeadlineStatus(
        dueDate: DateTime(2026, 7, 16, 18),
        isDone: false,
        now: now,
      ),
      PersonalDeadlineStatus.dueToday,
    );
    expect(
      personalDeadlineStatus(
        dueDate: DateTime(2026, 7, 15, 18),
        isDone: false,
        now: now,
      ),
      PersonalDeadlineStatus.expired,
    );
    expect(
      personalDeadlineStatus(
        dueDate: DateTime(2026, 7, 16, 11),
        isDone: false,
        now: now,
      ),
      PersonalDeadlineStatus.expired,
    );
    expect(
      personalDeadlineStatus(
        dueDate: DateTime(2026, 7, 15, 18),
        isDone: true,
        now: now,
      ),
      PersonalDeadlineStatus.done,
    );
  });

  test('زمان اعلان مهلت از سررسید کم می‌شود و امکان غیرفعال‌سازی دارد', () {
    final due = DateTime(2026, 7, 20, 9, 30);

    expect(
      personalDeadlineReminderTime(dueDate: due, reminderMinutesBefore: 1440),
      DateTime(2026, 7, 19, 9, 30),
    );
    expect(
      personalDeadlineReminderTime(dueDate: due, reminderMinutesBefore: -1),
      isNull,
    );
    expect(personalDeadlineReminderLabel(4320), '۳ روز پیش از سررسید');
  });
}
