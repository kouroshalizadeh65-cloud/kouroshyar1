import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/core/utils/date_format_fa.dart';

void main() {
  test('1405 starts on Saturday and round-trips correctly', () {
    final firstFarvardin = jalaliToGregorian(1405, 1, 1);

    expect(firstFarvardin.year, 2026);
    expect(firstFarvardin.month, 3);
    expect(firstFarvardin.day, 21);
    expect(firstFarvardin.weekday, DateTime.saturday);

    final back = gregorianToJalali(firstFarvardin);
    expect(back.year, 1405);
    expect(back.month, 1);
    expect(back.day, 1);
  });

  test('1405 official calendar month boundaries stay stable', () {
    expect(jalaliToGregorian(1405, 1, 31), DateTime(2026, 4, 20));
    expect(jalaliToGregorian(1405, 7, 30), DateTime(2026, 10, 22));
    expect(jalaliToGregorian(1405, 12, 29), DateTime(2027, 3, 20));
  });
}
