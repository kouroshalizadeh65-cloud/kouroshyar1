# Build fix v3.4.4

## خطای مشاهده‌شده

در GitHub Actions، مرحله `Build release APK` با خطای زیر متوقف شد:

```text
SigningConfig with name 'release' not found.
```

## علت

در workflow، پس از اجرای `flutter create . --platforms=android`، فایل `android/app/build.gradle.kts` ساخته می‌شود. این فایل در بخش `buildTypes.release` به signingConfig اشاره می‌کند، اما signingConfig با نام `release` تعریف نشده بود.

## اصلاح انجام‌شده

در `.github/workflows/build-apk.yml` شرط patch اصلاح شد تا وجود عبارت `signingConfigs` در خط `signingConfig = signingConfigs.getByName("debug")` باعث جا افتادن ساختار `signingConfigs { create("release") ... }` نشود.

## دامنه تغییر

این اصلاح فقط Build را هدف می‌گیرد و تغییری در قابلیت‌های برنامه ایجاد نمی‌کند.
