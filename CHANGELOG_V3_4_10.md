# کوروش‌یار ۳.۴.۱۰ — پاکسازی و پایدارسازی عمومی

هدف این نسخه افزودن قابلیت جدید نیست؛ تمرکز روی پایدارتر شدن نسخه نصب‌شده و حذف خطاهای گذرا و پیام‌های مبهم است.

## تغییرات اصلی

- نسخه برنامه به `3.4.10+60` تغییر کرد.
- نام APK و Artifact نسخه‌دار و بدون تداخل شد.
- پیام خطای عمومی Flutter از حالت کارت بزرگ و آزاردهنده به پیام کوچک‌تر و پایدارتر تبدیل شد.
- صفحه امروز حالت‌های بارگذاری، خالی و خطا را بهتر از هم جدا می‌کند.
- در صفحه امروز، خطاهای موقت داده‌ای نباید به شکل شکست کامل صفحه دیده شوند.
- گزارش‌های تصمیم‌ساز در خطاهای دریافت داده، پیام پایدارتر و قابل فهم‌تر نشان می‌دهند.
- پیام‌های مبهم مثل «فعلاً باز نشد» از مسیرهای اصلی حذف یا دقیق‌تر شدند.
- صفحه «وضعیت سلامت برنامه» به بخش «بیشتر» اضافه شد تا شمارش داده‌های اصلی و وضعیت پایه برنامه دیده شود.

## فایل‌های تغییرکرده

- `pubspec.yaml`
- `.github/workflows/build-apk.yml`
- `lib/main.dart`
- `lib/features/today/today_screen.dart`
- `lib/features/reports/reports_screen.dart`
- `lib/features/cases/cases_screen.dart`
- `lib/features/cases/case_detail_screen.dart`
- `lib/features/more/more_screen.dart`
- `lib/features/health/app_health_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/app_info/app_info_screen.dart`
- `README.md`

## مواردی که عمداً اضافه نشد

- اعلان گوشی
- منشور کوروش‌یار
- OCR
- AI آنلاین جدید
- همگام‌سازی ابری
- پرتال موکل

این نسخه باید با GitHub Actions و نصب روی گوشی تست شود.
