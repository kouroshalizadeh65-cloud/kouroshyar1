# تغییرات کوروش‌یار v3.6.47+119

## اصلاح خطاهای Analyze

- حذف `const` از هفت فهرست `FilteringTextInputFormatter.digitsOnly` در صفحات پشتیبان، قفل و امنیت.
- حذف import اضافی `cross_file` از صفحه پشتیبان.
- حذف فراخوانی تابع تعریف‌نشده `_dominantFinanceType` در خلاصه هزینه و درآمدها.
- استفاده از `querySummaryAmount` و `querySummaryColor` برای نمایش صحیح خلاصه جستجوی ترکیبی.
- به‌روزرسانی شماره نسخه به `3.6.47+119`.
- اصلاح نام APK و Artifact در GitHub Actions به نسخه `3.6.47`.

## علت Hotfix

در GitHub Actions نسخه `v3.6.46`، تست‌ها عبور کردند اما `flutter analyze` هشت خطای مانع Build و یک هشدار گزارش کرد. این نسخه دقیقاً همان موارد گزارش‌شده را اصلاح می‌کند.
