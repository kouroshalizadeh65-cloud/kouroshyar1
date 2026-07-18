import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/global_settings_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/session/session_context.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/money_format.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/utils/search_text.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/persian_date_picker.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import 'case_narrative_service.dart';
import 'case_attachment_viewer_screen.dart';
import 'edit_case_screen.dart';


const List<String> _legalHistoryActorRoles = ['خواهان', 'خوانده', 'هر دو طرف'];
const List<String> _criminalHistoryActorRoles = ['شاکی', 'متهم', 'مشتکی‌عنه', 'محکوم‌علیه', 'محکوم‌له', 'هر دو طرف'];


class _AttachmentDraft {
  const _AttachmentDraft({
    required this.path,
    required this.name,
    required this.type,
  });

  final String path;
  final String name;
  final String type;

  _AttachmentDraft copyWith({String? name}) => _AttachmentDraft(
        path: path,
        name: name ?? this.name,
        type: type,
      );
}

String _attachmentKindFromPath(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext == '.pdf') return 'pdf';
  if (['.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'].contains(ext)) return 'image';
  return 'file';
}

String _attachmentKindLabel(String? type) {
  switch ((type ?? '').trim()) {
    case 'pdf':
      return 'PDF';
    case 'image':
      return 'عکس';
    default:
      return 'فایل';
  }
}

bool _hasAttachmentPath(String? path) => (path ?? '').trim().isNotEmpty;

String _attachmentDisplayName(_AttachmentDraft attachment, TextEditingController? controller) {
  final typed = controller?.text.trim() ?? '';
  return typed.isNotEmpty ? typed : attachment.name;
}

Future<void> _shareAttachmentFile(BuildContext context, String? path, String title) async {
  final filePath = path?.trim();
  if (filePath == null || filePath.isEmpty) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('برای این مورد مدرکی ثبت نشده است.')));
    return;
  }
  final file = File(filePath);
  if (!await file.exists()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('فایل اصلی پیدا نشد.')));
    return;
  }
  await Share.shareXFiles(
    [XFile(filePath)],
    text: title,
    subject: title,
    sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
  );
}

