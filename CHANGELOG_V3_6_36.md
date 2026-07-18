# کوروش‌یار v3.6.36+108

## هدف نسخه

اصلاح خطای build نسخه v3.6.35 و نهایی‌سازی مسیر امضای دائمی APK.

## تغییرات

- رفع تداخل وابستگی‌ها بین PDF Viewer و اشتراک‌گذاری فایل با قفل کردن نسخه‌های Syncfusion روی نسخه سازگار.
- حفظ نمایش PDF با جستجو و هایلایت داخل خود PDF.
- حفظ اشتراک‌گذاری فایل اصلی از مسیر داخلی برنامه.
- تغییر نسخه برنامه به `3.6.36+108`.
- تغییر نام APK خروجی به `kouroshyar_v3_6_36_dependency_signing_hotfix_1405_04_16.apk`.
- حذف ساخت keystore موقت در GitHub Actions برای release.
- الزام GitHub Actions به وجود چهار Secret امضای دائمی:
  - `KOUROSHYAR_KEYSTORE_BASE64`
  - `KOUROSHYAR_KEYSTORE_PASSWORD`
  - `KOUROSHYAR_KEY_PASSWORD`
  - `KOUROSHYAR_KEY_ALIAS`
- افزودن راهنمای ساده `SIGNING_SETUP_V3_6_36.md`.

## نکته تست

در این محیط Flutter/Dart نصب نبود؛ بنابراین `flutter analyze` و `flutter build` محلی اجرا نشد. تست اصلی باید با GitHub Actions انجام شود.
