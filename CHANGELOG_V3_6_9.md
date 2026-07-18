# کوروش‌یار v3.6.9

## اصلاح فوری Build / GitHub Actions

این نسخه برای رفع خطای Invalid workflow file آماده شد.

### اصلاحات

- رفع خطای YAML در `.github/workflows/build-apk.yml` روی خط مربوط به `data_extraction_rules.xml`.
- حذف XML خام چندخطی از متن workflow و جایگزینی با ساخت رشته امن در Python.
- حفظ اصلاحات امنیتی نسخه قبل برای غیرفعال‌سازی Auto Backup / Restore داده‌های حساس.
- حفظ اصلاحات SafeArea، تقویم شمسی، فیلدهای لیستی و پاکسازی UI نسخه v3.6.8.

### نسخه

- `pubspec.yaml`: `3.6.9+81`
- APK هدف: `kouroshyar_v3_6_9_workflow_yaml_security_fix_1405_04_14.apk`
