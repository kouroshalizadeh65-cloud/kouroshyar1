import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import 'case_detail_screen.dart';
import 'edit_case_screen.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/money_format.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../core/widgets/global_search_field.dart';
import '../../core/widgets/persian_date_picker.dart';


bool _isClientPerson(CasePerson person) => (person.notes ?? '').contains('موکل');

String _joinCaseNames(Iterable<String> names) {
  final values = names.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  return values.isEmpty ? 'ثبت نشده' : values.join('، ');
}

String _caseListSubtitleText(Case item, List<CasePerson> people) {
  final type = item.caseType == 'کیفری' ? 'کیفری' : 'حقوقی';
  final clients = people.where(_isClientPerson).toList();
  final clientNames = clients.isEmpty ? (item.clientName?.trim() ?? '') : _joinCaseNames(clients.map((p) => p.name));
  final clientRoles = clients.isEmpty
      ? (item.clientRole?.trim() ?? '')
      : _joinCaseNames(clients.map((p) => p.role).toSet());
  final parts = <String>['نوع: $type'];
  if (type == 'حقوقی') {
    final plaintiffs = _joinCaseNames(people.where((p) => p.role == 'خواهان').map((p) => p.name));
    final defendants = _joinCaseNames(people.where((p) => p.role == 'خوانده').map((p) => p.name));
    if (plaintiffs != 'ثبت نشده') parts.add('خواهان: $plaintiffs');
    if (defendants != 'ثبت نشده') parts.add('خوانده: $defendants');
    if ((item.subject ?? '').trim().isNotEmpty) parts.add('خواسته: ${item.subject}');
  } else {
    final complainants = _joinCaseNames(people.where((p) => p.role == 'شاکی').map((p) => p.name));
    final accused = _joinCaseNames(people.where((p) => p.role == 'متهم').map((p) => p.name));
    if (complainants != 'ثبت نشده') parts.add('شاکی: $complainants');
    if (accused != 'ثبت نشده') parts.add('متهم: $accused');
    if ((item.subject ?? '').trim().isNotEmpty) parts.add('اتهام: ${item.subject}');
  }
  if (clientNames.isNotEmpty) parts.add('موکل من: $clientNames');
  if (clientRoles.isNotEmpty) parts.add('سمت موکل: $clientRoles');
  if ((item.caseNumber ?? '').isNotEmpty) parts.add('شماره پرونده: ${item.caseNumber}');
  if ((item.archiveNumber ?? '').isNotEmpty) parts.add('شماره بایگانی: ${item.archiveNumber}');
  if (item.status.isNotEmpty && item.status != 'فعال') parts.add('وضعیت: ${item.status}');
  return parts.join('\n');
}

String _safeCaseListSubtitleText(Case item, List<CasePerson> people) {
  try {
    return _caseListSubtitleText(item, people);
  } catch (_) {
    final type = item.caseType == 'کیفری' ? 'کیفری' : 'حقوقی';
    final subject = (item.subject ?? '').trim();
    final fallback = <String>['نوع: $type'];
    if (subject.isNotEmpty) fallback.add(type == 'کیفری' ? 'اتهام: $subject' : 'خواسته: $subject');
    final client = (item.clientName ?? '').trim();
    if (client.isNotEmpty) fallback.add('موکل من: $client');
    return fallback.join('\n');
  }
}

