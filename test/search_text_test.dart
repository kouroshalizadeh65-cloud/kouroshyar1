import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/core/utils/search_text.dart';

void main() {
  test('جستجو از اولین حرف و با یکسان‌سازی نویسه‌های فارسی انجام می‌شود', () {
    expect(searchTextContains('پرونده کیفری', 'پ'), isTrue);
    expect(searchTextContains('علي رضايي', 'علی رضایی'), isTrue);
    expect(searchTextContains('وکالت‌نامه', 'وکالت نامه'), isTrue);
    expect(searchTextContains('هزینه و درآمدها', 'درآمد'), isTrue);
  });

  test('جستجو نسبت به اعراب و فاصله‌های اضافی مقاوم است', () {
    expect(searchTextContains('مُهلت قانونی', 'مهلت'), isTrue);
    expect(searchTextContains('رای   نهایی', 'رای نهایی'), isTrue);
  });
}
