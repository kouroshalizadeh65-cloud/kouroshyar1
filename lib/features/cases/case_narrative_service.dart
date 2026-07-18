import '../../core/utils/date_format_fa.dart';
import '../../database/app_database.dart';

enum CaseNarrativeMode { short, normal, full }

class CaseNarrativeResult {
  const CaseNarrativeResult({
    required this.text,
    required this.usedEventsCount,
    required this.hasTimelineData,
  });

  final String text;
  final int usedEventsCount;
  final bool hasTimelineData;
}

class CaseNarrativeService {
  const CaseNarrativeService();

  CaseNarrativeResult generate({
    required Case item,
    required List<CasePerson> people,
    required List<CaseTimelineEvent> events,
    UserProfile? profile,
    CaseNarrativeMode mode = CaseNarrativeMode.normal,
  }) {
    final narrativeEvents = events
        .where((event) => event.includeInNarrative && !_isFutureEvent(event) && !_isRawScheduledSession(event))
        .toList()
      ..sort((a, b) {
        final dateCompare = a.eventDate.compareTo(b.eventDate);
        if (dateCompare != 0) return dateCompare;
        return a.id.compareTo(b.id);
      });

    final petitionEvent = _firstWhereOrNull(narrativeEvents, _isInitialPetitionEvent);
    final usedEventIds = <int>{};
    final addedKinds = <String>{};
    final timelineSentences = <String>[];

    if (petitionEvent != null) usedEventIds.add(petitionEvent.id);

    for (final event in narrativeEvents) {
      if (usedEventIds.contains(event.id)) continue;
      final sentence = _sentenceForEvent(event, addedKinds);
      if (sentence.isEmpty) continue;
      usedEventIds.add(event.id);
      timelineSentences.add(sentence);
    }

    final openingSentence = _buildOpeningSentence(item, people, petitionEvent, profile);
    final statusSentence = _buildStatusSentence(item, narrativeEvents, addedKinds);
    final sentences = <String>[openingSentence];

    switch (mode) {
      case CaseNarrativeMode.short:
        if (timelineSentences.isNotEmpty) {
          sentences.add(timelineSentences.last);
        }
        if (statusSentence.isNotEmpty && !statusSentence.startsWith('برای تکمیل شرح پرونده')) {
          sentences.add(statusSentence);
        }
        break;
      case CaseNarrativeMode.normal:
        final contextSentence = _buildNaturalCaseContextSentence(item, full: false);
        if (contextSentence.isNotEmpty) sentences.add(contextSentence);
        sentences.addAll(timelineSentences);
        if (statusSentence.isNotEmpty) sentences.add(statusSentence);
        break;
      case CaseNarrativeMode.full:
        final contextSentence = _buildNaturalCaseContextSentence(item, full: true);
        if (contextSentence.isNotEmpty) sentences.add(contextSentence);
        sentences.addAll(timelineSentences);
        if (statusSentence.isNotEmpty) sentences.add(statusSentence);
        break;
    }

    return CaseNarrativeResult(
      text: _normalizeSpacing(sentences.where((line) => line.trim().isNotEmpty).join(' ')),
      usedEventsCount: usedEventIds.length,
      hasTimelineData: narrativeEvents.isNotEmpty,
    );
  }

  CaseTimelineEvent? _firstWhereOrNull(
    Iterable<CaseTimelineEvent> events,
    bool Function(CaseTimelineEvent event) test,
  ) {
    for (final event in events) {
      if (test(event)) return event;
    }
    return null;
  }

  String _buildOpeningSentence(
    Case item,
    List<CasePerson> people,
    CaseTimelineEvent? petitionEvent,
    UserProfile? profile,
  ) {
    final datePrefix = petitionEvent == null ? 'در این پرونده ' : 'در تاریخ ${formatPersianLongDate(petitionEvent.eventDate)}، ';
    final subject = _clean(item.subject).isNotEmpty ? _clean(item.subject) : _clean(item.title);
    final court = _courtText(item);
    final lawyer = _lawyerText(profile);
    final clientRole = _clean(item.clientRole);

    if (_isCriminalCase(item)) {
      var complainant = _complainantText(item, people);
      var accused = _accusedText(item, people);
      if (lawyer.isNotEmpty) {
        if (clientRole.contains('شاکی') && complainant.isNotEmpty) {
          complainant = '$complainant با وکالت $lawyer';
        } else if ((clientRole.contains('متهم') || clientRole.contains('مشتکی')) && accused.isNotEmpty) {
          accused = '$accused با وکالت $lawyer';
        }
      }
      final buffer = StringBuffer(datePrefix);
      buffer.write(complainant.isEmpty ? 'شاکی' : complainant);
      if (subject.isNotEmpty) {
        buffer.write(' شکواییه‌ای با موضوع $subject');
      } else {
        buffer.write(' شکواییه‌ای');
      }
      if (accused.isNotEmpty) buffer.write(' علیه $accused');
      if (court.isNotEmpty) buffer.write(' در $court');
      buffer.write(' مطرح نموده است.');
      return buffer.toString();
    }

    var plaintiff = _plaintiffText(item, people);
    var defendant = _defendantText(item, people);

    if (lawyer.isNotEmpty) {
      if (clientRole.contains('خواهان') && plaintiff.isNotEmpty) {
        plaintiff = '$plaintiff با وکالت $lawyer';
      } else if (clientRole.contains('خوانده') && defendant.isNotEmpty) {
        defendant = '$defendant با وکالت $lawyer';
      }
    }

    final buffer = StringBuffer(datePrefix);
    buffer.write(plaintiff.isEmpty ? 'خواهان' : plaintiff);

    if (subject.isNotEmpty) {
      buffer.write(' دادخواستی با موضوع $subject');
    } else {
      buffer.write(' دادخواستی');
    }

    if (defendant.isNotEmpty) buffer.write(' به طرفیت $defendant');
    if (court.isNotEmpty) buffer.write(' به $court');
    buffer.write(' تقدیم نموده است.');
    return buffer.toString();
  }