class CasesScreen extends ConsumerWidget {
  const CasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          children: [
            Text('پرونده‌ها'),
            SizedBox(width: 10),
            Expanded(child: GlobalSearchField()),
          ],
        ),
        actions: const [GlobalSettingsButton()],
      ),
      body: StreamBuilder<List<Case>>(
        stream: db.select(db.cases).watch(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('در دریافت فهرست پرونده‌ها خطا رخ داد. دوباره تلاش کنید.'));
          }
          final cases = List<Case>.of(snapshot.data ?? const <Case>[]);
          cases.sort((a, b) {
            final activeCompare = (_isCaseActive(a) ? 0 : 1).compareTo(_isCaseActive(b) ? 0 : 1);
            if (activeCompare != 0) return activeCompare;
            return b.createdAt.compareTo(a.createdAt);
          });

          return StreamBuilder<List<CasePerson>>(
            stream: db.select(db.casePeople).watch(),
            builder: (context, peopleSnapshot) {
              final allPeople = List<CasePerson>.of(peopleSnapshot.data ?? const <CasePerson>[]);
              final peopleByCase = <int, List<CasePerson>>{};
              for (final person in allPeople) {
                peopleByCase.putIfAbsent(person.caseId, () => <CasePerson>[]).add(person);
              }

              final bottom = MediaQuery.of(context).padding.bottom;
              return ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 128 + bottom),
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _AddCaseScreen(db: db))),
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن پرونده'),
                  ),
                  const SizedBox(height: 12),
                  if (cases.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.gavel),
                        title: Text('هنوز پرونده‌ای ثبت نشده است.'),
                        subtitle: Text('برای شروع، از دکمه «افزودن پرونده» استفاده کنید.'),
                      ),
                    )
                  else
                    ...cases.map((item) {
                      final people = peopleByCase[item.id] ?? const <CasePerson>[];
                      return _CaseListCard(
                        item: item,
                        people: people,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CaseDetailScreen(item: item)),
                        ),
                        actions: _CaseActionsMenu(
                          active: _isCaseActive(item),
                          onEdit: () => _editCase(context, db, item),
                          onToggleActive: () => _toggleCaseActive(context, db, item),
                          onDelete: () => _deleteCase(context, db, item),
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

  Future<void> _editCase(BuildContext context, AppDatabase db, Case item) async {
    final updated = await Navigator.push<Case>(
      context,
      MaterialPageRoute(builder: (_) => EditCaseScreen(db: db, item: item)),
    );
    if (updated != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تغییرات پرونده ذخیره شد.')));
    }
  }

  Future<void> _toggleCaseActive(BuildContext context, AppDatabase db, Case item) async {
    final currentlyActive = _isCaseActive(item);
    final nextStatus = currentlyActive ? 'غیرفعال' : 'فعال';
    final title = currentlyActive ? 'غیرفعال‌کردن پرونده' : 'فعال‌کردن پرونده';
    final message = currentlyActive
        ? 'پرونده «${item.title}» از فهرست پرونده‌های فعال خارج شود؟ اطلاعات پرونده حذف نمی‌شود.'
        : 'پرونده «${item.title}» دوباره به فهرست پرونده‌های فعال برگردد؟';
    final confirmLabel = currentlyActive ? 'غیرفعال شود' : 'فعال شود';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(confirmLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.update(db.cases).replace(item.copyWith(status: nextStatus));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(currentlyActive ? 'پرونده غیرفعال شد.' : 'پرونده فعال شد.')));
    }
  }

  Future<void> _deleteCase(BuildContext context, AppDatabase db, Case item) async {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرونده حذف شد.')));
    }
  }

}


bool _isCaseActive(Case item) {
  final status = item.status.trim();
  return status.isEmpty || status == 'فعال' || status.contains('نیازمند') || status.contains('پیگیری');
}

String _shortCaseNumber(Case item) {
  final caseNumber = (item.caseNumber ?? '').trim();
  if (caseNumber.isNotEmpty) return 'پرونده $caseNumber';
  final archive = (item.archiveNumber ?? '').trim();
  if (archive.isNotEmpty) return 'بایگانی $archive';
  return 'شماره ثبت نشده';
}

class _CaseListCard extends StatelessWidget {
  const _CaseListCard({
    required this.item,
    required this.people,
    required this.onTap,
    required this.actions,
  });

  final Case item;
  final List<CasePerson> people;
  final VoidCallback onTap;
  final Widget actions;

  String _mainTitle() => item.title.trim().isEmpty ? 'پرونده بدون نام' : item.title.trim();

