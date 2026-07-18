# Build Fix v3.4.5 - Analyze source

## خطای GitHub Actions

مرحله `Analyze source` با سه هشدار `unused_local_variable` در فایل زیر شکست خورد:

`lib/features/cases/case_detail_screen.dart`

متغیرهای استفاده‌نشده:

- `relatedPeople`
- `income`
- `expense`

## اصلاح انجام‌شده

این متغیرها در نمای حقوقی پرونده استفاده شدند تا اطلاعات زیر نمایش داده شود:

- تعداد اشخاص مرتبط
- درآمد پرونده
- هزینه پرونده
- مانده پرونده

همچنین نام APK و Artifact برای جلوگیری از تداخل فایل خروجی نسخه‌دار شد.

## نکته

کد برنامه بازنویسی نشد؛ فقط خطای واقعی مرحله Analyze اصلاح شد.