  String _buildNaturalCaseContextSentence(Case item, {required bool full}) {
    final caseNumber = _clean(item.caseNumber);
    final archiveNumber = _clean(item.archiveNumber);
    final court = _clean(item.court);
    final branch = _clean(item.branch);
    final judge = _clean(item.judge);
    final title = _clean(item.title);
    final subject = _clean(item.subject);
    final caseType = _clean(item.caseType);
    final stage = _clean(item.stage);
    final currentRole = _clean(item.currentRole);
    final status = _clean(item.status);
    final nextAction = _clean(item.nextAction);

    final sentences = <String>[];
    final registryParts = <String>[];
    if (caseNumber.isNotEmpty) registryParts.add('شماره پرونده $caseNumber');
    if (archiveNumber.isNotEmpty) registryParts.add('شماره بایگانی $archiveNumber');

    var courtText = '';
    if (court.isNotEmpty && branch.isNotEmpty && !court.contains(branch)) {
      courtText = '$court، $branch';
    } else if (court.isNotEmpty) {
      courtText = court;
    } else if (branch.isNotEmpty) {
      courtText = branch;
    }
    if (courtText.isNotEmpty) registryParts.add(courtText);
    if (judge.isNotEmpty) registryParts.add('نزد قاضی $judge');

    if (registryParts.isNotEmpty) {
      sentences.add('پرونده با ${registryParts.join('، ')} در جریان رسیدگی قرار گرفته است.');
    }

    if (full) {
      final detailParts = <String>[];
      if (title.isNotEmpty && title != subject) detailParts.add('با عنوان $title');
      if (caseType.isNotEmpty) detailParts.add('از نوع $caseType');
      if (stage.isNotEmpty) detailParts.add('در مرحله $stage');
      if (currentRole.isNotEmpty) detailParts.add('با سمت فعلی موکل $currentRole');
      if (status.isNotEmpty && status != 'فعال') detailParts.add('در وضعیت $status');
      if (detailParts.isNotEmpty) {
        sentences.add('پرونده ${detailParts.join('، ')} ثبت شده است.');
      }
      if (nextAction.isNotEmpty) {
        sentences.add('اقدام بعدی پرونده $nextAction است.');
      }
    }

    return sentences.join(' ');
  }