String _normalizeHistoryKeyword(String value) {
  return value
      .trim()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('آ', 'ا')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('ؤ', 'و')
      .replaceAll('ۀ', 'ه')
      .replaceAll('‌', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

bool _isJudgmentIssueType(String type) {
  final value = _normalizeHistoryKeyword(type);
  return value.contains('صدور رای');
}

bool _isHearingHistoryType(String type) {
  final value = _normalizeHistoryKeyword(type);
  return value == 'جلسه' || value.contains('جلسه رسیدگی') || value.contains('برگزاری جلسه');
}

bool _isAppealHistoryType(String type) => type.trim().contains('تجدیدنظرخواهی');
bool _isCassationHistoryType(String type) => type.trim().contains('فرجام‌خواهی') || type.trim().contains('فرجام خواهی');
bool _isRetrialHistoryType(String type) => type.trim().contains('اعاده دادرسی');
bool _isExpertObjectionHistoryType(String type) => type.trim().contains('اعتراض به نظریه کارشناسی');

String? _historyActorRoleLabel(String type) {
  final value = _normalizeHistoryKeyword(type);
  if (_isAppealHistoryType(type)) return 'تجدیدنظرخواه';
  if (_isCassationHistoryType(type)) return 'فرجام‌خواه';
  if (_isRetrialHistoryType(type)) return 'متقاضی اعاده دادرسی';
  if (value.contains('واخواهی')) return 'واخواه';
  if (_isExpertObjectionHistoryType(type)) return 'معترض به نظریه کارشناسی';
  if (value.contains('اعتراض به قرار منع تعقیب') || value.contains('اعتراض به قرار موقوفی تعقیب')) return 'معترض';
  if (value.contains('گذشت شاکی') || value.contains('اعلام رضایت')) return 'اعلام‌کننده';
  return null;
}

String _historyDescriptionLabel(String type) {
  if (_isJudgmentIssueType(type)) return 'نوع رای صادره';
  if (_isHearingHistoryType(type)) return 'نوع جلسه رسیدگی';
  return 'توضیحات تکمیلی، اختیاری';
}

String _historyDescriptionHint(String type) {
  if (_isJudgmentIssueType(type)) {
    return 'مثلاً رای بر محکومیت خوانده یا بی‌حقی خواهان';
  }
  if (_isHearingHistoryType(type)) {
    return 'مثلاً جلسه رسیدگی به اصل خواسته، جلسه رسیدگی به اعسار یا استماع گواهی گواهان';
  }
  return 'توضیح کوتاه، در صورت نیاز';
}

bool _isFutureHistoryDate(DateTime value) {
  final today = DateTime.now();
  final selectedDay = DateTime(value.year, value.month, value.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  return selectedDay.isAfter(todayDay);
}

String _caseHistorySubtitle(CaseTimelineEvent event) {
  final type = event.eventType ?? event.title;
  final lines = <String>[
    '${event.eventType ?? 'سابقه'} | ${formatPersianLongDate(event.eventDate)}',
  ];
  final actorLabel = _historyActorRoleLabel(type);
  final actorRole = event.actorRole?.trim() ?? '';
  if (actorLabel != null && actorRole.isNotEmpty) {
    lines.add('$actorLabel: $actorRole');
  }
  final isJudgment = _isJudgmentIssueType(type);
  final isHearing = _isHearingHistoryType(type);
  final decisionSummary = event.decisionSummary?.trim() ?? '';
  final description = event.description?.trim() ?? '';
  if (isJudgment && decisionSummary.isNotEmpty) {
    lines.add('نوع رای صادره: $decisionSummary');
  }
  if (isHearing && description.isNotEmpty) {
    lines.add('نوع جلسه رسیدگی: $description');
  } else if (description.isNotEmpty && (!isJudgment || description != decisionSummary)) {
    lines.add(description);
  }
  if (_hasAttachmentPath(event.attachmentPath)) {
    lines.add('مدرک پیوست: ${event.attachmentName ?? p.basename(event.attachmentPath!)}');
  }
  if (!event.includeInNarrative) {
    lines.add('در شرح پرونده درج نمی‌شود');
  }
  return lines.join('\n');
}

String _courtBranchText(Case item) {
  final court = (item.court ?? '').trim();
  final branch = (item.branch ?? '').trim();
  if (court.isEmpty && branch.isEmpty) return 'ثبت نشده';
  if (court.isEmpty) return branch;
  if (branch.isEmpty || court.contains(branch)) return court;
  return '$court - $branch';
}


bool _isCaseClientPerson(CasePerson person) => (person.notes ?? '').contains('موکل');

String _joinNames(Iterable<CasePerson> people) {
  final names = people.map((p) => p.name.trim()).where((name) => name.isNotEmpty).toList();
  return names.isEmpty ? 'ثبت نشده' : names.join('، ');
}

String _namesByRole(List<CasePerson> people, String role) {
  return _joinNames(people.where((p) => p.role == role));
}

String _clientNamesFromPeople(List<CasePerson> people, Case item) {
  final clients = people.where(_isCaseClientPerson).toList();
  if (clients.isNotEmpty) return _joinNames(clients);
  final fallback = item.clientName?.trim() ?? '';
  return fallback.isEmpty ? 'ثبت نشده' : fallback;
}

String _clientRolesFromPeople(List<CasePerson> people, Case item) {
  final roles = people.where(_isCaseClientPerson).map((p) => p.role.trim()).where((r) => r.isNotEmpty).toSet().toList();
  if (roles.isNotEmpty) return roles.join('، ');
  final fallback = item.clientRole?.trim() ?? '';
  return fallback.isEmpty ? 'ثبت نشده' : fallback;
}

String _legalRoleName(Case item, String targetRole) {
  final clientRole = item.clientRole?.trim() ?? '';
  final client = item.clientName?.trim() ?? '';
  final opponent = item.opponentName?.trim() ?? '';
  if (targetRole == 'خواهان') {
    if (clientRole.contains('خواهان') && client.isNotEmpty) return client;
    if (clientRole.contains('خوانده') && opponent.isNotEmpty) return opponent;
  }
  if (targetRole == 'خوانده') {
    if (clientRole.contains('خوانده') && client.isNotEmpty) return client;
    if (clientRole.contains('خواهان') && opponent.isNotEmpty) return opponent;
  }
  return 'ثبت نشده';
}

String _criminalRoleName(Case item, String targetRole) {
  final clientRole = item.clientRole?.trim() ?? '';
  final client = item.clientName?.trim() ?? '';
  final opponent = item.opponentName?.trim() ?? '';
  if (targetRole == 'شاکی') {
    if (clientRole.contains('شاکی') && client.isNotEmpty) return client;
    if (clientRole.contains('متهم') && opponent.isNotEmpty) return opponent;
  }
  if (targetRole == 'متهم') {
    if (clientRole.contains('متهم') && client.isNotEmpty) return client;
    if (clientRole.contains('شاکی') && opponent.isNotEmpty) return opponent;
  }
  return 'ثبت نشده';
}

String _caseSummaryText(Case item, List<CasePerson> people) {
  final type = item.caseType == 'کیفری' ? 'کیفری' : 'حقوقی';
  final lines = <String>['نوع پرونده: $type'];
  if (type == 'حقوقی') {
    final plaintiffs = _namesByRole(people, 'خواهان');
    final defendants = _namesByRole(people, 'خوانده');
    lines.add('خواهان: ${plaintiffs == 'ثبت نشده' ? _legalRoleName(item, 'خواهان') : plaintiffs}');
    lines.add('خوانده: ${defendants == 'ثبت نشده' ? _legalRoleName(item, 'خوانده') : defendants}');
    lines.add('موکل من: ${_clientNamesFromPeople(people, item)}');
    lines.add('سمت موکل: ${_clientRolesFromPeople(people, item)}');
    lines.add('خواسته: ${item.subject ?? 'ثبت نشده'}');
  } else {
    final complainants = _namesByRole(people, 'شاکی');
    final accused = _namesByRole(people, 'متهم');
    lines.add('شاکی: ${complainants == 'ثبت نشده' ? _criminalRoleName(item, 'شاکی') : complainants}');
    lines.add('متهم: ${accused == 'ثبت نشده' ? _criminalRoleName(item, 'متهم') : accused}');
    lines.add('موکل من: ${_clientNamesFromPeople(people, item)}');
    lines.add('سمت موکل: ${_clientRolesFromPeople(people, item)}');
    lines.add('اتهام: ${item.subject ?? 'ثبت نشده'}');
  }
  lines.addAll([
    'شعبه و مرجع رسیدگی: ${_courtBranchText(item)}',
    'قاضی: ${item.judge ?? 'ثبت نشده'}',
    'شماره پرونده: ${item.caseNumber ?? 'ثبت نشده'}',
    'شماره بایگانی: ${item.archiveNumber ?? 'ثبت نشده'}',
    'مرحله رسیدگی: ${item.stage ?? 'ثبت نشده'}',
    'سمت موکل در این مرحله: ${item.currentRole ?? 'ثبت نشده'}',
    'وضعیت فعلی پرونده: ${item.status}',
  ]);
  final nextAction = item.nextAction?.trim() ?? '';
  if (nextAction.isNotEmpty) lines.add('اقدام بعدی: $nextAction');
  return lines.join('\n');
}

String _safeCaseSummaryText(Case item, List<CasePerson> people) {
  try {
    return _caseSummaryText(item, people);
  } catch (_) {
    final type = item.caseType == 'کیفری' ? 'کیفری' : 'حقوقی';
    final subjectLabel = type == 'کیفری' ? 'اتهام' : 'خواسته';
    final subject = (item.subject ?? '').trim();
    return [
      'نوع پرونده: $type',
      if (subject.isNotEmpty) '$subjectLabel: $subject',
      'وضعیت فعلی پرونده: ${item.status}',
    ].join('\n');
  }
}

class CaseDetailScreen extends ConsumerWidget {
  final Case item;

  const CaseDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    SessionContext.setLastCase(id: item.id, title: item.title);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          const GlobalSettingsButton(),
          IconButton(
            tooltip: 'جستجوی همین پرونده',
            icon: const Icon(Icons.search),
            onPressed: () => _showCaseSearch(context, db),
          ),
          PopupMenuButton<String>(
            tooltip: 'عملیات پرونده',
            onSelected: (value) {
              if (value == 'edit') {
                _editCase(context, db);
              } else if (value == 'finish') {
                _finishCase(context, db);
              } else if (value == 'delete') {
                _deleteCase(context, db);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('ویرایش پرونده')),
              PopupMenuItem(value: 'finish', child: Text('اتمام روند / غیرفعال')),
              PopupMenuItem(value: 'delete', child: Text('حذف پرونده')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 48 + MediaQuery.of(context).padding.bottom),
        children: [
          _CaseInfoSection(
            item: item,
            db: db,
            onEditCase: () => _editCase(context, db),
            onAddPerson: () => _showCasePersonDialog(context, db),
            onEditPerson: (person) => _showCasePersonDialog(context, db, person: person),
            onDeletePerson: (person) => _deleteCasePerson(context, db, person),
          ),
          _CaseFinanceSection(
            item: item,
            db: db,
            onAdd: () => _showCaseFinanceDialog(context, db),
            onEdit: (finance) => _showCaseFinanceDialog(context, db, item: finance),
            onDelete: (finance) => _deleteCaseFinance(context, db, finance),
          ),
          _CaseTasksSection(
            item: item,
            db: db,
            onAdd: () => _addTask(context, db),
            onEdit: (task) => _editTask(context, db, task),
            onDelete: (task) => _deleteTask(context, db, task),
          ),
          _CaseHistorySection(
            item: item,
            db: db,
            onAdd: () => _addTimelineEvent(context, db),
            onEdit: (event) => _editTimelineEvent(context, db, event),
            onDelete: (event) => _deleteTimelineEvent(context, db, event),
          ),
          _CaseNarrativeSection(
            item: item,
            db: db,
          ),
        ],
      ),
    );
  }

  void _notify(BuildContext context, String message) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(milliseconds: 1200)),
    );
  }

  Future<void> _showCaseSearch(BuildContext context, AppDatabase db) async {
    final controller = TextEditingController();
    var results = <Widget>[];

    Future<void> runSearch(StateSetter setState) async {
      final query = normalizeSearchText(controller.text);
      if (query.isEmpty) {
        setState(() => results = const [ListTile(title: Text('عبارت جستجو را وارد کنید.'))]);
        return;
      }
      final people = await (db.select(db.casePeople)..where((p) => p.caseId.equals(item.id))).get();
      final finances = (await db.select(db.financeItems).get()).where((f) => f.caseId == item.id).toList();
      final events = await (db.select(db.caseTimelineEvents)..where((e) => e.caseId.equals(item.id))).get();
      final tasks = await (db.select(db.tasks)..where((t) => t.caseId.equals(item.id))).get();
      final matches = <Widget>[];

      bool contains(String? text) => searchTextContains(text, query);

      if (contains(item.title) || contains(item.subject) || contains(item.caseNumber) || contains(item.archiveNumber) || contains(item.stage) || contains(item.status)) {
        matches.add(ListTile(leading: const Icon(Icons.folder_open), title: const Text('مشخصات پرونده'), subtitle: Text(_caseSummaryText(item, people))));
      }
      for (final p in people) {
        if (contains(p.name) || contains(p.role) || contains(p.notes) || contains(p.phone)) {
          matches.add(ListTile(leading: const Icon(Icons.person), title: Text(p.name), subtitle: Text('${p.role}${(p.notes ?? '').isEmpty ? '' : ' | ${p.notes}'}')));
        }
      }
      for (final f in finances) {
        if (contains(f.title) || contains(f.type) || contains(f.category) || contains(f.notes) || contains(f.attachmentName)) {
          matches.add(ListTile(
            leading: Icon(_hasAttachmentPath(f.attachmentPath) ? Icons.receipt_long : Icons.account_balance_wallet),
            title: Text(f.title),
            subtitle: Text('${f.type} | ${formatMoney(f.amount)} تومان${_hasAttachmentPath(f.attachmentPath) ? '\nمدرک مالی: ${f.attachmentName ?? p.basename(f.attachmentPath!)}' : ''}'),
            onTap: _hasAttachmentPath(f.attachmentPath)
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseAttachmentViewerScreen(filePath: f.attachmentPath!, title: f.attachmentName ?? f.title, fileType: f.attachmentType)))
                : null,
          ));
        }
      }
      for (final e in events) {
        if (contains(e.title) || contains(e.eventType) || contains(e.description) || contains(e.attachmentName)) {
          matches.add(ListTile(
            leading: Icon(_hasAttachmentPath(e.attachmentPath) ? Icons.attach_file : Icons.history),
            title: Text(e.title),
            subtitle: Text('${e.eventType ?? 'تاریخچه'}${_hasAttachmentPath(e.attachmentPath) ? '\nمدرک پیوست: ${e.attachmentName ?? p.basename(e.attachmentPath!)}' : ''}'),
            onTap: _hasAttachmentPath(e.attachmentPath)
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseAttachmentViewerScreen(filePath: e.attachmentPath!, title: e.attachmentName ?? e.title, fileType: e.attachmentType)))
                : null,
          ));
        }
      }
      for (final t in tasks) {
        if (contains(t.title) || contains(t.priority)) {
          matches.add(ListTile(leading: const Icon(Icons.task_alt), title: Text(t.title), subtitle: Text(t.isDone ? 'انجام‌شده' : 'انجام‌نشده')));
        }
      }
      setState(() => results = matches.isEmpty ? const [ListTile(title: Text('نتیجه‌ای در همین پرونده پیدا نشد.'))] : matches);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('جستجو در پرونده ${item.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    CompactSearchField(
                      controller: controller,
                      autofocus: true,
                      hintText: 'جستجو در مشخصات، مالی، تاریخچه و پیوست‌ها...',
                      onChanged: (_) => runSearch(setState),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: ListView(children: results)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editCase(BuildContext context, AppDatabase db) async {
    final updated = await Navigator.push<Case>(
      context,
      MaterialPageRoute(builder: (_) => EditCaseScreen(db: db, item: item)),
    );
    if (updated != null && context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CaseDetailScreen(item: updated)),
      );
    }
  }

  Future<void> _finishCase(BuildContext context, AppDatabase db) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اتمام روند پرونده'),
        content: Text('پرونده «${item.title}» از حالت فعال خارج شود؟ اطلاعات پرونده حذف نمی‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('اتمام روند')),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = item.copyWith(status: 'غیرفعال');
    await db.update(db.cases).replace(updated);
    if (context.mounted) {
      _notify(context, 'پرونده غیرفعال شد.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CaseDetailScreen(item: updated)),
      );
    }
  }

  Future<void> _deleteCase(BuildContext context, AppDatabase db) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف پرونده'),
        content: Text('آیا از حذف پرونده «${item.title}» مطمئن هستید؟ تاریخچه، اشخاص، پیوست‌های ثبت‌شده، کارها، مهلت‌ها، مالی، پیش‌نویس‌ها و تجربه‌های متصل به این پرونده نیز حذف می‌شوند. این عملیات قابل بازگشت نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف قطعی'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.deleteCaseCascade(item.id);
    if (context.mounted) {
      Navigator.pop(context);
    }
  }


  Future<DateTime?> _askCaseDate(BuildContext context, DateTime current, String title) {
    return pickPersianDate(context, initialDate: current, title: title);
  }

  Future<TimeOfDay?> _askCaseTime(BuildContext context, TimeOfDay current) {
    return showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'انتخاب ساعت',
      cancelText: 'لغو',
      confirmText: 'تأیید',
      hourLabelText: 'ساعت',
      minuteLabelText: 'دقیقه',
    );
  }

  List<String> _legalDeadlineOptions() => const [
        'مهلت ثبت دادخواست',
        'مهلت رفع نقص',
        'مهلت پرداخت هزینه دادرسی',
        'مهلت ملاحظه نظریه کارشناسی',
        'مهلت اعتراض به نظریه کارشناسی',
        'مهلت اعتراض به رای / تجدیدنظرخواهی',
        'مهلت واخواهی',
        'مهلت فرجام‌خواهی',
        'مهلت اعاده دادرسی',
        'مهلت اعتراض ثالث',
        'مهلت اعتراض به اجرائیه',
        'مهلت پرداخت محکوم‌به',
        'مهلت اجرای تعهد',
        'مهلت ارائه لایحه',
        'مهلت حضور / معرفی شهود',
        'سایر / ثبت دستی',
      ];

  List<String> _sessionTypeOptions() {
    if (item.caseType == 'کیفری') {
      return const [
        'جلسه رسیدگی کیفری',
        'رسیدگی به اتهام',
        'تفهیم اتهام',
        'مواجهه حضوری',
        'استماع اظهارات شاکی',
        'استماع دفاعیات متهم',
        'استماع شهادت شهود',
        'رسیدگی واخواهی کیفری',
        'رسیدگی تجدیدنظر کیفری',
        'رسیدگی اجرای احکام کیفری',
        'جلسه صلح و سازش',
        'سایر / ثبت دستی',
      ];
    }
    return const [
      'رسیدگی اصل خواسته',
      'رسیدگی اعسار',
      'رسیدگی دعوای تقابل',
      'رسیدگی تأمین خواسته',
      'رسیدگی دستور موقت',
      'رسیدگی واخواهی',
      'رسیدگی تجدیدنظر',
      'استماع گواهی گواهان',
      'اخذ توضیح از طرفین',
      'رسیدگی به اعتراض به نظریه کارشناسی',
      'رسیدگی اجرای احکام',
      'جلسه سازش / مصالحه',
      'سایر / ثبت دستی',
    ];
  }

  List<String> _historyTypeOptions() => item.caseType == 'کیفری' ? _criminalHistoryTypeOptions() : _legalHistoryTypeOptions();

  List<String> _legalHistoryTypeOptions() => const [
        'تاریخ ثبت دادخواست',
        'تاریخ ارجاع به شعبه',
        'تاریخ تعیین وقت رسیدگی',
        'تاریخ ابلاغ وقت رسیدگی',
        'تاریخ جلسه رسیدگی',
        'تاریخ تقدیم لایحه',
        'تاریخ اخذ توضیح',
        'تاریخ استعلام',
        'تاریخ وصول پاسخ استعلام',
        'تاریخ معاینه محل',
        'تاریخ تحقیق محلی',
        'تاریخ ارجاع به کارشناسی',
        'تاریخ تعیین کارشناس',
        'تاریخ پرداخت دستمزد کارشناس',
        'تاریخ وصول نظریه کارشناسی',
        'تاریخ اعتراض به نظریه کارشناسی',
        'تاریخ ارجاع به هیأت کارشناسی',
        'تاریخ وصول نظریه هیأت کارشناسی',
        'تاریخ صدور قرار',
        'تاریخ صدور قرار کارشناسی',
        'تاریخ صدور قرار تأمین خواسته',
        'تاریخ صدور دستور موقت',
        'تاریخ ختم رسیدگی',
        'تاریخ صدور رای',
        'تاریخ ابلاغ رای',
        'تاریخ واخواهی',
        'تاریخ تجدیدنظرخواهی',
        'تاریخ فرجام‌خواهی',
        'تاریخ اعاده دادرسی',
        'تاریخ اعتراض ثالث',
        'تاریخ ارجاع به دادگاه تجدیدنظر',
        'تاریخ جلسه تجدیدنظر',
        'تاریخ صدور رای تجدیدنظر',
        'تاریخ ابلاغ رای تجدیدنظر',
        'تاریخ قطعیت رای',
        'تاریخ ارسال به دیوان عالی کشور',
        'تاریخ صدور رای دیوان عالی کشور',
        'تاریخ صدور اجراییه',
        'تاریخ ابلاغ اجراییه',
        'تاریخ تشکیل پرونده اجرایی',
        'تاریخ توقیف مال',
        'تاریخ مزایده',
        'تاریخ پرداخت محکوم‌به',
        'تاریخ مختومه شدن اجرا',
        'تاریخ مختومه شدن پرونده',
        'ثبت مورد جدید',
      ];

  List<String> _criminalHistoryTypeOptions() => const [
        'تاریخ ثبت شکواییه',
        'تاریخ ارجاع شکواییه به دادسرا',
        'تاریخ ارجاع پرونده به شعبه دادیاری / بازپرسی',
        'تاریخ ارجاع به کلانتری / آگاهی / ضابط',
        'تاریخ وصول گزارش ضابط',
        'تاریخ تکمیل تحقیقات ضابط',
        'تاریخ ارسال پرونده از ضابط به دادسرا',
        'تاریخ احضار شاکی',
        'تاریخ اخذ اظهارات شاکی',
        'تاریخ احضار متهم',
        'تاریخ جلب متهم',
        'تاریخ تفهیم اتهام',
        'تاریخ اخذ دفاعیات متهم',
        'تاریخ اخذ آخرین دفاع',
        'تاریخ استماع شهادت شهود',
        'تاریخ تحقیق از گواه',
        'تاریخ مواجهه حضوری',
        'تاریخ معاینه محل',
        'تاریخ تحقیق محلی',
        'تاریخ ارجاع به کارشناسی',
        'تاریخ ابلاغ قرار کارشناسی',
        'تاریخ ارائه نظریه کارشناسی',
        'تاریخ اعتراض به نظریه کارشناسی',
        'تاریخ ارجاع به هیات کارشناسی',
        'تاریخ وصول نظریه هیات کارشناسی',
        'تاریخ صدور قرار تامین کیفری',
        'تاریخ ابلاغ قرار تامین کیفری',
        'تاریخ قبولی کفالت',
        'تاریخ تودیع وثیقه',
        'تاریخ بازداشت متهم',
        'تاریخ آزادی متهم',
        'تاریخ تبدیل قرار تامین',
        'تاریخ تشدید قرار تامین',
        'تاریخ فک قرار تامین',
        'تاریخ صدور قرار نظارت قضایی',
        'تاریخ لغو قرار نظارت قضایی',
        'تاریخ اعلام ختم تحقیقات',
        'تاریخ موافقت دادستان با قرار جلب به دادرسی',
        'تاریخ صدور کیفرخواست',
        'تاریخ ارسال کیفرخواست به دادگاه',
        'تاریخ ابلاغ قرار منع تعقیب',
        'تاریخ اعتراض به قرار منع تعقیب',
        'تاریخ ارسال اعتراض به دادگاه',
        'تاریخ نقض قرار منع تعقیب',
        'تاریخ تایید قرار منع تعقیب',
        'تاریخ صدور قرار موقوفی تعقیب',
        'تاریخ ابلاغ قرار موقوفی تعقیب',
        'تاریخ اعتراض به قرار موقوفی تعقیب',
        'تاریخ ارسال پرونده به مرجع صالح',
        'تاریخ ارجاع پرونده به دادگاه کیفری',
        'تاریخ ابلاغ وقت رسیدگی',
        'تاریخ جلسه رسیدگی',
        'تاریخ استماع اظهارات شاکی',
        'تاریخ دفاع متهم',
        'تاریخ استماع شهادت شهود در دادگاه',
        'تاریخ اخذ آخرین دفاع در دادگاه',
        'تاریخ اعلام ختم رسیدگی',
        'تاریخ صدور رای',
        'تاریخ ابلاغ رای',
        'تاریخ قطعیت رای',
        'تاریخ اعاده پرونده به دادسرا برای تکمیل تحقیقات',
        'تاریخ واخواهی',
        'تاریخ تجدیدنظرخواهی',
        'تاریخ ارسال پرونده به دادگاه تجدیدنظر',
        'تاریخ ارجاع به شعبه تجدیدنظر',
        'تاریخ جلسه تجدیدنظر',
        'تاریخ ابلاغ رای تجدیدنظر',
        'تاریخ فرجام‌خواهی',
        'تاریخ ارسال پرونده به دیوان عالی کشور',
        'تاریخ اعاده دادرسی',
        'تاریخ پذیرش اعاده دادرسی',
        'تاریخ رد اعاده دادرسی',
        'تاریخ ارسال پرونده به اجرای احکام',
        'تاریخ تشکیل پرونده اجرای احکام',
        'تاریخ ابلاغ احضاریه اجرای حکم',
        'تاریخ شروع اجرای حکم',
        'تاریخ اجرای حکم',
        'تاریخ تقسیط جزای نقدی',
        'تاریخ معرفی محکوم‌علیه به زندان',
        'تاریخ آزادی محکوم‌علیه',
        'تاریخ تعلیق اجرای مجازات',
        'تاریخ لغو تعلیق اجرای مجازات',
        'تاریخ پایان اجرای حکم',
        'تاریخ مختومه شدن پرونده اجرای احکام',
        'تاریخ گذشت شاکی',
        'تاریخ اعلام رضایت',
        'تاریخ ثبت سازش',
        'تاریخ صدور قرار ترک تعقیب',
        'تاریخ تعلیق تعقیب',
        'تاریخ بایگانی پرونده',
        'تاریخ رفع اثر از دستور جلب',
        'ثبت مورد جدید',
      ];

  List<String> _historyActorRolesForCase() => item.caseType == 'کیفری' ? _criminalHistoryActorRoles : _legalHistoryActorRoles;

  Widget _searchablePresetField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required List<String> options,
    required StateSetter setState,
  }) {
    final query = controller.text.trim();
    final exact = options.any((option) => option == query);
    final filtered = exact || query.isEmpty ? List<String>.of(options) : options.where((option) => option.contains(query)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (query.isNotEmpty || filtered.isNotEmpty) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...filtered.map((option) => ListTile(
                        dense: true,
                        title: Text(option),
                        trailing: option == query ? const Icon(Icons.check) : null,
                        onTap: () => setState(() => controller.text = (option == 'سایر / ثبت دستی' || option == 'ثبت مورد جدید') ? '' : option),
                      )),
                  if (query.isNotEmpty && !exact)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add),
                      title: Text('ثبت «$query» به‌عنوان مورد جدید'),
                      onTap: () => setState(() => controller.text = query),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _addTask(BuildContext context, AppDatabase db) {
    final titleController = TextEditingController();
    final presetController = TextEditingController();
    final notesController = TextEditingController();
    String itemType = 'کار / اقدام';
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    String priority = 'متوسط';
    const priorities = ['کم', 'متوسط', 'زیاد', 'فوری'];
    const itemTypes = ['کار / اقدام', 'مهلت قانونی', 'جلسه رسیدگی'];

    List<String> currentPresets() {
      if (itemType == 'مهلت قانونی') return _legalDeadlineOptions();
      if (itemType == 'جلسه رسیدگی') return _sessionTypeOptions();
      return const <String>[];
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          final presets = currentPresets();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('افزودن کار، مهلت یا جلسه پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: itemType,
                      decoration: const InputDecoration(labelText: 'نوع مورد', border: OutlineInputBorder()),
                      items: itemTypes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                      onChanged: (value) => setState(() {
                        itemType = value ?? itemType;
                        titleController.clear();
                        // این فیلد نباید با یک مقدار واقعی پر شود؛ در غیر این صورت همان مقدار
                        // مثل جستجو عمل می‌کند و بقیه گزینه‌ها را مخفی می‌کند.
                        presetController.clear();
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (itemType == 'کار / اقدام') ...[
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'عنوان کار / اقدام', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: priority,
                        decoration: const InputDecoration(labelText: 'اولویت', border: OutlineInputBorder()),
                        items: priorities.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                        onChanged: (value) => setState(() => priority = value ?? priority),
                      ),
                    ] else if (itemType == 'مهلت قانونی') ...[
                      _searchablePresetField(
                        controller: presetController,
                        label: 'نوع مهلت قانونی',
                        hint: 'مثلاً مهلت اعتراض به رای',
                        options: presets,
                        setState: setState,
                      ),
                    ] else ...[
                      _searchablePresetField(
                        controller: presetController,
                        label: item.caseType == 'کیفری' ? 'نوع جلسه کیفری' : 'نوع جلسه حقوقی',
                        hint: item.caseType == 'کیفری' ? 'مثلاً استماع دفاعیات متهم' : 'مثلاً رسیدگی اصل خواسته',
                        options: presets,
                        setState: setState,
                      ),
                    ],
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(itemType == 'مهلت قانونی' ? 'تاریخ پایان مهلت' : itemType == 'جلسه رسیدگی' ? 'تاریخ جلسه' : 'تاریخ کار'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, 'انتخاب تاریخ شمسی');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    if (itemType == 'جلسه رسیدگی')
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ساعت جلسه'),
                        subtitle: Text(toPersianDigits("${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}")),
                        trailing: const Icon(Icons.schedule),
                        onTap: () async {
                          final picked = await _askCaseTime(sheetContext, selectedTime);
                          if (picked != null) setState(() => selectedTime = picked);
                        },
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: InputDecoration(
                        labelText: itemType == 'کار / اقدام' ? 'توضیحات اختیاری' : itemType == 'مهلت قانونی' ? 'توضیح مهلت، اختیاری' : 'توضیح جلسه، اختیاری',
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final rootMessenger = ScaffoldMessenger.maybeOf(context);
                              rootMessenger?.clearSnackBars();
                              final notes = notesController.text.trim();
                              if (itemType == 'کار / اقدام') {
                                final title = titleController.text.trim();
                                if (title.isEmpty) {
                                  _notify(sheetContext, 'عنوان کار را وارد کنید.');
                                  return;
                                }
                                await db.into(db.tasks).insert(
                                      TasksCompanion.insert(
                                        title: title,
                                        caseId: Value(item.id),
                                        priority: Value(priority),
                                        dueDate: Value(selectedDate),
                                      ),
                                    );
                              } else if (itemType == 'مهلت قانونی') {
                                final title = presetController.text.trim();
                                if (title.isEmpty) {
                                  _notify(sheetContext, 'نوع مهلت قانونی را انتخاب یا وارد کنید.');
                                  return;
                                }
                                await db.into(db.deadlines).insert(
                                      DeadlinesCompanion.insert(
                                        caseId: Value(item.id),
                                        title: title,
                                        deadlineType: Value(title),
                                        dueDate: selectedDate,
                                        priority: const Value('خیلی زیاد'),
                                        notes: Value(notes),
                                      ),
                                    );
                              } else {
                                final type = presetController.text.trim();
                                if (type.isEmpty) {
                                  _notify(sheetContext, 'نوع جلسه رسیدگی را انتخاب یا وارد کنید.');
                                  return;
                                }
                                final dateTime = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  selectedTime.hour,
                                  selectedTime.minute,
                                );
                                await db.into(db.caseTimelineEvents).insert(
                                      CaseTimelineEventsCompanion.insert(
                                        caseId: item.id,
                                        title: type,
                                        eventType: const Value('جلسه'),
                                        description: Value(notes.isEmpty ? type : notes),
                                        eventDate: Value(dateTime),
                                        includeInNarrative: const Value(false),
                                      ),
                                    );
                              }
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) _notify(context, 'ثبت شد');
                            },
                            child: const Text('ثبت'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }


  void _editTask(BuildContext context, AppDatabase db, Task task) {
    final controller = TextEditingController(text: task.title);
    DateTime selectedDate = task.dueDate ?? DateTime.now();
    String priority = task.priority;
    const priorities = ['کم', 'متوسط', 'زیاد', 'فوری'];
    if (!priorities.contains(priority)) priority = 'متوسط';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ویرایش کار پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'عنوان کار', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: priority,
                      items: priorities.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => priority = v ?? priority),
                      decoration: const InputDecoration(labelText: 'اولویت', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ کار'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, 'تاریخ شمسی کار');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final title = controller.text.trim();
                              if (title.isEmpty) {
                                _notify(context, 'عنوان کار را وارد کنید.');
                                return;
                              }
                              final updatedTask = task.copyWith(
                                title: title,
                                priority: priority,
                                dueDate: Value(selectedDate),
                              );
                              await db.setTaskDone(updatedTask, updatedTask.isDone);
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) _notify(context, 'تغییرات ذخیره شد');
                            },
                            child: const Text('ذخیره'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteTask(BuildContext context, AppDatabase db, Task task) async {
    final confirmed = await _confirmDelete(context, 'حذف کار', 'آیا این کار از پرونده حذف شود؟');
    if (confirmed != true) return;
    await db.deleteTaskWithTimeline(task.id);
    if (context.mounted) {
      _notify(context, 'حذف شد');
    }
  }

  void _addTimelineEvent(BuildContext context, AppDatabase db) {
    final eventTypeController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? actorRole;
    bool includeInNarrative = true;
    _AttachmentDraft? attachment;
    final attachmentNameController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          final currentEventType = eventTypeController.text.trim();
          final actorRoleLabel = _historyActorRoleLabel(currentEventType);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('افزودن به تاریخچه پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _searchablePresetField(
                      controller: eventTypeController,
                      label: 'نوع ثبت در تاریخچه',
                      hint: 'انتخاب یا جستجوی نوع سابقه',
                      options: _historyTypeOptions(),
                      setState: setState,
                    ),
                    const SizedBox(height: 12),
                    if (actorRoleLabel != null) ...[
                      DropdownButtonFormField<String>(
                        value: actorRole,
                        decoration: InputDecoration(labelText: actorRoleLabel, border: const OutlineInputBorder()),
                        items: _historyActorRolesForCase().map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
                        onChanged: (value) => setState(() => actorRole = value),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ ثبت در تاریخچه'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, 'تاریخ شمسی سابقه');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: _historyDescriptionLabel(currentEventType),
                        hintText: _historyDescriptionHint(currentEventType),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: includeInNarrative,
                      title: const Text('ثبت در شرح پرونده'),
                      subtitle: const Text('اگر روشن باشد، این مورد در تولید شرح پرونده استفاده می‌شود.'),
                      onChanged: (value) => setState(() => includeInNarrative = value),
                    ),
                    const SizedBox(height: 8),
                    _AttachmentPickerCard(
                      title: 'مدرک این سابقه',
                      attachmentName: attachment?.name,
                      attachmentType: attachment?.type,
                      nameController: attachmentNameController,
                      onPickFile: () async {
                        final picked = await _pickAttachmentFile(sheetContext);
                        if (picked != null) {
                          setState(() {
                            attachment = picked;
                            attachmentNameController.text = picked.name;
                          });
                        }
                      },
                      onCamera: () async {
                        final picked = await _captureAttachment(sheetContext);
                        if (picked != null) {
                          setState(() {
                            attachment = picked;
                            attachmentNameController.text = picked.name;
                          });
                        }
                      },
                      onRemove: attachment == null ? null : () => setState(() {
                        attachment = null;
                        attachmentNameController.clear();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final eventType = eventTypeController.text.trim().isEmpty ? 'ثبت دستی' : eventTypeController.text.trim();
                              final description = descriptionController.text.trim();
                              final roleLabel = _historyActorRoleLabel(eventType);
                              final selectedActorRole = roleLabel == null ? null : actorRole;
                              if (_isJudgmentIssueType(eventType) && description.isEmpty) {
                                _notify(sheetContext, 'نوع رای صادره را وارد کنید.');
                                return;
                              }
                              if (_isHearingHistoryType(eventType) && description.isEmpty) {
                                _notify(sheetContext, 'نوع جلسه رسیدگی را وارد کنید.');
                                return;
                              }
                              if (roleLabel != null && (selectedActorRole == null || selectedActorRole.trim().isEmpty)) {
                                _notify(sheetContext, '$roleLabel را انتخاب کنید.');
                                return;
                              }
                              if (_isFutureHistoryDate(selectedDate)) {
                                _notify(sheetContext, 'تاریخچه پرونده نمی‌تواند مربوط به آینده باشد. آینده را در کارها، مهلت‌ها یا جلسات ثبت کنید.');
                                return;
                              }
                              await db.into(db.caseTimelineEvents).insert(
                                    CaseTimelineEventsCompanion.insert(
                                      caseId: item.id,
                                      title: eventType,
                                      eventType: Value(eventType),
                                      description: Value(description),
                                      eventDate: Value(selectedDate),
                                      decisionSummary: Value<String?>(_isJudgmentIssueType(eventType) ? description : null),
                                      actorRole: Value<String?>(selectedActorRole),
                                      attachmentPath: Value<String?>(attachment?.path),
                                      attachmentName: Value<String?>(attachment == null ? null : _attachmentDisplayName(attachment!, attachmentNameController)),
                                      attachmentType: Value<String?>(attachment?.type),
                                      includeInNarrative: Value(includeInNarrative),
                                    ),
                                  );
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) _notify(context, 'ثبت شد');
                            },
                            child: const Text('ثبت'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }


  void _editTimelineEvent(BuildContext context, AppDatabase db, CaseTimelineEvent event) {
    if ((event.sourceType ?? '').trim().isNotEmpty && event.sourceId != null) {
      _notify(context, 'این سابقه خودکار است. برای ویرایش آن، کار، مهلت یا جلسه مربوط را ویرایش کنید.');
      return;
    }
    final initialEventType = event.eventType ?? event.title;
    final eventTypeController = TextEditingController(text: initialEventType);
    final descriptionController = TextEditingController(
      text: _isJudgmentIssueType(initialEventType) ? (event.decisionSummary ?? event.description ?? '') : (event.description ?? ''),
    );
    DateTime selectedDate = event.eventDate;
    String? actorRole = event.actorRole;
    bool includeInNarrative = event.includeInNarrative;
    _AttachmentDraft? attachment = _hasAttachmentPath(event.attachmentPath)
        ? _AttachmentDraft(
            path: event.attachmentPath!,
            name: event.attachmentName ?? p.basename(event.attachmentPath!),
            type: event.attachmentType ?? _attachmentKindFromPath(event.attachmentPath!),
          )
        : null;
    final attachmentNameController = TextEditingController(text: attachment?.name ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          final currentEventType = eventTypeController.text.trim();
          final actorRoleLabel = _historyActorRoleLabel(currentEventType);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ویرایش تاریخچه پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _searchablePresetField(
                      controller: eventTypeController,
                      label: 'نوع ثبت در تاریخچه',
                      hint: 'انتخاب یا جستجوی نوع سابقه',
                      options: _historyTypeOptions(),
                      setState: setState,
                    ),
                    const SizedBox(height: 12),
                    if (actorRoleLabel != null) ...[
                      DropdownButtonFormField<String>(
                        value: _historyActorRolesForCase().contains(actorRole) ? actorRole : null,
                        decoration: InputDecoration(labelText: actorRoleLabel, border: const OutlineInputBorder()),
                        items: _historyActorRolesForCase().map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
                        onChanged: (value) => setState(() => actorRole = value),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ ثبت در تاریخچه'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, 'تاریخ شمسی سابقه');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: _historyDescriptionLabel(currentEventType),
                        hintText: _historyDescriptionHint(currentEventType),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: includeInNarrative,
                      title: const Text('ثبت در شرح پرونده'),
                      subtitle: const Text('اگر روشن باشد، این مورد در تولید شرح پرونده استفاده می‌شود.'),
                      onChanged: (value) => setState(() => includeInNarrative = value),
                    ),
                    const SizedBox(height: 8),
                    _AttachmentPickerCard(
                      title: 'مدرک این سابقه',
                      attachmentName: attachment?.name,
                      attachmentType: attachment?.type,
                      nameController: attachmentNameController,
                      onPickFile: () async {
                        final picked = await _pickAttachmentFile(sheetContext);
                        if (picked != null) {
                          setState(() {
                            attachment = picked;
                            attachmentNameController.text = picked.name;
                          });
                        }
                      },
                      onCamera: () async {
                        final picked = await _captureAttachment(sheetContext);
                        if (picked != null) {
                          setState(() {
                            attachment = picked;
                            attachmentNameController.text = picked.name;
                          });
                        }
                      },
                      onRemove: attachment == null ? null : () => setState(() {
                        attachment = null;
                        attachmentNameController.clear();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final eventType = eventTypeController.text.trim().isEmpty ? 'ثبت دستی' : eventTypeController.text.trim();
                              final description = descriptionController.text.trim();
                              final roleLabel = _historyActorRoleLabel(eventType);
                              final selectedActorRole = roleLabel == null ? null : actorRole;
                              if (_isJudgmentIssueType(eventType) && description.isEmpty) {
                                _notify(sheetContext, 'نوع رای صادره را وارد کنید.');
                                return;
                              }
                              if (_isHearingHistoryType(eventType) && description.isEmpty) {
                                _notify(sheetContext, 'نوع جلسه رسیدگی را وارد کنید.');
                                return;
                              }
                              if (roleLabel != null && (selectedActorRole == null || selectedActorRole.trim().isEmpty)) {
                                _notify(sheetContext, '$roleLabel را انتخاب کنید.');
                                return;
                              }
                              if (_isFutureHistoryDate(selectedDate)) {
                                _notify(sheetContext, 'تاریخچه پرونده نمی‌تواند مربوط به آینده باشد. آینده را در کارها، مهلت‌ها یا جلسات ثبت کنید.');
                                return;
                              }
                              final oldAttachmentPath = event.attachmentPath;
                              final attachmentChanged = (oldAttachmentPath ?? '') != (attachment?.path ?? '');
                              await db.update(db.caseTimelineEvents).replace(
                                    event.copyWith(
                                      title: eventType,
                                      eventType: Value(eventType),
                                      description: Value(description),
                                      eventDate: selectedDate,
                                      decisionSummary: Value<String?>(_isJudgmentIssueType(eventType) ? description : null),
                                      actorRole: Value<String?>(selectedActorRole),
                                      attachmentPath: Value<String?>(attachment?.path),
                                      attachmentName: Value<String?>(attachment == null ? null : _attachmentDisplayName(attachment!, attachmentNameController)),
                                      attachmentType: Value<String?>(attachment?.type),
                                      includeInNarrative: includeInNarrative,
                                    ),
                                  );
                              if (attachmentChanged) {
                                await _deleteAttachmentFile(oldAttachmentPath);
                              }
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) _notify(context, 'تغییرات ذخیره شد');
                            },
                            child: const Text('ذخیره'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteTimelineEvent(BuildContext context, AppDatabase db, CaseTimelineEvent event) async {
    if ((event.sourceType ?? '').trim().isNotEmpty && event.sourceId != null) {
      _notify(context, 'این سابقه خودکار است. برای حذف آن، وضعیت انجام‌شده منبع را بردارید یا خود کار، مهلت یا جلسه را حذف کنید.');
      return;
    }
    final confirmed = await _confirmDelete(context, 'حذف سابقه', 'آیا این سابقه از تاریخچه پرونده حذف شود؟');
    if (confirmed != true) return;
    await (db.delete(db.caseTimelineEvents)..where((t) => t.id.equals(event.id))).go();
    await _deleteAttachmentFile(event.attachmentPath);
    if (context.mounted) {
      _notify(context, 'حذف شد');
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAttachmentFile(String? filePath) async {
    final path = filePath?.trim();
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<_AttachmentDraft> _copyAttachmentToCaseFolder(String sourcePath, {String? originalName}) async {
    final source = File(sourcePath);
    final dir = await getApplicationDocumentsDirectory();
    final caseDir = Directory(p.join(dir.path, 'case_attachments', 'case_${item.id}'));
    if (!await caseDir.exists()) {
      await caseDir.create(recursive: true);
    }
    final nameFromPath = originalName?.trim().isNotEmpty == true ? originalName!.trim() : p.basename(sourcePath);
    final safeBaseName = nameFromPath.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final targetName = '${DateTime.now().millisecondsSinceEpoch}_$safeBaseName';
    final target = File(p.join(caseDir.path, targetName));
    await source.copy(target.path);
    return _AttachmentDraft(path: target.path, name: nameFromPath, type: _attachmentKindFromPath(target.path));
  }

  Future<_AttachmentDraft?> _pickAttachmentFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      final picked = result?.files.single;
      final path = picked?.path;
      if (path == null || path.isEmpty) return null;
      return _copyAttachmentToCaseFolder(path, originalName: picked?.name);
    } catch (_) {
      if (context.mounted) _notify(context, 'افزودن فایل انجام نشد.');
      return null;
    }
  }

  Future<_AttachmentDraft?> _captureAttachment(BuildContext context) async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.camera);
      if (image == null) return null;
      return _copyAttachmentToCaseFolder(image.path, originalName: p.basename(image.path));
    } catch (_) {
      if (context.mounted) _notify(context, 'دوربین یا ذخیره عکس در دسترس نبود.');
      return null;
    }
  }


  void _showCasePersonDialog(BuildContext context, AppDatabase db, {CasePerson? person}) {
    final nameController = TextEditingController(text: person?.name ?? '');
    final phoneController = TextEditingController(text: person?.phone ?? '');
    final rawNotes = person?.notes ?? '';
    var isClient = rawNotes.contains('موکل');
    final notesController = TextEditingController(text: rawNotes.replaceAll('موکل من است', '').replaceAll('موکل', '').trim());
    final isCriminal = item.caseType == 'کیفری';
    final mainRoles = isCriminal ? ['شاکی', 'متهم'] : ['خواهان', 'خوانده'];
    final roles = [...mainRoles, 'وکیل مقابل', 'کارشناس', 'شاهد', 'نماینده', 'سایر'];
    String role = person?.role ?? roles.first;
    if (!roles.contains(role)) role = roles.first;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(person == null ? 'افزودن شخص پرونده' : 'ویرایش شخص پرونده', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      items: roles.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => role = v ?? role),
                      decoration: InputDecoration(labelText: isCriminal ? 'سمت در پرونده کیفری' : 'سمت در پرونده حقوقی', border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isClient,
                      onChanged: (value) => setState(() => isClient = value ?? false),
                      title: const Text('موکل من است'),
                      subtitle: Text(isCriminal ? 'فقط شاکی یا متهم می‌تواند موکل باشد.' : 'فقط خواهان یا خوانده می‌تواند موکل باشد.'),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'نام', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'شماره تماس', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(controller: notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیح کوتاه', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) {
                                _notify(context, 'نام شخص را وارد کنید.');
                                return;
                              }
                              if (isClient && !mainRoles.contains(role)) {
                                _notify(context, 'موکل باید از سمت‌های اصلی پرونده انتخاب شود.');
                                return;
                              }
                              final noteParts = <String>[];
                              if (isClient) noteParts.add('موکل من است');
                              final noteText = notesController.text.trim();
                              if (noteText.isNotEmpty) noteParts.add(noteText);
                              final finalNotes = noteParts.join(' - ');

                              if (isClient) {
                                final allPeople = await (db.select(db.casePeople)..where((p) => p.caseId.equals(item.id))).get();
                                final oppositeRoles = role == mainRoles.first ? [mainRoles.last] : [mainRoles.first];
                                for (final other in allPeople) {
                                  if (other.id == person?.id) continue;
                                  if (oppositeRoles.contains(other.role) && (other.notes ?? '').contains('موکل')) {
                                    final cleanedNotes = (other.notes ?? '').replaceAll('موکل من است', '').replaceAll('موکل', '').trim();
                                    await db.update(db.casePeople).replace(
                                      CasePerson(
                                        id: other.id,
                                        caseId: other.caseId,
                                        name: other.name,
                                        role: other.role,
                                        phone: other.phone,
                                        notes: cleanedNotes.isEmpty ? null : cleanedNotes,
                                        createdAt: other.createdAt,
                                      ),
                                    );
                                  }
                                }
                              }

                              if (person == null) {
                                await db.into(db.casePeople).insert(
                                      CasePeopleCompanion.insert(
                                        caseId: item.id,
                                        name: name,
                                        role: Value(role),
                                        phone: Value(phoneController.text.trim()),
                                        notes: Value(finalNotes),
                                      ),
                                    );
                              } else {
                                await db.update(db.casePeople).replace(
                                      CasePerson(
                                        id: person.id,
                                        caseId: person.caseId,
                                        name: name,
                                        role: role,
                                        phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                                        notes: finalNotes.isEmpty ? null : finalNotes,
                                        createdAt: person.createdAt,
                                      ),
                                    );
                              }
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) _notify(context, person == null ? 'ثبت شد' : 'تغییرات ذخیره شد');
                            },
                            child: Text(person == null ? 'ثبت' : 'ذخیره'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteCasePerson(BuildContext context, AppDatabase db, CasePerson person) async {
    final confirmed = await _confirmDelete(context, 'حذف شخص', 'آیا این شخص از پرونده حذف شود؟');
    if (confirmed != true) return;
    await (db.delete(db.casePeople)..where((p) => p.id.equals(person.id))).go();
    if (context.mounted) {
      _notify(context, 'حذف شد');
    }
  }

  void _showCaseFinanceDialog(BuildContext context, AppDatabase db, {FinanceItem? item}) {
    const typeOptions = [
      'حق‌الوکاله دریافتی',
      'هزینه پرونده',
      'سایر دریافت',
      'سایر پرداخت',
    ];
    const costTitles = [
      'هزینه دادخواست',
      'هزینه دادخواست بدوی',
      'هزینه دادخواست واخواهی',
      'هزینه دادخواست تجدیدنظرخواهی',
      'هزینه دادخواست فرجام‌خواهی',
      'هزینه دادرسی',
      'هزینه کارشناسی',
      'هزینه هیأت کارشناسی',
      'هزینه لایحه',
      'هزینه دفاتر خدمات قضایی',
      'هزینه ابلاغ / استعلام / کپی / برابر اصل',
      'هزینه اجرای احکام',
      'هزینه ایاب و ذهاب / مأموریت',
    ];

    String defaultTitleFor(String type) {
      if (type == 'حق‌الوکاله دریافتی') return 'حق‌الوکاله دریافتی';
      if (type == 'هزینه پرونده') return '';
      return type;
    }

    String amountLabelFor(String type) {
      if (type == 'حق‌الوکاله دریافتی') return 'مبلغ دریافتی تومان';
      if (type == 'هزینه پرونده') return 'مبلغ هزینه تومان';
      return 'مبلغ تومان';
    }

    String dateLabelFor(String type) {
      if (type == 'حق‌الوکاله دریافتی') return 'تاریخ دریافت';
      if (type == 'هزینه پرونده' || type == 'سایر پرداخت') return 'تاریخ پرداخت / هزینه';
      return 'تاریخ دریافت';
    }

    final titleController = TextEditingController(text: item?.title ?? defaultTitleFor('حق‌الوکاله دریافتی'));
    final amountController = TextEditingController(text: item == null ? '' : formatMoneyInput(item.amount.toStringAsFixed(0)));
    final notesController = TextEditingController(text: item?.notes ?? '');
    String selectedType = typeOptions.contains(item?.type) ? item!.type : 'حق‌الوکاله دریافتی';
    bool costOnLawyer = item?.isLawyerCost ?? false;
    DateTime selectedDate = item?.date ?? DateTime.now();
    _AttachmentDraft? attachment = _hasAttachmentPath(item?.attachmentPath)
        ? _AttachmentDraft(
            path: item!.attachmentPath!,
            name: item.attachmentName ?? p.basename(item.attachmentPath!),
            type: item.attachmentType ?? _attachmentKindFromPath(item.attachmentPath!),
          )
        : null;
    final attachmentNameController = TextEditingController(text: attachment?.name ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          final titleQuery = titleController.text.trim();
          final filteredCosts = costTitles
              .where((option) => titleQuery.isEmpty || option.contains(titleQuery))
              .toList();
          final exactCostMatch = costTitles.any((option) => option == titleQuery);

          Widget titleField() {
            if (selectedType == 'حق‌الوکاله دریافتی') {
              return const SizedBox.shrink();
            }
            if (selectedType == 'هزینه پرونده') {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'نوع هزینه',
                      hintText: 'مثلاً هزینه کارشناسی یا هزینه دادخواست',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (titleQuery.isNotEmpty || filteredCosts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            ...filteredCosts.map((option) => ListTile(
                                  dense: true,
                                  title: Text(option),
                                  trailing: option == titleQuery ? const Icon(Icons.check) : null,
                                  onTap: () => setState(() => titleController.text = option),
                                )),
                            if (titleQuery.isNotEmpty && !exactCostMatch)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.add),
                                title: Text('ثبت «$titleQuery» به‌عنوان نوع هزینه جدید'),
                                onTap: () => setState(() => titleController.text = titleQuery),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            }
            return TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: selectedType == 'سایر دریافت' ? 'عنوان دریافت' : 'عنوان پرداخت',
                hintText: selectedType == 'سایر دریافت' ? 'مثلاً دریافت متفرقه از موکل' : 'مثلاً پرداخت متفرقه پرونده',
                border: const OutlineInputBorder(),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item == null ? 'ثبت مالی پرونده' : 'ویرایش مالی پرونده', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      items: typeOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() {
                        final next = v ?? selectedType;
                        selectedType = next;
                        costOnLawyer = next == 'هزینه پرونده' ? costOnLawyer : false;
                        titleController.text = defaultTitleFor(next);
                      }),
                      decoration: const InputDecoration(labelText: 'نوع ثبت مالی', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    titleField(),
                    if (selectedType != 'حق‌الوکاله دریافتی') const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [MoneyInputFormatter()],
                      decoration: InputDecoration(labelText: amountLabelFor(selectedType), border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(dateLabelFor(selectedType)),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, dateLabelFor(selectedType));
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    if (selectedType == 'هزینه پرونده')
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: costOnLawyer,
                        title: const Text('هزینه به عهده وکیل است'),
                        subtitle: const Text('اگر فعال باشد، در مانده قابل دریافت از موکل حساب نمی‌شود.'),
                        onChanged: (v) => setState(() => costOnLawyer = v ?? false),
                      ),
                    const SizedBox(height: 12),
                    TextField(controller: notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات اختیاری', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    _AttachmentPickerCard(
                      title: 'مدرک مالی / رسید',
                      attachmentName: attachment?.name,
                      attachmentType: attachment?.type,
                      nameController: attachmentNameController,
                      onPickFile: () async {
                        final picked = await _pickAttachmentFile(sheetContext);
                        if (picked != null) {
                          setState(() {
                            attachment = picked;
                            attachmentNameController.text = picked.name;
                          });
                        }
                      },
                      onCamera: () async {
                        final picked = await _captureAttachment(sheetContext);
                        if (picked != null) {
                          setState(() {
                            attachment = picked;
                            attachmentNameController.text = picked.name;
                          });
                        }
                      },
                      onRemove: attachment == null ? null : () => setState(() {
                        attachment = null;
                        attachmentNameController.clear();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final title = selectedType == 'حق‌الوکاله دریافتی'
                                  ? 'حق‌الوکاله دریافتی'
                                  : titleController.text.trim();
                              final amount = parseMoney(amountController.text);
                              if (title.isEmpty) {
                                final message = selectedType == 'هزینه پرونده' ? 'نوع هزینه را وارد یا انتخاب کنید.' : 'عنوان را وارد کنید.';
                                _notify(context, message);
                                return;
                              }
                              if (amount == null || amount <= 0) {
                                _notify(context, 'مبلغ معتبر وارد کنید.');
                                return;
                              }
                              if (item == null) {
                                await db.into(db.financeItems).insert(
                                      FinanceItemsCompanion.insert(
                                        caseId: Value(this.item.id),
                                        type: selectedType,
                                        title: title,
                                        amount: amount,
                                        category: Value(selectedType == 'هزینه پرونده' ? title : selectedType),
                                        date: Value(selectedDate),
                                        notes: Value(notesController.text.trim()),
                                        attachmentPath: Value<String?>(attachment?.path),
                                        attachmentName: Value<String?>(attachment == null ? null : _attachmentDisplayName(attachment!, attachmentNameController)),
                                        attachmentType: Value<String?>(attachment?.type),
                                        isLawyerCost: Value(costOnLawyer),
                                      ),
                                    );
                              } else {
                                if ((item.attachmentPath ?? '') != (attachment?.path ?? '')) {
                                  await _deleteAttachmentFile(item.attachmentPath);
                                }
                                await db.update(db.financeItems).replace(
                                      FinanceItem(
                                        id: item.id,
                                        caseId: item.caseId ?? this.item.id,
                                        type: selectedType,
                                        title: title,
                                        amount: amount,
                                        category: selectedType == 'هزینه پرونده' ? title : selectedType,
                                        date: selectedDate,
                                        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                        attachmentPath: attachment?.path,
                                        attachmentName: attachment == null ? null : _attachmentDisplayName(attachment!, attachmentNameController),
                                        attachmentType: attachment?.type,
                                        isLawyerCost: costOnLawyer,
                                      ),
                                    );
                              }
                              if (context.mounted) _notify(context, item == null ? 'ثبت شد' : 'تغییرات ذخیره شد');
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            },
                            child: Text(item == null ? 'ثبت' : 'ذخیره'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteCaseFinance(BuildContext context, AppDatabase db, FinanceItem item) async {
    final confirmed = await _confirmDelete(context, 'حذف ثبت مالی', 'آیا این ثبت مالی از پرونده حذف شود؟');
    if (confirmed != true) return;
    await (db.delete(db.financeItems)..where((f) => f.id.equals(item.id))).go();
    await _deleteAttachmentFile(item.attachmentPath);
    if (context.mounted) {
      _notify(context, 'حذف شد');
    }
  }


}



class _AttachmentPickerCard extends StatelessWidget {
  const _AttachmentPickerCard({
    required this.title,
    required this.attachmentName,
    required this.attachmentType,
    this.nameController,
    required this.onPickFile,
    required this.onCamera,
    required this.onRemove,
  });

  final String title;
  final String? attachmentName;
  final String? attachmentType;
  final TextEditingController? nameController;
  final VoidCallback onPickFile;
  final VoidCallback onCamera;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasAttachment = (attachmentName ?? '').trim().isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(hasAttachment ? Icons.attach_file : Icons.note_add),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasAttachment
                        ? '$title: ${attachmentName!} (${_attachmentKindLabel(attachmentType)})'
                        : '$title: هنوز مدرکی اضافه نشده است.',
                  ),
                ),
                if (hasAttachment && onRemove != null)
                  IconButton(
                    tooltip: 'حذف مدرک از این ثبت',
                    icon: const Icon(Icons.close),
                    onPressed: onRemove,
                  ),
              ],
            ),
            if (hasAttachment && nameController != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'نام نمایشی پیوست',
                  hintText: 'مثلاً رای دادگاه، نظریه کارشناسی یا رسید پرداخت',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('افزودن فایل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('اسکن/عکس'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _CaseInfoSection extends StatefulWidget {
  const _CaseInfoSection({
    required this.item,
    required this.db,
    required this.onEditCase,
    required this.onAddPerson,
    required this.onEditPerson,
    required this.onDeletePerson,
  });

  final Case item;
  final AppDatabase db;
  final VoidCallback onEditCase;
  final VoidCallback onAddPerson;
  final void Function(CasePerson person) onEditPerson;
  final void Function(CasePerson person) onDeletePerson;

  @override
  State<_CaseInfoSection> createState() => _CaseInfoSectionState();
}

class _CaseInfoSectionState extends State<_CaseInfoSection> {
  bool _expanded = false;

  void _toggle() {
    if (!mounted) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.gavel),
            title: Text('مشخصات پرونده ${widget.item.title}'),
            subtitle: Text('${widget.item.caseType ?? 'نوع ثبت نشده'} | ${widget.item.subject ?? 'موضوع ثبت نشده'}'),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: _toggle,
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onEditCase,
                                  icon: const Icon(Icons.edit),
                                  label: const Text('ویرایش مشخصات'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onAddPerson,
                                  icon: const Icon(Icons.person_add),
                                  label: const Text('افزودن شخص'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          StreamBuilder<List<CasePerson>>(
                            stream: (widget.db.select(widget.db.casePeople)..where((p) => p.caseId.equals(widget.item.id))).watch(),
                            builder: (context, snapshot) {
                              final people = List<CasePerson>.of(snapshot.data ?? const <CasePerson>[]);
                              return Card(
                                child: ListTile(
                                  title: const Text('خلاصه مشخصات'),
                                  subtitle: Text(_safeCaseSummaryText(widget.item, people)),
                                ),
                              );
                            },
                          ),
                          _CasePeopleSection(
                            item: widget.item,
                            db: widget.db,
                            onAdd: widget.onAddPerson,
                            onEdit: widget.onEditPerson,
                            onDelete: widget.onDeletePerson,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _CasePeopleSection extends StatelessWidget {
  const _CasePeopleSection({
    required this.item,
    required this.db,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final Case item;
  final AppDatabase db;
  final VoidCallback onAdd;
  final void Function(CasePerson person) onEdit;
  final void Function(CasePerson person) onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups),
              title: const Text('اشخاص پرونده'),
              subtitle: const Text('موکل، طرف مقابل، وکیل مقابل، کارشناس، شاهد و اشخاص مرتبط.'),
              trailing: FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add),
                label: const Text('افزودن'),
              ),
            ),
            StreamBuilder<List<CasePerson>>(
              stream: (db.select(db.casePeople)..where((p) => p.caseId.equals(item.id))).watch(),
              builder: (context, snapshot) {
                final people = List<CasePerson>.of(snapshot.data ?? const <CasePerson>[]);
                if (people.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text('هنوز شخصی برای این پرونده ثبت نشده است.', style: TextStyle(color: Colors.white60)),
                  );
                }
                return Column(
                  children: people.map((person) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text('${person.role}: ${person.name}'),
                      subtitle: Text([
                        if ((person.phone ?? '').isNotEmpty) 'تماس: ${person.phone}',
                        if ((person.notes ?? '').isNotEmpty) person.notes!,
                      ].join('\n')),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') onEdit(person);
                          if (value == 'delete') onDelete(person);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}



class _CaseNarrativeSection extends StatefulWidget {
  const _CaseNarrativeSection({required this.item, required this.db});

  final Case item;
  final AppDatabase db;

  @override
  State<_CaseNarrativeSection> createState() => _CaseNarrativeSectionState();
}

class _CaseNarrativeSectionState extends State<_CaseNarrativeSection> {
  int _refreshToken = 0;
  CaseNarrativeMode _mode = CaseNarrativeMode.normal;
  final TextEditingController _narrativeController = TextEditingController();
  String? _lastGeneratedText;

  @override
  void dispose() {
    _narrativeController.dispose();
    super.dispose();
  }

  Future<CaseNarrativeResult> _loadNarrative() async {
    final people = await (widget.db.select(widget.db.casePeople)..where((p) => p.caseId.equals(widget.item.id))).get();
    final events = await (widget.db.select(widget.db.caseTimelineEvents)..where((e) => e.caseId.equals(widget.item.id))).get();
    final profiles = await widget.db.select(widget.db.userProfiles).get();
    final profile = profiles.isEmpty ? null : profiles.last;
    return const CaseNarrativeService().generate(
      item: widget.item,
      people: people,
      events: events,
      profile: profile,
      mode: _mode,
    );
  }

  Future<void> _copyText(BuildContext context) async {
    final text = _narrativeController.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('شرح پرونده کپی شد.')));
  }

  void _syncGeneratedText(String text) {
    if (_lastGeneratedText == text) return;
    _lastGeneratedText = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _narrativeController.text = text;
    });
  }

  void _regenerate() {
    _lastGeneratedText = null;
    setState(() => _refreshToken += 1);
  }

  String _modeLabel(CaseNarrativeMode mode) {
    switch (mode) {
      case CaseNarrativeMode.short:
        return 'خلاصه کوتاه';
      case CaseNarrativeMode.normal:
        return 'شرح معمولی';
      case CaseNarrativeMode.full:
        return 'شرح کامل';
    }
  }

  String _modeHelp(CaseNarrativeMode mode) {
    switch (mode) {
      case CaseNarrativeMode.short:
        return 'خروجی کوتاه برای مرور سریع پرونده.';
      case CaseNarrativeMode.normal:
        return 'متن روان و حقوقی برای استفاده روزمره، بدون حالت فهرستی.';
      case CaseNarrativeMode.full:
        return 'شرح مفصل‌تر با اطلاعات تکمیلی پرونده، شماره‌ها، شعبه، مرحله و روند کامل.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: StreamBuilder<int>(
        stream: widget.db.watchAny(),
        builder: (context, _) {
          return FutureBuilder<CaseNarrativeResult>(
            key: ValueKey('$_refreshToken-${_mode.name}'),
            future: _loadNarrative(),
            builder: (context, snapshot) {
              final result = snapshot.data;
              if (result != null) _syncGeneratedText(result.text);
              final subtitle = result == null
                  ? 'گزارش خودکار آفلاین از مشخصات و تاریخچه پرونده'
                  : result.hasTimelineData
                      ? '${_modeLabel(_mode)}؛ تولیدشده از مشخصات پرونده و ${result.usedEventsCount} سابقه منتخب برای شرح'
                      : '${_modeLabel(_mode)}؛ تولید اولیه از مشخصات پرونده، تاریخچه هنوز کامل نیست';

              return ExpansionTile(
                leading: const Icon(Icons.auto_stories),
                title: Text('شرح پرونده ${widget.item.title}'),
                subtitle: Text(subtitle),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  if (snapshot.connectionState == ConnectionState.waiting && result == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<CaseNarrativeMode>(
                        segments: const [
                        ButtonSegment<CaseNarrativeMode>(
                          value: CaseNarrativeMode.short,
                          label: Text('کوتاه'),
                          icon: Icon(Icons.short_text),
                        ),
                        ButtonSegment<CaseNarrativeMode>(
                          value: CaseNarrativeMode.normal,
                          label: Text('معمولی'),
                          icon: Icon(Icons.notes),
                        ),
                        ButtonSegment<CaseNarrativeMode>(
                          value: CaseNarrativeMode.full,
                          label: Text('کامل'),
                          icon: Icon(Icons.subject),
                        ),
                      ],
                        selected: {_mode},
                        onSelectionChanged: (selection) {
                          final selected = selection.first;
                          _lastGeneratedText = null;
                          setState(() {
                            _mode = selected;
                            _refreshToken += 1;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _modeHelp(_mode),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: result == null ? null : () => _copyText(context),
                          icon: const Icon(Icons.copy),
                          label: const Text('کپی متن'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _regenerate,
                          icon: const Icon(Icons.refresh),
                          label: const Text('بازتولید شرح'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _narrativeController,
                    enabled: result != null,
                    minLines: 7,
                    maxLines: 16,
                    textAlign: TextAlign.justify,
                    decoration: InputDecoration(
                      labelText: 'متن شرح پرونده',
                      helperText: 'متن تولیدشده قابل ویرایش است؛ بعد از اصلاح، همان متن کپی می‌شود.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'این متن به‌صورت آفلاین و قالب‌محور از اطلاعات پرونده و تاریخچه مرتب‌شده از قدیمی‌تر به جدیدتر ساخته می‌شود و مشخصات پرونده را به شکل طبیعی داخل متن می‌آورد.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}


class _CaseHistorySection extends StatelessWidget {
  const _CaseHistorySection({
    required this.item,
    required this.db,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final Case item;
  final AppDatabase db;
  final VoidCallback onAdd;
  final void Function(CaseTimelineEvent event) onEdit;
  final void Function(CaseTimelineEvent event) onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: StreamBuilder<List<CaseTimelineEvent>>(
        stream: (db.select(db.caseTimelineEvents)..where((e) => e.caseId.equals(item.id))).watch(),
        builder: (context, snapshot) {
          final events = List<CaseTimelineEvent>.of(snapshot.data ?? const <CaseTimelineEvent>[])
            .where((event) => (event.eventType ?? '') != 'جلسه')
            .toList()
            ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
          final subtitle = events.isEmpty ? 'هنوز سابقه‌ای ثبت نشده است.' : '${events.length} مورد، جدیدترین‌ها بالاتر';
          return ExpansionTile(
            leading: const Icon(Icons.history),
            title: Text('تاریخچه پرونده ${item.title}'),
            subtitle: Text(subtitle),
            trailing: PopupMenuButton<String>(
              tooltip: 'عملیات تاریخچه',
              onSelected: (value) {
                if (value == 'add') onAdd();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('افزودن سابقه')),
              ],
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن سابقه'),
                ),
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                const Text('سابقه‌های پرونده را از این بخش ثبت کنید.', style: TextStyle(color: Colors.white60))
              else
                ...events.map((e) {
                  final hasAttachment = _hasAttachmentPath(e.attachmentPath);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(hasAttachment ? Icons.attach_file : Icons.event_note),
                    title: Text(e.title.isEmpty ? 'سابقه بدون عنوان' : e.title),
                    subtitle: Text(_caseHistorySubtitle(e)),
                    onTap: hasAttachment
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CaseAttachmentViewerScreen(
                                  filePath: e.attachmentPath!,
                                  title: e.attachmentName ?? e.title,
                                  fileType: e.attachmentType,
                                ),
                              ),
                            )
                        : null,
                    trailing: PopupMenuButton<String>(
                      tooltip: 'عملیات سابقه',
                      onSelected: (value) {
                        if (value == 'open' && hasAttachment) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaseAttachmentViewerScreen(
                                filePath: e.attachmentPath!,
                                title: e.attachmentName ?? e.title,
                                fileType: e.attachmentType,
                              ),
                            ),
                          );
                        }
                        if (value == 'share' && hasAttachment) {
                          _shareAttachmentFile(context, e.attachmentPath, e.attachmentName ?? e.title);
                        }
                        if (value == 'edit') onEdit(e);
                        if (value == 'delete') onDelete(e);
                      },
                      itemBuilder: (_) => [
                        if (hasAttachment) const PopupMenuItem(value: 'open', child: Text('مشاهده مدرک')),
                        if (hasAttachment) const PopupMenuItem(value: 'share', child: Text('اشتراک‌گذاری مدرک')),
                        const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _CaseActionRow {
  const _CaseActionRow({
    required this.kind,
    required this.title,
    required this.date,
    required this.priority,
    required this.isDone,
    required this.icon,
    this.task,
    this.deadline,
    this.session,
    this.subtitle,
  });

  final String kind;
  final String title;
  final DateTime? date;
  final String priority;
  final bool isDone;
  final IconData icon;
  final Task? task;
  final Deadline? deadline;
  final CaseTimelineEvent? session;
  final String? subtitle;
}

class _CaseActionsData {
  const _CaseActionsData(this.rows);
  final List<_CaseActionRow> rows;
}

class _CaseTasksSection extends StatelessWidget {
  const _CaseTasksSection({
    required this.item,
    required this.db,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final Case item;
  final AppDatabase db;
  final VoidCallback onAdd;
  final void Function(Task task) onEdit;
  final void Function(Task task) onDelete;

  int _priorityRank(String priority) {
    switch (priority) {
      case 'فوری':
      case 'خیلی زیاد':
        return 0;
      case 'زیاد':
        return 1;
      case 'متوسط':
        return 2;
      case 'کم':
        return 3;
      default:
        return 2;
    }
  }

  Future<_CaseActionsData> _load() async {
    final tasks = await (db.select(db.tasks)..where((t) => t.caseId.equals(item.id))).get();
    final deadlines = (await db.select(db.deadlines).get()).where((d) => d.caseId == item.id).toList();
    final sessions = (await (db.select(db.caseTimelineEvents)..where((e) => e.caseId.equals(item.id))).get())
        .where((e) => (e.eventType ?? '') == 'جلسه')
        .toList();

    final rows = <_CaseActionRow>[
      ...tasks.map((task) => _CaseActionRow(
            kind: 'کار / اقدام',
            title: task.title,
            date: task.dueDate,
            priority: task.priority,
            isDone: task.isDone,
            icon: Icons.task_alt,
            task: task,
            subtitle: 'اولویت: ${task.priority}',
          )),
      ...deadlines.map((deadline) => _CaseActionRow(
            kind: 'مهلت قانونی',
            title: deadline.title,
            date: deadline.dueDate,
            priority: deadline.priority,
            isDone: deadline.isDone,
            icon: Icons.alarm,
            deadline: deadline,
            subtitle: deadline.deadlineType ?? 'مهلت قانونی',
          )),
      ...sessions.map((session) => _CaseActionRow(
            kind: 'جلسه رسیدگی',
            title: session.title,
            date: session.eventDate,
            priority: 'خیلی زیاد',
            isDone: session.isDone,
            icon: Icons.groups,
            session: session,
            subtitle: session.description ?? 'جلسه رسیدگی',
          )),
    ];

    rows.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final aDate = a.date ?? DateTime(9999);
      final bDate = b.date ?? DateTime(9999);
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) return dateCompare;
      return _priorityRank(a.priority).compareTo(_priorityRank(b.priority));
    });
    return _CaseActionsData(rows);
  }

  bool _isNearDue(_CaseActionRow row) {
    if (row.isDone || row.date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(row.date!.year, row.date!.month, row.date!.day);
    final lastWarningDay = today.add(const Duration(days: 3));
    return !due.isBefore(today) && !due.isAfter(lastWarningDay);
  }

  Future<bool> _confirm(BuildContext context, String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteDeadline(BuildContext context, Deadline deadline) async {
    if (!await _confirm(context, 'حذف مهلت', 'آیا این مهلت قانونی حذف شود؟')) return;
    await db.deleteDeadlineWithTimeline(deadline.id);
  }

  Future<void> _deleteSession(BuildContext context, CaseTimelineEvent session) async {
    if (!await _confirm(context, 'حذف جلسه', 'آیا این جلسه رسیدگی حذف شود؟')) return;
    await db.deleteCaseSessionWithTimeline(session.id);
  }

  Future<void> _markTaskDone(Task task, bool done) async {
    await db.setTaskDone(task, done);
  }

  Future<void> _markDeadlineDone(Deadline deadline, bool done) async {
    await db.setDeadlineDone(deadline, done);
  }

  Future<void> _markSessionDone(CaseTimelineEvent session, bool done) async {
    await db.setCaseSessionDone(session, done);
  }

  Future<DateTime?> _pickActionDate(BuildContext context, DateTime current, String title) {
    return pickPersianDate(context, initialDate: current, title: title);
  }

  Future<TimeOfDay?> _pickActionTime(BuildContext context, TimeOfDay current) {
    return showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'انتخاب ساعت',
      cancelText: 'لغو',
      confirmText: 'تأیید',
      hourLabelText: 'ساعت',
      minuteLabelText: 'دقیقه',
    );
  }

  void _editDeadline(BuildContext context, Deadline deadline) {
    final typeController = TextEditingController(text: deadline.deadlineType ?? deadline.title);
    final notesController = TextEditingController(text: deadline.notes ?? '');
    DateTime selectedDate = deadline.dueDate;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ویرایش مهلت قانونی', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'نوع مهلت قانونی', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ پایان مهلت'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _pickActionDate(sheetContext, selectedDate, 'تاریخ پایان مهلت');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'توضیح مهلت، اختیاری', border: OutlineInputBorder()),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final type = typeController.text.trim();
                              if (type.isEmpty) return;
                              final updatedDeadline = deadline.copyWith(
                                title: type,
                                deadlineType: Value(type),
                                dueDate: selectedDate,
                                notes: Value(notesController.text.trim()),
                              );
                              await db.setDeadlineDone(updatedDeadline, updatedDeadline.isDone);
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            },
                            child: const Text('ذخیره'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _editSession(BuildContext context, CaseTimelineEvent session) {
    final typeController = TextEditingController(text: session.title);
    final notesController = TextEditingController(text: session.description ?? '');
    DateTime selectedDate = session.eventDate;
    TimeOfDay selectedTime = TimeOfDay(hour: session.eventDate.hour, minute: session.eventDate.minute);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final insets = MediaQuery.of(sheetContext).viewInsets;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ویرایش جلسه رسیدگی', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'نوع جلسه رسیدگی', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ جلسه'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _pickActionDate(sheetContext, selectedDate, 'تاریخ جلسه');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('ساعت جلسه'),
                      subtitle: Text(toPersianDigits("${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}")),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final picked = await _pickActionTime(sheetContext, selectedTime);
                        if (picked != null) setState(() => selectedTime = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'توضیح جلسه، اختیاری', border: OutlineInputBorder()),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final type = typeController.text.trim();
                              if (type.isEmpty) return;
                              final dateTime = DateTime(
                                selectedDate.year,
                                selectedDate.month,
                                selectedDate.day,
                                selectedTime.hour,
                                selectedTime.minute,
                              );
                              final updatedSession = session.copyWith(
                                title: type,
                                eventType: const Value('جلسه'),
                                description: Value(notesController.text.trim()),
                                eventDate: dateTime,
                                includeInNarrative: false,
                              );
                              await db.setCaseSessionDone(updatedSession, updatedSession.isDone);
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            },
                            child: const Text('ذخیره'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: StreamBuilder<int>(
        stream: db.watchAny(),
        builder: (context, _) {
          return FutureBuilder<_CaseActionsData>(
            future: _load(),
            builder: (context, snapshot) {
              final rows = snapshot.data?.rows ?? const <_CaseActionRow>[];
              final openCount = rows.where((row) => !row.isDone).length;
              final subtitle = rows.isEmpty ? 'کار، مهلت یا جلسه‌ای ثبت نشده است.' : '$openCount مورد باز از ${rows.length} مورد، مرتب بر اساس تاریخ و اولویت';
              return ExpansionTile(
                leading: const Icon(Icons.task_alt),
                title: Text('کارها، مهلت‌ها و جلسات پرونده ${item.title}'),
                subtitle: Text(subtitle),
                trailing: PopupMenuButton<String>(
                  tooltip: 'عملیات اقدامات',
                  onSelected: (value) {
                    if (value == 'add') onAdd();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('افزودن مورد')),
                  ],
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_task),
                      label: const Text('افزودن کار / مهلت / جلسه'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting && rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (rows.isEmpty)
                    Text('کار، مهلت قانونی و جلسه رسیدگی مربوط به همین پرونده اینجا نمایش داده می‌شود.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                  else
                    ...rows.map((row) {
                      final dateText = row.date == null ? 'بدون تاریخ' : formatPersianLongDate(row.date!);
                      final timeValue = row.date == null ? '' : "${row.date!.hour.toString().padLeft(2, '0')}:${row.date!.minute.toString().padLeft(2, '0')}";
                      final timeText = row.kind == 'جلسه رسیدگی' && row.date != null ? ' - ${toPersianDigits(timeValue)}' : '';
                      final isNearDue = _isNearDue(row);
                      final warningColor = Theme.of(context).colorScheme.error;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: row.task != null
                            ? Checkbox(
                                value: row.task!.isDone,
                                onChanged: (value) async {
                                  await _markTaskDone(row.task!, value ?? false);
                                },
                              )
                            : row.deadline != null
                                ? Checkbox(
                                    value: row.deadline!.isDone,
                                    onChanged: (value) async {
                                      await _markDeadlineDone(row.deadline!, value ?? false);
                                    },
                                  )
                                : row.session != null
                                    ? Checkbox(
                                        value: row.session!.isDone,
                                        onChanged: (value) async {
                                          await _markSessionDone(row.session!, value ?? false);
                                        },
                                      )
                                    : Icon(row.icon),
                        title: Text(
                          row.title,
                          style: TextStyle(
                            fontWeight: isNearDue ? FontWeight.w800 : FontWeight.normal,
                            color: isNearDue ? warningColor : null,
                          ),
                        ),
                        subtitle: Text(
                          '${row.kind} | $dateText$timeText\n${row.subtitle ?? ''}',
                          style: TextStyle(
                            fontWeight: isNearDue ? FontWeight.w600 : FontWeight.normal,
                            color: isNearDue ? warningColor.withOpacity(0.86) : null,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'عملیات مورد',
                          onSelected: (value) {
                            if (row.task != null) {
                              if (value == 'edit') onEdit(row.task!);
                              if (value == 'delete') onDelete(row.task!);
                            } else if (row.deadline != null) {
                              if (value == 'edit') _editDeadline(context, row.deadline!);
                              if (value == 'delete') _deleteDeadline(context, row.deadline!);
                            } else if (row.session != null) {
                              if (value == 'edit') _editSession(context, row.session!);
                              if (value == 'delete') _deleteSession(context, row.session!);
                            }
                          },
                          itemBuilder: (_) => row.task != null
                              ? const [
                                  PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                                ]
                              : const [
                                  PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                                ],
                        ),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}


class _FinanceSummaryLine extends StatelessWidget {
  const _FinanceSummaryLine({
    required this.label,
    required this.amount,
    this.highlightDebt = false,
    this.positiveGood = false,
  });

  final String label;
  final double amount;
  final bool highlightDebt;
  final bool positiveGood;

  @override
  Widget build(BuildContext context) {
    final isImportantDebt = highlightDebt && amount > 0;
    final isGood = positiveGood && amount > 0 || highlightDebt && amount <= 0;
    final color = isImportantDebt
        ? Colors.redAccent
        : isGood
            ? Colors.greenAccent
            : Colors.white70;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          Text(
            '${formatMoney(amount)} تومان',
            style: TextStyle(
              color: color,
              fontWeight: isImportantDebt || isGood ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class _CaseFinanceSection extends StatelessWidget {
  const _CaseFinanceSection({
    required this.item,
    required this.db,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final Case item;
  final AppDatabase db;
  final VoidCallback onAdd;
  final void Function(FinanceItem finance) onEdit;
  final void Function(FinanceItem finance) onDelete;

  bool _isFeeTotal(FinanceItem item) => item.type == 'حق‌الوکاله توافقی';
  bool _isFeeReceived(FinanceItem item) => item.type == 'حق‌الوکاله دریافتی';
  bool _isCaseCost(FinanceItem item) => item.type == 'هزینه پرونده';
  bool _isReceipt(FinanceItem item) => item.type == 'سایر دریافت';
  bool _isPayment(FinanceItem item) => item.type == 'سایر پرداخت';

  double _sum(Iterable<FinanceItem> items) => items.fold<double>(0, (sum, item) => sum + item.amount);

  IconData _iconFor(FinanceItem item) {
    if (_isFeeTotal(item)) return Icons.request_quote;
    if (_isFeeReceived(item) || _isReceipt(item)) return Icons.trending_up;
    return Icons.trending_down;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: StreamBuilder<List<FinanceItem>>(
        stream: db.select(db.financeItems).watch(),
        builder: (context, snapshot) {
          final items = List<FinanceItem>.of(snapshot.data ?? const <FinanceItem>[])
              .where((f) => f.caseId == item.id)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          final totalFee = _sum(items.where(_isFeeTotal));
          final receivedFee = _sum(items.where(_isFeeReceived));
          final remainingFee = totalFee - receivedFee;
          final recoverableCosts = _sum(items.where((i) => _isCaseCost(i) && !i.isLawyerCost));
          final lawyerCosts = _sum(items.where((i) => _isCaseCost(i) && i.isLawyerCost));
          final otherReceipts = _sum(items.where(_isReceipt));
          final otherPayments = _sum(items.where(_isPayment));
          final receivableFromClient = remainingFee + recoverableCosts + otherPayments - otherReceipts;

          return ExpansionTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: Text('مالی پرونده ${item.title}'),
            subtitle: Text(
              'مانده قابل دریافت: ${formatMoney(receivableFromClient)} تومان',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: receivableFromClient > 0 ? Colors.orangeAccent : Colors.greenAccent,
              ),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'عملیات مالی پرونده',
              onSelected: (value) {
                if (value == 'add') onAdd();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('ثبت مالی جدید')),
              ],
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('خلاصه مالی', style: TextStyle(fontWeight: FontWeight.bold))),
                        FilledButton.tonalIcon(
                          onPressed: onAdd,
                          icon: const Icon(Icons.add),
                          label: const Text('ثبت'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _FinanceSummaryLine(label: 'کل حق‌الوکاله', amount: totalFee),
                    _FinanceSummaryLine(label: 'دریافتی حق‌الوکاله', amount: receivedFee, positiveGood: true),
                    _FinanceSummaryLine(label: 'مانده حق‌الوکاله', amount: remainingFee, highlightDebt: true),
                    _FinanceSummaryLine(label: 'هزینه قابل مطالبه از موکل', amount: recoverableCosts),
                    _FinanceSummaryLine(label: 'هزینه به عهده وکیل', amount: lawyerCosts),
                    _FinanceSummaryLine(label: 'سایر دریافت', amount: otherReceipts, positiveGood: true),
                    _FinanceSummaryLine(label: 'سایر پرداخت', amount: otherPayments),
                  ],
                ),
              ),
              if (items.isEmpty)
                const Text('ثبت مالی برای این پرونده وجود ندارد.', style: TextStyle(color: Colors.white60))
              else
                ...items.map((finance) {
                  final hasAttachment = _hasAttachmentPath(finance.attachmentPath);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(hasAttachment ? Icons.receipt_long : _iconFor(finance)),
                    title: Text(finance.title),
                    subtitle: Text(
                      '${finance.type} | ${formatMoney(finance.amount)} تومان | ${formatPersianLongDate(finance.date)}'
                      '${finance.isLawyerCost ? '\nهزینه به عهده وکیل' : ''}'
                      '${(finance.notes ?? '').isEmpty ? '' : '\n${finance.notes}'}'
                      '${hasAttachment ? '\nمدرک مالی: ${finance.attachmentName ?? p.basename(finance.attachmentPath!)}' : ''}',
                    ),
                    onTap: hasAttachment
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CaseAttachmentViewerScreen(
                                  filePath: finance.attachmentPath!,
                                  title: finance.attachmentName ?? finance.title,
                                  fileType: finance.attachmentType,
                                ),
                              ),
                            )
                        : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'open' && hasAttachment) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaseAttachmentViewerScreen(
                                filePath: finance.attachmentPath!,
                                title: finance.attachmentName ?? finance.title,
                                fileType: finance.attachmentType,
                              ),
                            ),
                          );
                        }
                        if (value == 'share' && hasAttachment) {
                          _shareAttachmentFile(context, finance.attachmentPath, finance.attachmentName ?? finance.title);
                        }
                        if (value == 'edit') onEdit(finance);
                        if (value == 'delete') onDelete(finance);
                      },
                      itemBuilder: (_) => [
                        if (hasAttachment) const PopupMenuItem(value: 'open', child: Text('مشاهده مدرک مالی')),
                        if (hasAttachment) const PopupMenuItem(value: 'share', child: Text('اشتراک‌گذاری مدرک مالی')),
                        const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