  List<String> _detailLines() {
    final raw = _safeCaseListSubtitleText(item, people).split('\n');
    return raw.where((line) => line.trim().isNotEmpty).take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final type = item.caseType == 'کیفری' ? 'کیفری' : 'حقوقی';
    final stage = (item.stage ?? '').trim();
    final status = item.status.trim().isEmpty ? 'فعال' : item.status.trim();
    final active = _isCaseActive(item);
    final lines = _detailLines();
    final nextAction = (item.nextAction ?? '').trim();
    final secondaryTextColor = scheme.onSurfaceVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withOpacity(.55),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Icon(type == 'کیفری' ? Icons.balance : Icons.gavel, color: scheme.primary, size: 21),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _mainTitle(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _shortCaseNumber(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: secondaryTextColor, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          _StatusLamp(active: active),
                          const SizedBox(width: 4),
                          actions,
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _CasePill(label: type),
                          if (stage.isNotEmpty) _CasePill(label: stage),
                          _CasePill(label: status),
                        ],
                      ),
                      if (lines.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        ...lines.map((line) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: secondaryTextColor)),
                            )),
                      ],
                      if (nextAction.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withOpacity(.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orangeAccent.withOpacity(.25)),
                          ),
                          child: Text('اقدام بعدی: $nextAction', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CasePill extends StatelessWidget {
  const _CasePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 11.5)),
    );
  }
}

class _StatusLamp extends StatelessWidget {
  const _StatusLamp({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.green : Colors.blueGrey;
    return Tooltip(
      message: active ? 'پرونده فعال' : 'پرونده غیرفعال یا مختومه',
      child: Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: active ? [BoxShadow(color: color.withOpacity(.45), blurRadius: 7, spreadRadius: 1)] : null,
          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.4),
        ),
      ),
    );
  }
}

class _CaseActionsMenu extends StatelessWidget {
  const _CaseActionsMenu({
    required this.active,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'عملیات پرونده',
      onSelected: (value) {
        if (value == 'edit') {
          onEdit();
        } else if (value == 'toggleActive') {
          onToggleActive();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('ویرایش پرونده')),
        PopupMenuItem(value: 'toggleActive', child: Text(active ? 'غیرفعال‌کردن پرونده' : 'فعال‌کردن پرونده')),
        const PopupMenuItem(value: 'delete', child: Text('حذف پرونده')),
      ],
    );
  }
}

class _AddCaseScreen extends StatefulWidget {
  const _AddCaseScreen({required this.db});

  final AppDatabase db;

  @override
  State<_AddCaseScreen> createState() => _AddCaseScreenState();
}

class _AddCaseScreenState extends State<_AddCaseScreen> {
  final titleController = TextEditingController();
  final claimOrChargeController = TextEditingController();
  final courtController = TextEditingController();
  final branchController = TextEditingController();
  final judgeController = TextEditingController();
  final caseNumberController = TextEditingController();
  final archiveNumberController = TextEditingController();
  final stageController = TextEditingController();
  final currentRoleController = TextEditingController();
  final nextActionController = TextEditingController();
  final feeTotalController = TextEditingController();
  final feeNotesController = TextEditingController();

  String caseType = 'حقوقی';
  String status = 'فعال';
  bool feeReceived = false;

  static const caseStatusOptions = [
    'فعال',
    'نیازمند پیگیری',
    'متوقف',
    'مختومه',
    'غیرفعال',
    'سایر / ثبت دستی',
  ];
  DateTime feeReceivedDate = DateTime.now();

  static const legalStages = [
    'دستور موقت',
    'تأمین خواسته',
    'اعسار از پرداخت هزینه دادرسی بدوی',
    'رسیدگی بدوی',
    'اعسار از هزینه دادرسی واخواهی',
    'رسیدگی واخواهی',
    'اعسار از هزینه دادرسی تجدیدنظر',
    'رسیدگی تجدیدنظر',
    'اعسار از هزینه دادرسی فرجام‌خواهی',
    'فرجام‌خواهی',
    'اعاده دادرسی',
    'اعتراض ثالث',
    'اعسار از محکوم‌به',
    'اجرای احکام',
    'سایر / ثبت دستی',
  ];

  static const criminalStages = [
    'تحقیقات مقدماتی',
    'دادیاری',
    'بازپرسی',
    'دادگاه کیفری',
    'واخواهی کیفری',
    'تجدیدنظر کیفری',
    'فرجام‌خواهی کیفری',
    'اعاده دادرسی کیفری',
    'اجرای احکام کیفری',
    'سایر / ثبت دستی',
  ];