  String _sentenceForEvent(CaseTimelineEvent event, Set<String> addedKinds) {
    if (_isFutureEvent(event) || _isRawScheduledSession(event)) return '';

    final text = _normalizedEventText(event);
    final dateText = formatPersianLongDate(event.eventDate);
    final originalType = _clean(event.eventType).isEmpty ? _clean(event.title) : _clean(event.eventType);

    final criminalSentence = _criminalSentenceForEvent(event, text, dateText, addedKinds);
    if (criminalSentence.isNotEmpty) return criminalSentence;

    if (_isHearingScheduleEvent(event)) {
      if (!addedKinds.add('scheduledHearing:${event.id}')) return '';
      return 'وقت رسیدگی برای مورخ $dateText تعیین شده است.';
    }

    if (_isHearingNoticeEvent(event)) {
      if (!addedKinds.add('hearingNotice:${event.id}')) return '';
      return 'وقت رسیدگی در تاریخ $dateText ابلاغ گردیده است.';
    }

    if (_isHearingEvent(event)) {
      final hearingTitle = _hearingTitleText(event);
      final kind = 'hearing:${_normalize(hearingTitle)}:${event.eventDate.year}-${event.eventDate.month}-${event.eventDate.day}';
      if (!addedKinds.add(kind)) return '';
      return '$hearingTitle در تاریخ $dateText برگزار گردیده است.';
    }

    if (text.contains('ارجاع به شعبه')) {
      if (!addedKinds.add('branchReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده به شعبه رسیدگی‌کننده ارجاع شده است.';
    }

    if (text.contains('تقدیم لایحه')) {
      if (!addedKinds.add('brief:${event.id}')) return '';
      return 'در تاریخ $dateText، لایحه در پرونده تقدیم شده است.';
    }

    if (text.contains('اخذ توضیح')) {
      if (!addedKinds.add('explanation:${event.id}')) return '';
      return 'در تاریخ $dateText، موضوع اخذ توضیح در پرونده انجام یا ثبت شده است.';
    }

    if (text.contains('وصول پاسخ استعلام')) {
      if (!addedKinds.add('inquiryAnswer:${event.id}')) return '';
      return 'در تاریخ $dateText، پاسخ استعلام واصل و در پرونده ثبت شده است.';
    }

    if (text.contains('استعلام')) {
      if (!addedKinds.add('inquiry:${event.id}')) return '';
      return 'در تاریخ $dateText، استعلام مربوط به پرونده انجام یا ثبت شده است.';
    }

    if (text.contains('معاینه محل')) {
      if (!addedKinds.add('localInspection:${event.id}')) return '';
      return 'در تاریخ $dateText، معاینه محل در پرونده انجام یا ثبت شده است.';
    }

    if (text.contains('تحقیق محلی')) {
      if (!addedKinds.add('localResearch:${event.id}')) return '';
      return 'در تاریخ $dateText، تحقیق محلی در پرونده انجام یا ثبت شده است.';
    }

    if (text.contains('تعیین کارشناس')) {
      if (!addedKinds.add('expertSelected:${event.id}')) return '';
      return 'در تاریخ $dateText، کارشناس پرونده تعیین شده است.';
    }

    if (text.contains('پرداخت دستمزد کارشناس')) {
      if (!addedKinds.add('expertFee:${event.id}')) return '';
      return 'در تاریخ $dateText، دستمزد کارشناس پرداخت یا ثبت شده است.';
    }

    if (_isExpertObjectionEvent(event)) {
      if (!addedKinds.add('expertObjection:${event.id}')) return '';
      final actor = _actorText(event.actorRole);
      return 'در تاریخ $dateText، $actor نسبت به نظریه کارشناسی اعتراض نموده است.';
    }

    if (_isExpertPanelOpinionEvent(event)) {
      if (!addedKinds.add('expertPanelOpinion:${event.id}')) return '';
      return 'در تاریخ $dateText، نظریه هیأت کارشناسی واصل و در پرونده ثبت شده است.';
    }

    if (_isExpertPanelEvent(event)) {
      if (!addedKinds.add('expertPanel:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده جهت ارجاع به هیأت کارشناسی مطرح گردیده است.';
    }

    if (_isExpertOpinionEvent(event)) {
      if (!addedKinds.add('expertOpinion:${event.id}')) return '';
      return 'در تاریخ $dateText، نظریه کارشناسی واصل و در پرونده ثبت شده است.';
    }

    if (_isExpertReferralEvent(event)) {
      if (!addedKinds.add('expertReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده به کارشناسی ارجاع گردیده است.';
    }

    if (text.contains('صدور قرار کارشناسی')) {
      if (!addedKinds.add('expertOrder:${event.id}')) return '';
      return 'در تاریخ $dateText، قرار کارشناسی صادر شده است.';
    }

    if (text.contains('تامین خواسته') || text.contains('تأمین خواسته')) {
      if (!addedKinds.add('securityOrder:${event.id}')) return '';
      return 'در تاریخ $dateText، قرار تأمین خواسته صادر یا ثبت شده است.';
    }

    if (text.contains('دستور موقت')) {
      if (!addedKinds.add('temporaryOrder:${event.id}')) return '';
      return 'در تاریخ $dateText، دستور موقت صادر یا ثبت شده است.';
    }

    if (text.contains('صدور قرار')) {
      if (!addedKinds.add('order:${event.id}')) return '';
      return 'در تاریخ $dateText، قرار مربوط به پرونده صادر شده است.';
    }

    if (text.contains('ختم رسیدگی')) {
      if (!addedKinds.add('closeTrial:${event.id}')) return '';
      return 'در تاریخ $dateText، ختم رسیدگی اعلام شده است.';
    }

    if (text.contains('ابلاغ رای تجدیدنظر')) {
      if (!addedKinds.add('appealJudgmentNotice:${event.id}')) return '';
      return 'در تاریخ $dateText، رای تجدیدنظر ابلاغ گردیده است.';
    }

    if (text.contains('صدور رای تجدیدنظر')) {
      if (!addedKinds.add('appealJudgment:${event.id}')) return '';
      final decision = _decisionText(event);
      if (decision.isEmpty) return 'در تاریخ $dateText، رای تجدیدنظر صادر گردیده است.';
      return 'در تاریخ $dateText، رای تجدیدنظر مبنی بر $decision صادر گردیده است.';
    }

    if (text.contains('صدور رای دیوان عالی کشور')) {
      if (!addedKinds.add('supremeJudgment:${event.id}')) return '';
      final decision = _decisionText(event);
      if (decision.isEmpty) return 'در تاریخ $dateText، رای دیوان عالی کشور صادر شده است.';
      return 'در تاریخ $dateText، رای دیوان عالی کشور مبنی بر $decision صادر شده است.';
    }

    if (_isJudgmentEvent(event)) {
      if (!addedKinds.add('judgment:${event.id}')) return '';
      final decision = _decisionText(event);
      if (decision.isEmpty) return 'در تاریخ $dateText، رای دادگاه صادر گردیده است.';
      return 'در تاریخ $dateText، رای بر $decision صادر گردیده است.';
    }

    if (text.contains('ابلاغ رای')) {
      if (!addedKinds.add('judgmentNotice:${event.id}')) return '';
      return 'در تاریخ $dateText، رای صادره ابلاغ گردیده است.';
    }

    if (_isAppealEvent(event)) {
      if (!addedKinds.add('appeal:${event.id}')) return '';
      final actor = _actorText(event.actorRole);
      return 'در تاریخ $dateText، $actor نسبت به رای صادره تجدیدنظرخواهی نموده است.';
    }

    if (text.contains('واخواهی')) {
      if (!addedKinds.add('objection:${event.id}')) return '';
      final actor = _actorText(event.actorRole);
      return 'در تاریخ $dateText، $actor نسبت به رای صادره واخواهی نموده است.';
    }

    if (_isCassationEvent(event)) {
      if (!addedKinds.add('cassation:${event.id}')) return '';
      final actor = _actorText(event.actorRole);
      return 'در تاریخ $dateText، $actor نسبت به رای صادره فرجام‌خواهی نموده است.';
    }

    if (_isRetrialEvent(event)) {
      if (!addedKinds.add('retrial:${event.id}')) return '';
      final actor = _actorText(event.actorRole);
      return 'در تاریخ $dateText، $actor درخواست اعاده دادرسی مطرح نموده است.';
    }

    if (text.contains('اعتراض ثالث')) {
      if (!addedKinds.add('thirdPartyObjection:${event.id}')) return '';
      return 'در تاریخ $dateText، اعتراض ثالث نسبت به رای یا جریان پرونده ثبت شده است.';
    }

    if (text.contains('ارجاع به دادگاه تجدیدنظر')) {
      if (!addedKinds.add('appealCourtReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده به دادگاه تجدیدنظر ارجاع شده است.';
    }

    if (text.contains('جلسه تجدیدنظر')) {
      if (!addedKinds.add('appealHearing:${event.id}')) return '';
      return 'در تاریخ $dateText، جلسه تجدیدنظر برگزار یا برای رسیدگی ثبت شده است.';
    }

    if (text.contains('قطعیت رای')) {
      if (!addedKinds.add('finalJudgment:${event.id}')) return '';
      return 'در تاریخ $dateText، رای صادره قطعیت یافته است.';
    }

    if (text.contains('ارسال به دیوان عالی کشور')) {
      if (!addedKinds.add('supremeReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده به دیوان عالی کشور ارسال شده است.';
    }

    if (text.contains('صدور اجراییه') || text.contains('صدور اجرائیه')) {
      if (!addedKinds.add('executionWrit:${event.id}')) return '';
      return 'در تاریخ $dateText، اجراییه صادر شده است.';
    }

    if (text.contains('ابلاغ اجراییه') || text.contains('ابلاغ اجرائیه')) {
      if (!addedKinds.add('executionNotice:${event.id}')) return '';
      return 'در تاریخ $dateText، اجراییه ابلاغ شده است.';
    }

    if (text.contains('تشکیل پرونده اجرایی')) {
      if (!addedKinds.add('executionCase:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده اجرایی تشکیل شده است.';
    }

    if (text.contains('توقیف مال')) {
      if (!addedKinds.add('seizure:${event.id}')) return '';
      return 'در تاریخ $dateText، توقیف مال در پرونده اجرایی ثبت شده است.';
    }

    if (text.contains('مزایده')) {
      if (!addedKinds.add('auction:${event.id}')) return '';
      return 'در تاریخ $dateText، مزایده مربوط به پرونده اجرایی ثبت یا برگزار شده است.';
    }

    if (text.contains('پرداخت محکوم به') || text.contains('پرداخت محکوم‌به')) {
      if (!addedKinds.add('payment:${event.id}')) return '';
      return 'در تاریخ $dateText، پرداخت محکوم‌به ثبت شده است.';
    }

    if (text.contains('مختومه شدن اجرا')) {
      if (!addedKinds.add('executionClosed:${event.id}')) return '';
      return 'در تاریخ $dateText، عملیات اجرایی پرونده مختومه شده است.';
    }

    if (text.contains('مختومه شدن پرونده')) {
      if (!addedKinds.add('caseClosed:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده مختومه شده است.';
    }

    if (_isDeadlineDoneEvent(event)) {
      if (!addedKinds.add('deadlineDone:${event.id}')) return '';
      return 'در تاریخ $dateText، مهلت قانونی مرتبط با پرونده انجام یا پیگیری شده است.';
    }

    if (_isTaskDoneEvent(event)) {
      if (!addedKinds.add('taskDone:${event.id}')) return '';
      final title = _clean(event.title).replaceFirst('انجام کار:', '').trim();
      if (title.isEmpty) return 'در تاریخ $dateText، اقدام ثبت‌شده پرونده انجام شده است.';
      return 'در تاریخ $dateText، اقدام «$title» انجام شده است.';
    }

    if (originalType.isNotEmpty) {
      if (!addedKinds.add('general:${event.id}')) return '';
      return 'در تاریخ $dateText، $originalType در پرونده ثبت شده است.';
    }

    return '';
  }

  String _criminalSentenceForEvent(CaseTimelineEvent event, String text, String dateText, Set<String> addedKinds) {
    if (text.contains('ارجاع شکواییه به دادسرا')) {
      if (!addedKinds.add('criminalComplaintReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، شکواییه به دادسرا ارجاع شده است.';
    }
    if (text.contains('شعبه دادیاری') || text.contains('شعبه بازپرسی') || text.contains('دادیاری') || text.contains('بازپرسی')) {
      if (!addedKinds.add('criminalInvestigationBranch:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده به شعبه دادیاری یا بازپرسی ارجاع شده است.';
    }
    if (text.contains('کلانتری') || text.contains('اگاهی') || text.contains('آگاهی') || text.contains('ضابط')) {
      if (text.contains('وصول گزارش')) {
        if (!addedKinds.add('officerReport:${event.id}')) return '';
        return 'در تاریخ $dateText، گزارش ضابط واصل و در پرونده ثبت شده است.';
      }
      if (text.contains('تکمیل تحقیقات')) {
        if (!addedKinds.add('officerInvestigationDone:${event.id}')) return '';
        return 'در تاریخ $dateText، تکمیل تحقیقات ضابط در پرونده ثبت شده است.';
      }
      if (text.contains('ارسال پرونده') && text.contains('دادسرا')) {
        if (!addedKinds.add('officerToProsecutor:${event.id}')) return '';
        return 'در تاریخ $dateText، پرونده از ضابط به دادسرا ارسال شده است.';
      }
      if (!addedKinds.add('officerReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده جهت انجام تحقیقات به ضابط مربوط ارجاع شده است.';
    }
    if (text.contains('احضار شاکی')) {
      if (!addedKinds.add('complainantSummon:${event.id}')) return '';
      return 'در تاریخ $dateText، احضار شاکی در پرونده ثبت شده است.';
    }
    if (text.contains('اخذ اظهارات شاکی') || text.contains('استماع اظهارات شاکی')) {
      if (!addedKinds.add('complainantStatement:${event.id}')) return '';
      return 'در تاریخ $dateText، اظهارات شاکی استماع یا اخذ شده است.';
    }
    if (text.contains('احضار متهم')) {
      if (!addedKinds.add('accusedSummon:${event.id}')) return '';
      return 'در تاریخ $dateText، احضار متهم در پرونده ثبت شده است.';
    }
    if (text.contains('جلب متهم')) {
      if (!addedKinds.add('accusedArrestOrder:${event.id}')) return '';
      return 'در تاریخ $dateText، جلب متهم در پرونده ثبت شده است.';
    }
    if (text.contains('تفهیم اتهام')) {
      if (!addedKinds.add('chargeExplained:${event.id}')) return '';
      return 'در تاریخ $dateText، اتهام به متهم تفهیم شده است.';
    }
    if (text.contains('اخذ دفاعیات متهم') || text.contains('دفاع متهم')) {
      if (!addedKinds.add('accusedDefense:${event.id}')) return '';
      return 'در تاریخ $dateText، دفاعیات متهم اخذ یا استماع شده است.';
    }
    if (text.contains('اخرین دفاع') || text.contains('آخرین دفاع')) {
      if (!addedKinds.add('lastDefense:${event.id}')) return '';
      return 'در تاریخ $dateText، آخرین دفاع متهم اخذ شده است.';
    }
    if (text.contains('شهادت شهود') || text.contains('تحقیق از گواه')) {
      if (!addedKinds.add('witness:${event.id}')) return '';
      return 'در تاریخ $dateText، شهادت شهود یا اظهارات گواه در پرونده استماع شده است.';
    }
    if (text.contains('مواجهه حضوری')) {
      if (!addedKinds.add('confrontation:${event.id}')) return '';
      return 'در تاریخ $dateText، مواجهه حضوری در پرونده انجام یا ثبت شده است.';
    }
    if (text.contains('قرار تامین کیفری') || text.contains('قرار تأمین کیفری')) {
      if (!addedKinds.add('criminalBailOrder:${event.id}')) return '';
      return text.contains('ابلاغ') ? 'در تاریخ $dateText، قرار تامین کیفری ابلاغ شده است.' : 'در تاریخ $dateText، قرار تامین کیفری صادر شده است.';
    }
    if (text.contains('قبولی کفالت')) {
      if (!addedKinds.add('suretyAccepted:${event.id}')) return '';
      return 'در تاریخ $dateText، قبولی کفالت در پرونده ثبت شده است.';
    }
    if (text.contains('تودیع وثیقه')) {
      if (!addedKinds.add('bailDeposit:${event.id}')) return '';
      return 'در تاریخ $dateText، تودیع وثیقه در پرونده ثبت شده است.';
    }
    if (text.contains('بازداشت متهم')) {
      if (!addedKinds.add('accusedDetention:${event.id}')) return '';
      return 'در تاریخ $dateText، بازداشت متهم در پرونده ثبت شده است.';
    }
    if (text.contains('ازادی متهم') || text.contains('آزادی متهم')) {
      if (!addedKinds.add('accusedRelease:${event.id}')) return '';
      return 'در تاریخ $dateText، آزادی متهم در پرونده ثبت شده است.';
    }
    if (text.contains('تبدیل قرار تامین') || text.contains('تشدید قرار تامین') || text.contains('فک قرار تامین')) {
      if (!addedKinds.add('bailChange:${event.id}')) return '';
      return 'در تاریخ $dateText، تغییر وضعیت قرار تامین در پرونده ثبت شده است.';
    }
    if (text.contains('قرار نظارت قضایی')) {
      if (!addedKinds.add('judicialSupervision:${event.id}')) return '';
      return text.contains('لغو') ? 'در تاریخ $dateText، لغو قرار نظارت قضایی ثبت شده است.' : 'در تاریخ $dateText، قرار نظارت قضایی صادر شده است.';
    }
    if (text.contains('ختم تحقیقات')) {
      if (!addedKinds.add('investigationClosed:${event.id}')) return '';
      return 'در تاریخ $dateText، ختم تحقیقات اعلام شده است.';
    }
    if (text.contains('موافقت دادستان') || text.contains('قرار جلب به دادرسی')) {
      if (!addedKinds.add('prosecutorApproval:${event.id}')) return '';
      return 'در تاریخ $dateText، موافقت دادستان با قرار جلب به دادرسی ثبت شده است.';
    }
    if (text.contains('صدور کیفرخواست')) {
      if (!addedKinds.add('indictment:${event.id}')) return '';
      return 'در تاریخ $dateText، کیفرخواست صادر شده است.';
    }
    if (text.contains('ارسال کیفرخواست')) {
      if (!addedKinds.add('indictmentToCourt:${event.id}')) return '';
      return 'در تاریخ $dateText، کیفرخواست به دادگاه ارسال شده است.';
    }
    if (text.contains('قرار منع تعقیب')) {
      if (text.contains('اعتراض')) {
        if (!addedKinds.add('noProsecutionObjection:${event.id}')) return '';
        final actor = _actorText(event.actorRole);
        return 'در تاریخ $dateText، $actor نسبت به قرار منع تعقیب اعتراض نموده است.';
      }
      if (text.contains('نقض')) {
        if (!addedKinds.add('noProsecutionReversed:${event.id}')) return '';
        return 'در تاریخ $dateText، قرار منع تعقیب نقض شده است.';
      }
      if (text.contains('تایید') || text.contains('تأیید')) {
        if (!addedKinds.add('noProsecutionConfirmed:${event.id}')) return '';
        return 'در تاریخ $dateText، قرار منع تعقیب تایید شده است.';
      }
      if (!addedKinds.add('noProsecutionNotice:${event.id}')) return '';
      return 'در تاریخ $dateText، قرار منع تعقیب ابلاغ یا ثبت شده است.';
    }
    if (text.contains('قرار موقوفی تعقیب')) {
      if (text.contains('اعتراض')) {
        if (!addedKinds.add('stopProsecutionObjection:${event.id}')) return '';
        final actor = _actorText(event.actorRole);
        return 'در تاریخ $dateText، $actor نسبت به قرار موقوفی تعقیب اعتراض نموده است.';
      }
      if (!addedKinds.add('stopProsecution:${event.id}')) return '';
      return text.contains('ابلاغ') ? 'در تاریخ $dateText، قرار موقوفی تعقیب ابلاغ شده است.' : 'در تاریخ $dateText، قرار موقوفی تعقیب صادر شده است.';
    }
    if (text.contains('دادگاه کیفری') && !text.contains('رای') && !text.contains('جلسه رسیدگی')) {
      if (!addedKinds.add('criminalCourtReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده به دادگاه کیفری ارجاع شده است.';
    }
    if (text.contains('اعاده پرونده به دادسرا')) {
      if (!addedKinds.add('returnToProsecutor:${event.id}')) return '';
      return 'در تاریخ $dateText، پرونده برای تکمیل تحقیقات به دادسرا اعاده شده است.';
    }
    if (text.contains('اجرای احکام') || text.contains('اجرای حکم')) {
      if (!addedKinds.add('criminalExecution:${event.id}')) return '';
      if (text.contains('مختومه')) return 'در تاریخ $dateText، پرونده اجرای احکام مختومه شده است.';
      if (text.contains('شروع')) return 'در تاریخ $dateText، اجرای حکم شروع شده است.';
      if (text.contains('ابلاغ احضاریه')) return 'در تاریخ $dateText، احضاریه اجرای حکم ابلاغ شده است.';
      if (text.contains('تشکیل پرونده')) return 'در تاریخ $dateText، پرونده اجرای احکام تشکیل شده است.';
      return 'در تاریخ $dateText، اقدام مربوط به اجرای حکم ثبت شده است.';
    }
    if (text.contains('تقسیط جزای نقدی')) {
      if (!addedKinds.add('fineInstallment:${event.id}')) return '';
      return 'در تاریخ $dateText، تقسیط جزای نقدی در پرونده ثبت شده است.';
    }
    if (text.contains('معرفی محکوم علیه به زندان') || text.contains('معرفی محکوم‌علیه به زندان')) {
      if (!addedKinds.add('prisonReferral:${event.id}')) return '';
      return 'در تاریخ $dateText، معرفی محکوم‌علیه به زندان ثبت شده است.';
    }
    if (text.contains('ازادی محکوم علیه') || text.contains('آزادی محکوم‌علیه') || text.contains('آزادی محکوم علیه')) {
      if (!addedKinds.add('convictRelease:${event.id}')) return '';
      return 'در تاریخ $dateText، آزادی محکوم‌علیه ثبت شده است.';
    }
    if (text.contains('تعلیق اجرای مجازات')) {
      if (!addedKinds.add('sentenceSuspension:${event.id}')) return '';
      return text.contains('لغو') ? 'در تاریخ $dateText، لغو تعلیق اجرای مجازات ثبت شده است.' : 'در تاریخ $dateText، تعلیق اجرای مجازات ثبت شده است.';
    }
    if (text.contains('گذشت شاکی') || text.contains('اعلام رضایت')) {
      if (!addedKinds.add('complainantConsent:${event.id}')) return '';
      return 'در تاریخ $dateText، گذشت یا رضایت شاکی در پرونده ثبت شده است.';
    }
    if (text.contains('ثبت سازش')) {
      if (!addedKinds.add('settlement:${event.id}')) return '';
      return 'در تاریخ $dateText، سازش طرفین در پرونده ثبت شده است.';
    }
    if (text.contains('ترک تعقیب')) {
      if (!addedKinds.add('abandonProsecution:${event.id}')) return '';
      return 'در تاریخ $dateText، قرار ترک تعقیب صادر یا ثبت شده است.';
    }
    if (text.contains('تعلیق تعقیب')) {
      if (!addedKinds.add('suspendProsecution:${event.id}')) return '';
      return 'در تاریخ $dateText، تعلیق تعقیب در پرونده ثبت شده است.';
    }
    if (text.contains('بایگانی پرونده')) {
      if (!addedKinds.add('criminalArchive:${event.id}')) return '';
      return 'در تاریخ $dateText، بایگانی پرونده ثبت شده است.';
    }
    if (text.contains('رفع اثر از دستور جلب')) {
      if (!addedKinds.add('arrestOrderLifted:${event.id}')) return '';
      return 'در تاریخ $dateText، رفع اثر از دستور جلب ثبت شده است.';
    }
    return '';
  }

  String _buildStatusSentence(Case item, List<CaseTimelineEvent> sortedEvents, Set<String> addedKinds) {
    final status = _clean(item.status);
    final stage = _clean(item.stage);
    final nextAction = _clean(item.nextAction);
    final lastMeaningfulEvent = _lastMeaningfulEvent(sortedEvents);

    if (_isCriminalCase(item)) {
      if (lastMeaningfulEvent != null) {
        final lastText = _normalizedEventText(lastMeaningfulEvent);

        if (_isCriminalExecutionStatusEvent(lastMeaningfulEvent)) {
          return 'پرونده در حال حاضر در مرحله اجرای احکام کیفری${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} قرار دارد.';
        }
        if (_isRetrialEvent(lastMeaningfulEvent)) {
          return 'پرونده در حال حاضر در مرحله رسیدگی به درخواست اعاده دادرسی${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} قرار دارد.';
        }
        if (_isCassationEvent(lastMeaningfulEvent)) {
          return 'پرونده در حال حاضر پس از فرجام‌خواهی در حال پیگیری${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} می‌باشد.';
        }
        if (_isAppealEvent(lastMeaningfulEvent)) {
          return 'پرونده در حال حاضر پس از تجدیدنظرخواهی در حال پیگیری${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} می‌باشد.';
        }
        if (_isJudgmentEvent(lastMeaningfulEvent) || lastText.contains('ابلاغ رای') || lastText.contains('قطعیت رای')) {
          if (status.isNotEmpty && status != 'فعال') return 'پرونده در حال حاضر در وضعیت $status قرار دارد.';
          return lastText.contains('قطعیت رای')
              ? 'پرونده پس از قطعیت رای در مرحله پیگیری بعدی قرار دارد.'
              : 'پرونده پس از صدور یا ابلاغ رای در مرحله پیگیری بعدی قرار دارد.';
        }
        if (_isHearingEvent(lastMeaningfulEvent)) {
          return 'پرونده پس از آخرین جلسه رسیدگی در جریان رسیدگی دادگاه کیفری می‌باشد.';
        }
        if (_isCriminalIndictmentOrCourtReferralEvent(lastMeaningfulEvent)) {
          return 'پرونده پس از صدور یا ارسال کیفرخواست در مرحله رسیدگی دادگاه کیفری قرار دارد.';
        }
        if (_isCriminalFinalProsecutionOrderEvent(lastMeaningfulEvent)) {
          return 'پرونده در حال حاضر در مرحله پیگیری قرار نهایی دادسرا${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} قرار دارد.';
        }
        if (_isCriminalInvestigationStatusEvent(lastMeaningfulEvent)) {
          return 'پرونده در حال حاضر در مرحله تحقیقات مقدماتی یا تصمیم دادسرا قرار دارد.';
        }
        if (lastText.contains('گذشت شاکی') || lastText.contains('اعلام رضایت') || lastText.contains('ثبت سازش')) {
          return status.isNotEmpty && status != 'فعال'
              ? 'پرونده با توجه به آخرین اقدام ثبت‌شده در وضعیت $status قرار دارد.'
              : 'پرونده پس از ثبت رضایت، گذشت یا سازش در مرحله پیگیری بعدی قرار دارد.';
        }
        if (lastText.contains('ترک تعقیب') || lastText.contains('تعلیق تعقیب') || lastText.contains('بایگانی پرونده')) {
          return status.isNotEmpty && status != 'فعال'
              ? 'پرونده در حال حاضر در وضعیت $status قرار دارد.'
              : 'پرونده با توجه به آخرین تصمیم دادسرا در مرحله پیگیری بعدی قرار دارد.';
        }
      }

      if (addedKinds.any((kind) => kind.startsWith('criminalExecution:') || kind.startsWith('fineInstallment:') || kind.startsWith('prisonReferral:') || kind.startsWith('convictRelease:'))) {
        return 'پرونده در حال حاضر در مرحله اجرای احکام کیفری${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} قرار دارد.';
      }
      if (addedKinds.any((kind) => kind.startsWith('noProsecution') || kind.startsWith('stopProsecution'))) {
        return 'پرونده در حال حاضر در مرحله پیگیری قرار نهایی دادسرا${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} قرار دارد.';
      }
      if (addedKinds.any((kind) => kind.startsWith('chargeExplained') || kind.startsWith('accusedDefense') || kind.startsWith('investigationClosed'))) {
        return 'پرونده در حال حاضر در مرحله تحقیقات مقدماتی یا تصمیم دادسرا قرار دارد.';
      }
    }

    if (addedKinds.any((kind) => kind.startsWith('retrial:'))) {
      return 'پرونده در حال حاضر در مرحله رسیدگی به درخواست اعاده دادرسی${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} قرار دارد.';
    }
    if (addedKinds.any((kind) => kind.startsWith('cassation:'))) {
      return 'پرونده در حال حاضر پس از فرجام‌خواهی در حال پیگیری${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} می‌باشد.';
    }
    if (addedKinds.any((kind) => kind.startsWith('appeal:'))) {
      return 'پرونده در حال حاضر پس از تجدیدنظرخواهی در حال پیگیری${status.isNotEmpty && status != 'فعال' ? ' و در وضعیت $status' : ''} می‌باشد.';
    }
    if (addedKinds.any((kind) => kind.startsWith('expertObjection:')) && !addedKinds.any((kind) => kind.startsWith('judgment:'))) {
      return 'پرونده جهت رسیدگی به اعتراض کارشناسی یا ارجاع به هیأت کارشناسی در حال رسیدگی می‌باشد.';
    }
    if (addedKinds.any((kind) => kind.startsWith('expertReferral')) && !addedKinds.any((kind) => kind.startsWith('judgment:'))) {
      return 'پرونده در حال حاضر در مرحله کارشناسی و رسیدگی تکمیلی قرار دارد.';
    }

    if (lastMeaningfulEvent != null && _isHearingEvent(lastMeaningfulEvent)) {
      return 'پرونده پس از آخرین جلسه رسیدگی در جریان رسیدگی می‌باشد.';
    }

    if (addedKinds.any((kind) => kind.startsWith('judgment:'))) {
      if (status.isNotEmpty && status != 'فعال') return 'پرونده در حال حاضر در وضعیت $status قرار دارد.';
      return 'پرونده پس از صدور رای در مرحله پیگیری بعدی قرار دارد.';
    }
    if (nextAction.isNotEmpty) return 'اقدام بعدی پرونده $nextAction است.';
    if (stage.isNotEmpty) return 'پرونده در حال حاضر در مرحله $stage قرار دارد.';
    if (status.isNotEmpty && status != 'فعال') return 'پرونده در حال حاضر در وضعیت $status قرار دارد.';
    if (sortedEvents.isNotEmpty) return 'پرونده در حال حاضر در جریان رسیدگی می‌باشد.';
    return 'برای تکمیل شرح پرونده، ثبت مراحل بعدی در تاریخچه پرونده لازم است.';
  }

  CaseTimelineEvent? _lastMeaningfulEvent(List<CaseTimelineEvent> sortedEvents) {
    for (final event in sortedEvents.reversed) {
      if (!_isInitialPetitionEvent(event) && !_isAutoTaskOrDeadlineEvent(event)) return event;
    }
    return null;
  }

  bool _isCriminalIndictmentOrCourtReferralEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('صدور کیفرخواست') || text.contains('ارسال کیفرخواست') || (text.contains('دادگاه کیفری') && !text.contains('رای') && !text.contains('جلسه رسیدگی'));
  }

  bool _isCriminalFinalProsecutionOrderEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('قرار منع تعقیب') || text.contains('قرار موقوفی تعقیب');
  }

  bool _isCriminalInvestigationStatusEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('تفهیم اتهام') ||
        text.contains('اخذ دفاعیات متهم') ||
        text.contains('دفاع متهم') ||
        text.contains('اخرین دفاع') ||
        text.contains('آخرین دفاع') ||
        text.contains('ختم تحقیقات') ||
        text.contains('قرار تامین کیفری') ||
        text.contains('قرار تأمین کیفری') ||
        text.contains('بازپرسی') ||
        text.contains('دادیاری');
  }

  bool _isCriminalExecutionStatusEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('اجرای احکام') ||
        text.contains('اجرای حکم') ||
        text.contains('تقسیط جزای نقدی') ||
        text.contains('معرفی محکوم علیه به زندان') ||
        text.contains('معرفی محکوم‌علیه به زندان') ||
        text.contains('ازادی محکوم علیه') ||
        text.contains('آزادی محکوم علیه') ||
        text.contains('آزادی محکوم‌علیه') ||
        text.contains('تعلیق اجرای مجازات');
  }

  bool _isInitialPetitionEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('ثبت دادخواست') ||
        text.contains('ثبت شکواییه') ||
        (text.contains('شکواییه') && !text.contains('ارجاع')) ||
        (text.contains('دادخواست') &&
            !text.contains('تجدیدنظر') &&
            !text.contains('فرجام') &&
            !text.contains('واخواهی') &&
            !text.contains('اعاده'));
  }

  bool _isHearingScheduleEvent(CaseTimelineEvent event) => _normalizedEventText(event).contains('تعیین وقت رسیدگی');
  bool _isHearingNoticeEvent(CaseTimelineEvent event) => _normalizedEventText(event).contains('ابلاغ وقت رسیدگی');

  bool _isHearingEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('جلسه رسیدگی') || text.contains('برگزاری جلسه') || text == 'جلسه';
  }


  bool _isExpertReferralEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('کارشناسی') && text.contains('ارجاع') && !_isExpertObjectionEvent(event) && !_isExpertPanelEvent(event);
  }

  bool _isExpertOpinionEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return (text.contains('وصول نظریه کارشناسی') || text.contains('ارائه نظریه کارشناسی')) && !_isExpertObjectionEvent(event);
  }

  bool _isExpertObjectionEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('اعتراض') && text.contains('نظریه کارشناسی');
  }

  bool _isExpertPanelOpinionEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('وصول نظریه هیات کارشناسی') || text.contains('وصول نظریه هیأت کارشناسی') || text.contains('وصول نظریه هیئت کارشناسی');
  }

  bool _isExpertPanelEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return (text.contains('هیات کارشناسی') || text.contains('هیأت کارشناسی') || text.contains('هیئت کارشناسی')) ||
        (text.contains('هیات') && text.contains('کارشناس'));
  }

  bool _isJudgmentEvent(CaseTimelineEvent event) {
    final text = _normalizedEventText(event);
    return text.contains('صدور رای') || text.contains('تاریخ صدور رای');
  }

  bool _isAppealEvent(CaseTimelineEvent event) => _normalizedEventText(event).contains('تجدیدنظرخواهی');
  bool _isCassationEvent(CaseTimelineEvent event) => _normalizedEventText(event).contains('فرجام خواهی') || _normalizedEventText(event).contains('فرجام‌خواهی');
  bool _isRetrialEvent(CaseTimelineEvent event) => _normalizedEventText(event).contains('اعاده دادرسی');

  bool _isFutureEvent(CaseTimelineEvent event) {
    final today = DateTime.now();
    final eventDay = DateTime(event.eventDate.year, event.eventDate.month, event.eventDate.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return eventDay.isAfter(todayDay);
  }

  bool _isRawScheduledSession(CaseTimelineEvent event) {
    return _normalize(_clean(event.eventType)) == 'جلسه';
  }

  bool _isAutoTaskOrDeadlineEvent(CaseTimelineEvent event) {
    final sourceType = _clean(event.sourceType);
    return sourceType == 'task' || sourceType == 'deadline';
  }

  bool _isDeadlineDoneEvent(CaseTimelineEvent event) => _normalizedEventText(event).contains('انجام مهلت');
  bool _isTaskDoneEvent(CaseTimelineEvent event) => _normalizedEventText(event).contains('انجام کار') || _normalizedEventText(event).contains('انجام اقدام');

  String _hearingTitleText(CaseTimelineEvent event) {
    final description = _clean(event.description);
    final title = _clean(event.title);
    final eventType = _normalize(_clean(event.eventType));

    if (eventType == 'جلسه') {
      final fromTitle = _meaningfulHearingText(title);
      if (fromTitle.isNotEmpty) return _asHearingTitle(fromTitle);
    }

    final fromDescription = _meaningfulHearingText(description);
    if (fromDescription.isNotEmpty) return _asHearingTitle(fromDescription);

    final fromTitle = _meaningfulHearingText(title);
    if (fromTitle.isNotEmpty) return _asHearingTitle(fromTitle);

    return 'جلسه رسیدگی';
  }

  String _meaningfulHearingText(String value) {
    var text = _clean(value);
    if (text.isEmpty) return '';

    final labeledType = _extractLabeledValue(text, const ['نوع جلسه رسیدگی', 'نوع جلسه']);
    if (labeledType.isNotEmpty) return labeledType;

    text = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('زمان جلسه'))
        .where((line) => !RegExp(r'\d{4}-\d{2}-\d{2}T').hasMatch(line))
        .join(' ')
        .trim();

    text = text
        .replaceFirst(RegExp(r'^برگزاری\s+جلسه\s*[:：]\s*'), '')
        .replaceFirst(RegExp(r'^جلسه\s*[:：]\s*'), '')
        .trim();

    final normalized = _normalize(text);
    if (text.isEmpty || normalized == 'جلسه' || normalized == 'تاریخ جلسه رسیدگی' || normalized == 'برگزاری جلسه رسیدگی' || normalized == 'جلسه رسیدگی') {
      return '';
    }
    return text;
  }

  String _extractLabeledValue(String value, List<String> labels) {
    final lines = value.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final cleanLine = line.trim();
      for (final label in labels) {
        final match = RegExp('^${RegExp.escape(label)}\\s*[:：]\\s*(.+)\$').firstMatch(cleanLine);
        if (match != null) {
          final result = _clean(match.group(1));
          if (result.isNotEmpty && !RegExp(r'\d{4}-\d{2}-\d{2}T').hasMatch(result)) {
            return result;
          }
        }
      }
    }
    return '';
  }

  String _asHearingTitle(String value) {
    final text = _clean(value);
    if (text.isEmpty) return 'جلسه رسیدگی';
    if (text.startsWith('جلسه')) return text;
    return 'جلسه $text';
  }

  String _decisionText(CaseTimelineEvent event) {
    final decisionSummary = _clean(event.decisionSummary);
    if (decisionSummary.isNotEmpty) return decisionSummary;
    final description = _clean(event.description);
    if (description.isNotEmpty) return description;
    return '';
  }

  String _eventText(CaseTimelineEvent event) => [
        event.eventType,
        event.title,
        event.description,
        event.decisionSummary,
        event.actorRole,
      ].map(_clean).where((part) => part.isNotEmpty).join(' ');

  String _normalizedEventText(CaseTimelineEvent event) => _normalize(_eventText(event));

  String _actorText(String? value) {
    final role = _clean(value);
    if (role == 'هر دو طرف') return 'طرفین پرونده';
    if (role == 'خواهان' || role == 'خوانده' || role == 'شاکی' || role == 'متهم' || role == 'مشتکی‌عنه' || role == 'محکوم‌علیه' || role == 'محکوم‌له') return role;
    return 'احد از طرفین پرونده';
  }

  String _plaintiffText(Case item, List<CasePerson> people) {
    final fromPeople = _joinPeople(people.where((person) => _clean(person.role) == 'خواهان'));
    if (fromPeople.isNotEmpty) return fromPeople;
    final clientRole = _clean(item.clientRole);
    if (clientRole.contains('خواهان')) return _clean(item.clientName);
    if (clientRole.contains('خوانده')) return _clean(item.opponentName);
    return _clean(item.clientName);
  }

  String _defendantText(Case item, List<CasePerson> people) {
    final fromPeople = _joinPeople(people.where((person) => _clean(person.role) == 'خوانده'));
    if (fromPeople.isNotEmpty) return fromPeople;
    final clientRole = _clean(item.clientRole);
    if (clientRole.contains('خوانده')) return _clean(item.clientName);
    if (clientRole.contains('خواهان')) return _clean(item.opponentName);
    return _clean(item.opponentName);
  }

  bool _isCriminalCase(Case item) => _clean(item.caseType) == 'کیفری';

  String _complainantText(Case item, List<CasePerson> people) {
    final fromPeople = _joinPeople(people.where((person) => _clean(person.role) == 'شاکی'));
    if (fromPeople.isNotEmpty) return fromPeople;
    final clientRole = _clean(item.clientRole);
    if (clientRole.contains('شاکی')) return _clean(item.clientName);
    if (clientRole.contains('متهم') || clientRole.contains('مشتکی')) return _clean(item.opponentName);
    return _clean(item.clientName);
  }

  String _accusedText(Case item, List<CasePerson> people) {
    final fromPeople = _joinPeople(people.where((person) {
      final role = _clean(person.role);
      return role == 'متهم' || role == 'مشتکی‌عنه';
    }));
    if (fromPeople.isNotEmpty) return fromPeople;
    final clientRole = _clean(item.clientRole);
    if (clientRole.contains('متهم') || clientRole.contains('مشتکی')) return _clean(item.clientName);
    if (clientRole.contains('شاکی')) return _clean(item.opponentName);
    return _clean(item.opponentName);
  }

  String _joinPeople(Iterable<CasePerson> people) {
    return people.map((person) => _clean(person.name)).where((name) => name.isNotEmpty).join('، ');
  }

  String _lawyerText(UserProfile? profile) {
    if (profile == null || !profile.useNameInLegalTexts) return '';
    final name = _clean(profile.displayName);
    if (name.isEmpty) return '';
    final legalTitle = _clean(profile.legalTitle);
    if (legalTitle.isEmpty || name.contains(legalTitle)) return name;
    return '$legalTitle $name';
  }

  String _courtText(Case item) {
    final court = _clean(item.court);
    final branch = _clean(item.branch);
    if (court.isEmpty && branch.isEmpty) return '';
    if (court.isEmpty) return branch;
    if (branch.isEmpty || court.contains(branch)) return court;
    return '$court - $branch';
  }

  String _clean(String? value) => value?.trim() ?? '';

  String _normalize(String value) {
    return value
        .trim()
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('آ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ۀ', 'ه')
        .replaceAll('أ', 'ا')
        .replaceAll('رأی', 'رای')
        .replaceAll('رأى', 'رای')
        .replaceAll('رأي', 'رای')
        .replaceAll('رای', 'رای')
        .replaceAll('‌', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeSpacing(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
