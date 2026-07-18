# کوروش‌یار v3.6.32+104

## محور نسخه
رفع خطای analyze مربوط به import اضافه در نمایشگر پیوست‌ها.

## تغییرات
- حذف import غیرضروری `package:cross_file/cross_file.dart` از فایل `lib/features/cases/case_attachment_viewer_screen.dart`.
- حفظ تمام قابلیت‌های نسخه v3.6.31 شامل پیوست‌های تاریخچه و مالی، نمایشگر داخلی PDF/عکس، اشتراک‌گذاری فایل اصلی، و استخراج/جستجوی متن PDF متنی.
- به‌روزرسانی نسخه برنامه به `3.6.32+104`.

## یادداشت تست
در محیط ChatGPT، Flutter/Dart نصب نبود و `flutter analyze` محلی اجرا نشد. این نسخه باید در GitHub Actions تست شود.