  static const currentRoleOptions = {
    'رسیدگی تجدیدنظر': ['تجدیدنظرخواه', 'تجدیدنظرخوانده'],
    'اعسار از هزینه دادرسی تجدیدنظر': ['متقاضی اعسار تجدیدنظر', 'خوانده اعسار تجدیدنظر'],
    'فرجام‌خواهی': ['فرجام‌خواه', 'فرجام‌خوانده'],
    'اعسار از هزینه دادرسی فرجام‌خواهی': ['متقاضی اعسار فرجام', 'خوانده اعسار فرجام'],
    'اعاده دادرسی': ['متقاضی اعاده دادرسی', 'طرف مقابل اعاده دادرسی'],
    'اعتراض ثالث': ['معترض ثالث', 'طرف اعتراض ثالث'],
    'اعسار از محکوم‌به': ['متقاضی اعسار از محکوم‌به', 'خوانده اعسار از محکوم‌به'],
    'تأمین خواسته': ['متقاضی تأمین خواسته', 'طرف مقابل تأمین خواسته'],
    'دستور موقت': ['متقاضی دستور موقت', 'طرف مقابل دستور موقت'],
    'واخواهی کیفری': ['واخواه', 'واخوانده'],
    'تجدیدنظر کیفری': ['تجدیدنظرخواه', 'تجدیدنظرخوانده'],
    'فرجام‌خواهی کیفری': ['فرجام‌خواه', 'فرجام‌خوانده'],
    'اعاده دادرسی کیفری': ['متقاضی اعاده دادرسی', 'طرف مقابل اعاده دادرسی'],
  };

  final plaintiffs = <_PartyInput>[_PartyInput(role: 'خواهان')];
  final defendants = <_PartyInput>[_PartyInput(role: 'خوانده')];
  final complainants = <_PartyInput>[_PartyInput(role: 'شاکی')];
  final accused = <_PartyInput>[_PartyInput(role: 'متهم')];

  @override
  void dispose() {
    titleController.dispose();
    claimOrChargeController.dispose();
    courtController.dispose();
    branchController.dispose();
    judgeController.dispose();
    caseNumberController.dispose();
    archiveNumberController.dispose();
    stageController.dispose();
    currentRoleController.dispose();
    nextActionController.dispose();
    feeTotalController.dispose();
    feeNotesController.dispose();
    for (final list in [plaintiffs, defendants, complainants, accused]) {
      for (final p in list) {
        p.dispose();
      }
    }
    super.dispose();
  }

  List<_PartyInput> get activeParties => caseType == 'حقوقی' ? [...plaintiffs, ...defendants] : [...complainants, ...accused];

  List<_PartyInput> get clients => activeParties.where((p) => p.isClient && p.name.trim().isNotEmpty).toList();

  List<String> get _stageOptions => caseType == 'حقوقی' ? legalStages : criminalStages;

  String? get _mainClientRole {
    final roles = clients.map((p) => p.role).toSet();
    return roles.length == 1 ? roles.first : null;
  }

  List<String> get _currentRoleOptions => currentRoleOptions[stageController.text.trim()] ?? const <String>[];

  String _resolvedCurrentRole() {
    final stage = stageController.text.trim();
    final mainRole = _mainClientRole;
    if (stage.isEmpty) return _clientRoles();
    if (caseType == 'حقوقی') {
      if (stage == 'رسیدگی بدوی' || stage == 'اجرای احکام') return _clientRoles();
      if (stage == 'رسیدگی واخواهی') {
        if (mainRole == 'خوانده') return 'واخواه';
        if (mainRole == 'خواهان') return 'واخوانده';
      }
      if (stage == 'اعسار از هزینه دادرسی واخواهی') {
        if (mainRole == 'خوانده') return 'متقاضی اعسار واخواهی / واخواه';
        if (mainRole == 'خواهان') return 'خوانده اعسار واخواهی / واخوانده';
      }
      if (stage == 'اعسار از پرداخت هزینه دادرسی بدوی') {
        if (mainRole == 'خواهان') return 'متقاضی اعسار از هزینه دادرسی بدوی';
        if (mainRole == 'خوانده') return 'خوانده اعسار از هزینه دادرسی بدوی';
      }
    }
    return currentRoleController.text.trim().isEmpty ? _clientRoles() : currentRoleController.text.trim();
  }

