# تغییرات کوروش‌یار v3.6.17

نام نسخه: `finance_analyze_hotfix`

نسخه برنامه: `3.6.17+89`

نام APK هدف:

`kouroshyar_v3_6_17_finance_analyze_hotfix_1405_04_15.apk`

## محور نسخه

هات‌فیکس خطای Analyze مربوط به تغییرات مالی پرونده در v3.6.16.

## اصلاحات

- اضافه شدن import صحیح ابزارهای مالی از `lib/core/utils/money_format.dart` در `cases_screen.dart`.
- رفع خطای `parseMoney isn't defined` در ثبت پرونده.
- رفع خطای `MoneyInputFormatter isn't defined` در فیلد مبلغ کل حق‌الوکاله.
- اصلاح لیست `inputFormatters` برای جلوگیری از خطای `non_constant_list_element`.
- حفظ همه تغییرات v3.6.16 شامل زیباسازی کارت‌های پرونده، برجسته‌سازی مالی، اصلاح Back، حذف دکمه متنی امروز و چک‌باکس ساده جلسه‌های رسیدگی در فهرست امروز.

## یادداشت ساخت

- فایل workflow و `pubspec.yaml` به نسخه جدید به‌روزرسانی شد.
- در این محیط Flutter نصب نبود، بنابراین `flutter analyze` محلی اجرا نشد.
