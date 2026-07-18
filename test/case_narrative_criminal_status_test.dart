import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/database/app_database.dart';
import 'package:kouroshyar/features/cases/case_narrative_service.dart';

void main() {
  test('شرح کیفری وضعیت را بر اساس آخرین اقدام واقعی می‌سازد', () {
    final item = Case(
      id: 1,
      title: 'پرونده کیفری آزمایشی',
      clientName: 'شاکی',
      opponentName: 'متهم',
      subject: 'ایراد اتهام',
      caseType: 'کیفری',
      status: 'فعال',
      createdAt: DateTime(2026, 1, 1),
    );

    final result = const CaseNarrativeService().generate(
      item: item,
      people: const <CasePerson>[],
      events: [
        CaseTimelineEvent(
          id: 1,
          caseId: 1,
          title: 'تاریخ صدور کیفرخواست',
          eventType: 'تاریخ صدور کیفرخواست',
          eventDate: DateTime(2026, 2, 1),
          isDone: true,
          includeInNarrative: true,
          createdAt: DateTime(2026, 2, 1),
        ),
        CaseTimelineEvent(
          id: 2,
          caseId: 1,
          title: 'تاریخ صدور رای',
          eventType: 'تاریخ صدور رای',
          decisionSummary: 'محکومیت متهم',
          eventDate: DateTime(2026, 3, 1),
          isDone: true,
          includeInNarrative: true,
          createdAt: DateTime(2026, 3, 1),
        ),
      ],
    );

    expect(result.text, contains('رای'));
    expect(result.text, isNot(contains('پرونده پس از صدور یا ارسال کیفرخواست در مرحله رسیدگی دادگاه کیفری قرار دارد.')));
    expect(result.text, contains('پرونده پس از صدور یا ابلاغ رای در مرحله پیگیری بعدی قرار دارد.'));
  });
}