  void _setPartyClient(_PartyInput party, bool value) {
    if (value) {
      final opposite = caseType == 'حقوقی'
          ? (party.role == 'خواهان' ? defendants : plaintiffs)
          : (party.role == 'شاکی' ? accused : complainants);
      for (final p in opposite) {
        p.isClient = false;
      }
      currentRoleController.clear();
    }
    party.isClient = value;
  }

  String _autoTitle() {
    final names = clients.map((p) => p.name.trim()).where((e) => e.isNotEmpty).toList();
    if (names.isEmpty) return '';
    return 'پرونده ${names.take(2).join(' و ')}${names.length > 2 ? ' و دیگران' : ''}';
  }

  String _clientRoles() {
    final roles = clients.map((p) => p.role).toSet().toList();
    return roles.join('، ');
  }

  String _opponents() {
    return activeParties.where((p) => !p.isClient && p.name.trim().isNotEmpty).map((p) => p.name.trim()).join('، ');
  }

  Future<void> _save() async {
    final selectedClients = clients;
    if (selectedClients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای ثبت پرونده، حداقل نام یک موکل را وارد و تیک «موکل من است» را فعال کنید.')),
      );
      return;
    }

    if (_currentRoleOptions.isNotEmpty && currentRoleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سمت موکل در این مرحله را انتخاب کنید.')),
      );
      return;
    }

    final finalTitle = titleController.text.trim().isEmpty ? _autoTitle() : titleController.text.trim();
    final clientNames = selectedClients.map((p) => p.name.trim()).join('، ');
    final subject = claimOrChargeController.text.trim();
    final roleText = _clientRoles();
    final currentRoleText = _resolvedCurrentRole();

    final caseId = await widget.db.into(widget.db.cases).insert(
          CasesCompanion.insert(
            title: finalTitle,
            clientName: Value(clientNames),
            opponentName: Value(_opponents()),
            subject: Value(subject),
            caseType: Value(caseType),
            court: Value(courtController.text.trim()),
            branch: const Value(''),
            judge: Value(judgeController.text.trim()),
            caseNumber: Value(caseNumberController.text.trim()),
            archiveNumber: Value(archiveNumberController.text.trim()),
            stage: Value(stageController.text.trim()),
            clientRole: Value(roleText),
            currentRole: Value(currentRoleText),
            status: Value(status),
            nextAction: Value(nextActionController.text.trim()),
          ),
        );

    for (final party in activeParties.where((p) => p.name.trim().isNotEmpty)) {
      await widget.db.into(widget.db.casePeople).insert(
            CasePeopleCompanion.insert(
              caseId: caseId,
              name: party.name.trim(),
              role: Value(party.role),
              notes: Value(party.isClient ? 'موکل من' : null),
            ),
          );
    }

    final totalFee = parseMoney(feeTotalController.text);
    if (totalFee != null && totalFee > 0) {
      await widget.db.into(widget.db.financeItems).insert(
            FinanceItemsCompanion.insert(
              caseId: Value(caseId),
              type: 'حق‌الوکاله توافقی',
              title: 'حق‌الوکاله کل توافقی',
              amount: totalFee,
              category: const Value('حق‌الوکاله'),
              date: Value(DateTime.now()),
              notes: const Value('ثبت کل حق‌الوکاله هنگام ثبت پرونده'),
            ),
          );
      if (feeReceived) {
        await widget.db.into(widget.db.financeItems).insert(
              FinanceItemsCompanion.insert(
                caseId: Value(caseId),
                type: 'حق‌الوکاله دریافتی',
                title: 'حق‌الوکاله دریافتی',
                amount: totalFee,
                category: const Value('حق‌الوکاله'),
                date: Value(feeReceivedDate),
                notes: Value(feeNotesController.text.trim()),
              ),
            );
      }
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پرونده ثبت شد.')));
  }

  @override
  Widget build(BuildContext context) {
    final isLegal = caseType == 'حقوقی';
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت پرونده جدید'), actions: const [GlobalSettingsButton()]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 120 + MediaQuery.of(context).padding.bottom),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('اطلاعات اصلی', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'حقوقی', label: Text('حقوقی')),
                      ButtonSegment(value: 'کیفری', label: Text('کیفری')),
                    ],
                    selected: {caseType},
                    onSelectionChanged: (v) => setState(() { caseType = v.first; stageController.clear(); currentRoleController.clear(); }),
                  ),
                  const SizedBox(height: 12),
                  _field(titleController, 'نام پرونده، اختیاری', hint: 'اگر خالی بماند از نام موکل ساخته می‌شود.'),
                  _field(claimOrChargeController, isLegal ? 'خواسته' : 'اتهام'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isLegal) ...[
            _partySection(title: 'خواهان‌ها', parties: plaintiffs, role: 'خواهان'),
            _partySection(title: 'خوانده‌ها', parties: defendants, role: 'خوانده'),
          ] else ...[
            _partySection(title: 'شاکی / شاکیان', parties: complainants, role: 'شاکی'),
            _partySection(title: 'متهم / متهمان', parties: accused, role: 'متهم'),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('مشخصات تکمیلی', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _field(courtController, 'شعبه و مرجع رسیدگی', hint: 'مثلاً: شعبه اول دادگاه عمومی حقوقی شهرستان تهران'),
                  _field(judgeController, 'قاضی'),
                  _field(caseNumberController, 'شماره پرونده'),
                  _field(archiveNumberController, 'شماره بایگانی'),
                  _stageField(),
                  if (_currentRoleOptions.isNotEmpty) _currentRoleField(),
                  _statusField(),
                  const SizedBox(height: 12),
                  _field(nextActionController, 'اقدام بعدی، اختیاری'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _initialFeeSection(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('ذخیره پرونده'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
      ),
    );
  }

  Future<String?> _pickSearchableChoice({
    required String title,
    required String searchLabel,
    required String hint,
    required List<String> options,
    required String currentValue,
    bool allowCustom = true,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final trimmed = query.trim();
            final filtered = options.where((e) => trimmed.isEmpty || e.contains(trimmed)).toList();
            final exact = options.any((e) => e == trimmed);
            final bottom = MediaQuery.of(sheetContext).padding.bottom;
            final insets = MediaQuery.of(sheetContext).viewInsets.bottom;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, insets + bottom + 16),
                child: SizedBox(
                  height: MediaQuery.of(sheetContext).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: searchLabel,
                          hintText: hint,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: (value) => setSheetState(() => query = value),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty && (!allowCustom || trimmed.isEmpty)
                            ? const Center(child: Text('موردی پیدا نشد.'))
                            : ListView(
                                children: [
                                  ...filtered.map((option) => ListTile(
                                        title: Text(option),
                                        trailing: option == currentValue ? const Icon(Icons.check) : null,
                                        onTap: () => Navigator.pop(sheetContext, option),
                                      )),
                                  if (allowCustom && trimmed.isNotEmpty && !exact)
                                    ListTile(
                                      leading: const Icon(Icons.add),
                                      title: Text('ثبت «$trimmed» به‌عنوان مورد جدید'),
                                      onTap: () => Navigator.pop(sheetContext, trimmed),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    return selected;
  }

  Future<void> _pickStage() async {
    final selected = await _pickSearchableChoice(
      title: 'انتخاب مرحله رسیدگی',
      searchLabel: 'جستجو یا ثبت مرحله رسیدگی',
      hint: 'مثلاً اعسار، تجدیدنظر، دستور موقت',
      options: _stageOptions,
      currentValue: stageController.text.trim(),
    );
    if (selected != null) {
      setState(() {
        stageController.text = selected;
        currentRoleController.clear();
      });
    }
  }

  Future<void> _pickStatus() async {
    final selected = await _pickSearchableChoice(
      title: 'انتخاب وضعیت پرونده',
      searchLabel: 'جستجو یا ثبت وضعیت پرونده',
      hint: 'مثلاً فعال، مختومه، نیازمند پیگیری',
      options: caseStatusOptions,
      currentValue: status,
    );
    if (selected != null && selected.trim().isNotEmpty) {
      setState(() => status = selected.trim());
    }
  }

  Future<void> _pickCurrentRole() async {
    final options = _currentRoleOptions;
    final selected = await _pickSearchableChoice(
      title: 'انتخاب سمت موکل در این مرحله',
      searchLabel: 'جستجو یا ثبت سمت موکل',
      hint: 'مثلاً تجدیدنظرخواه یا تجدیدنظرخوانده',
      options: options,
      currentValue: currentRoleController.text.trim(),
    );
    if (selected != null && selected.trim().isNotEmpty) {
      setState(() => currentRoleController.text = selected.trim());
    }
  }

  Widget _stageField() {
    final value = stageController.text.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: _pickStage,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'مرحله رسیدگی',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.search),
          ),
          child: Text(value.isEmpty ? 'انتخاب مرحله رسیدگی' : value),
        ),
      ),
    );
  }

  Widget _currentRoleField() {
    final value = currentRoleController.text.trim();
    return _choiceDecorator(
      label: 'سمت موکل در این مرحله',
      value: value.isEmpty ? 'انتخاب سمت موکل' : value,
      onTap: _pickCurrentRole,
    );
  }

  Widget _statusField() {
    return _choiceDecorator(
      label: 'وضعیت پرونده',
      value: status.isEmpty ? 'انتخاب وضعیت پرونده' : status,
      onTap: _pickStatus,
    );
  }

  Widget _choiceDecorator({required String label, required String value, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.search),
          ),
          child: Text(value),
        ),
      ),
    );
  }

  Widget _initialFeeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('حق‌الوکاله / قرارداد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: feeTotalController,
              keyboardType: TextInputType.number,
              inputFormatters: [const MoneyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'مبلغ کل قرارداد / کل حق‌الوکاله',
                hintText: 'مثلاً ۲۰.۰۰۰.۰۰۰',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              value: feeReceived,
              contentPadding: EdgeInsets.zero,
              title: const Text('دریافت شد'),
              subtitle: const Text('اگر فعال باشد، همین مبلغ به‌عنوان حق‌الوکاله دریافتی هم ثبت می‌شود.'),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(() => feeReceived = value ?? false),
            ),
            if (feeReceived) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تاریخ دریافت'),
                subtitle: Text(formatPersianLongDate(feeReceivedDate)),
                trailing: const Icon(Icons.calendar_month),
                onTap: _pickFeeReceivedDate,
              ),
              TextField(
                controller: feeNotesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'توضیحات دریافت، اختیاری', border: OutlineInputBorder()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickFeeReceivedDate() async {
    final picked = await pickPersianDate(
      context,
      initialDate: feeReceivedDate,
      title: 'انتخاب تاریخ دریافت',
    );
    if (picked != null) setState(() => feeReceivedDate = picked);
  }

  Widget _partySection({required String title, required List<_PartyInput> parties, required String role}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                TextButton.icon(
                  onPressed: () => setState(() => parties.add(_PartyInput(role: role))),
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < parties.length; i++)
              _partyCard(parties: parties, index: i),
          ],
        ),
      ),
    );
  }

  Widget _partyCard({required List<_PartyInput> parties, required int index}) {
    final party = parties[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextField(
              controller: party.nameController,
              decoration: InputDecoration(
                labelText: '${party.role} ${index + 1}',
                hintText: 'نام شخص را وارد کنید',
                border: const OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              value: party.isClient,
              contentPadding: EdgeInsets.zero,
              title: const Text('موکل من است'),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(() => _setPartyClient(party, value ?? false)),
            ),
            if (parties.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    final removed = parties.removeAt(index);
                    removed.dispose();
                  }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف این شخص'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartyInput {
  _PartyInput({required this.role});

  final String role;
  final TextEditingController nameController = TextEditingController();
  bool isClient = false;

  String get name => nameController.text;

  void dispose() => nameController.dispose();
}
