# تغییرات v3.6.28

نسخه برنامه: `3.6.28+100`

## محور نسخه

Hotfix رفع خطای build/analyze در صفحه جزئیات پرونده پس از نسخه v3.6.27.

## اصلاحات

- بازگردانی و تعریف دوباره بخش‌های حذف‌شده/جاافتاده در `case_detail_screen.dart`:
  - `_CaseDocumentsSection`
  - `_CaseTasksSection`
  - `_CaseHistorySection`
  - `_FinanceSummaryLine`
- رفع خطاهای `undefined_method` گزارش‌شده در GitHub Actions.
- رفع هشدار `unused_element` مربوط به `_caseHistorySubtitle` با استفاده مجدد در نمایش تاریخچه.
- حفظ تغییرات نسخه v3.6.27 شامل شرح پرونده طبیعی، حالت‌های کوتاه/معمولی/کامل و متن قابل ویرایش.

## نکته تست

در محیط ChatGPT، Flutter/Dart نصب نبود و `flutter analyze` محلی اجرا نشد. تست نهایی باید با GitHub Actions انجام شود.
