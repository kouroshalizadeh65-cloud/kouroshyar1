import '../../core/utils/persian_numbers.dart';

enum PersonalDeadlineStatus { active, dueToday, expired, done }

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

PersonalDeadlineStatus personalDeadlineStatus({
  required DateTime dueDate,
  required bool isDone,
  DateTime? now,
}) {
  if (isDone) return PersonalDeadlineStatus.done;
  final current = now ?? DateTime.now();
  final effectiveDue = dueDate.hour == 0 && dueDate.minute == 0
      ? DateTime(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59)
      : dueDate;
  if (effectiveDue.isBefore(current)) return PersonalDeadlineStatus.expired;
  if (_dateOnly(effectiveDue) == _dateOnly(current)) return PersonalDeadlineStatus.dueToday;
  return PersonalDeadlineStatus.active;
}

String personalDeadlineStatusLabel(PersonalDeadlineStatus status) {
  switch (status) {
    case PersonalDeadlineStatus.active:
      return 'فعال';
    case PersonalDeadlineStatus.dueToday:
      return 'سررسید امروز';
    case PersonalDeadlineStatus.expired:
      return 'منقضی‌شده';
    case PersonalDeadlineStatus.done:
      return 'انجام‌شده';
  }
}

String personalDeadlineRemainingLabel({
  required DateTime dueDate,
  required bool isDone,
  DateTime? now,
}) {
  final status = personalDeadlineStatus(dueDate: dueDate, isDone: isDone, now: now);
  if (status == PersonalDeadlineStatus.done) return 'مهلت انجام شده است';
  if (status == PersonalDeadlineStatus.dueToday) return 'امروز آخرین فرصت است';

  final days = _dateOnly(dueDate).difference(_dateOnly(now ?? DateTime.now())).inDays;
  if (status == PersonalDeadlineStatus.expired) {
    if (days == 0) return 'زمان سررسید گذشته است';
    return '${toPersianDigits(days.abs())} روز از سررسید گذشته است';
  }
  return '${toPersianDigits(days)} روز تا سررسید باقی مانده است';
}

DateTime? personalDeadlineReminderTime({
  required DateTime dueDate,
  required int reminderMinutesBefore,
}) {
  if (reminderMinutesBefore < 0) return null;
  return dueDate.subtract(Duration(minutes: reminderMinutesBefore));
}

String personalDeadlineReminderLabel(int minutesBefore) {
  switch (minutesBefore) {
    case -1:
      return 'بدون اعلان';
    case 0:
      return 'هم‌زمان با سررسید';
    case 60:
      return '۱ ساعت پیش از سررسید';
    case 1440:
      return '۱ روز پیش از سررسید';
    case 4320:
      return '۳ روز پیش از سررسید';
    case 10080:
      return '۱ هفته پیش از سررسید';
    default:
      if (minutesBefore > 0 && minutesBefore % 1440 == 0) {
        return '${toPersianDigits(minutesBefore ~/ 1440)} روز پیش از سررسید';
      }
      if (minutesBefore > 0 && minutesBefore % 60 == 0) {
        return '${toPersianDigits(minutesBefore ~/ 60)} ساعت پیش از سررسید';
      }
      return minutesBefore < 0 ? 'بدون اعلان' : 'پیش از سررسید';
  }
}

const List<int> personalDeadlineReminderOptions = <int>[-1, 0, 60, 1440, 4320, 10080];
