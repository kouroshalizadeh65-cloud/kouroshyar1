import 'package:flutter/material.dart';

import '../../core/widgets/global_settings_button.dart';
import '../../database/app_database.dart';

class EditCaseScreen extends StatefulWidget {
  final AppDatabase db;
  final Case item;

  const EditCaseScreen({
    super.key,
    required this.db,
    required this.item,
  });

  @override
  State<EditCaseScreen> createState() => _EditCaseScreenState();
}

class _EditCaseScreenState extends State<EditCaseScreen> {
  late final TextEditingController title;
  late final TextEditingController subject;
  late final TextEditingController court;
  late final TextEditingController judge;
  late final TextEditingController caseNumber;
  late final TextEditingController archiveNumber;
  late final TextEditingController stage;
  late final TextEditingController currentRole;
  late final TextEditingController nextAction;

  String caseType = 'حقوقی';
  String status = 'فعال';
  bool _peopleLoaded = false;

  static const caseStatusOptions = [
    'فعال',
    'نیازمند پیگیری',
    'متوقف',
    'مختومه',
    'غیرفعال',
    'سایر / ثبت دستی',
  ];

  final plaintiffs = <_PartyInput>[];
  final defendants = <_PartyInput>[];
  final complainants = <_PartyInput>[];
  final accused = <_PartyInput>[];

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

  List<_PartyInput> get activeParties => caseType == 'حقوقی' ? [...plaintiffs, ...defendants] : [...complainants, ...accused];

  List<_PartyInput> get clients => activeParties.where((p) => p.isClient && p.name.trim().isNotEmpty).toList();

  List<String> get _stageOptions => caseType == 'حقوقی' ? legalStages : criminalStages;

  String? get _mainClientRole {
    final roles = clients.map((p) => p.role).toSet();
    return roles.length == 1 ? roles.first : null;
  }

  List<String> get _currentRoleOptions => currentRoleOptions[stage.text.trim()] ?? const <String>[];

  String _clientRoles() {
    final roles = clients.map((p) => p.role).toSet().toList();
    return roles.join('، ');
  }

  String _opponents() {
    return activeParties.where((p) => !p.isClient && p.name.trim().isNotEmpty).map((p) => p.name.trim()).join('، ');
  }

  String _resolvedCurrentRole() {
    final st = stage.text.trim();
    final mainRole = _mainClientRole;
    if (st.isEmpty) return _clientRoles();
    if (caseType == 'حقوقی') {
      if (st == 'رسیدگی بدوی' || st == 'اجرای احکام') return _clientRoles();
      if (st == 'رسیدگی واخواهی') {
        if (mainRole == 'خوانده') return 'واخواه';
        if (mainRole == 'خواهان') return 'واخوانده';
      }
      if (st == 'اعسار از هزینه دادرسی واخواهی') {
        if (mainRole == 'خوانده') return 'متقاضی اعسار واخواهی / واخواه';
        if (mainRole == 'خواهان') return 'خوانده اعسار واخواهی / واخوانده';
      }
      if (st == 'اعسار از پرداخت هزینه دادرسی بدوی') {
        if (mainRole == 'خواهان') return 'متقاضی اعسار از هزینه دادرسی بدوی';
        if (mainRole == 'خوانده') return 'خوانده اعسار از هزینه دادرسی بدوی';
      }
    }
    return currentRole.text.trim().isEmpty ? _clientRoles() : currentRole.text.trim();
  }

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    title = TextEditingController(text: i.title);
    subject = TextEditingController(text: i.subject ?? '');
    court = TextEditingController(text: _courtText(i));
    judge = TextEditingController(text: i.judge ?? '');
    caseNumber = TextEditingController(text: i.caseNumber ?? '');
    archiveNumber = TextEditingController(text: i.archiveNumber ?? '');
    stage = TextEditingController(text: i.stage ?? '');
    currentRole = TextEditingController(text: i.currentRole ?? '');
    nextAction = TextEditingController(text: i.nextAction ?? '');
    caseType = i.caseType == 'کیفری' ? 'کیفری' : 'حقوقی';
    status = i.status.isEmpty ? 'فعال' : i.status;
    _loadPeople();
  }

  String _courtText(Case item) {
    final courtValue = (item.court ?? '').trim();
    final branch = (item.branch ?? '').trim();
    if (courtValue.isEmpty) return branch;
    if (branch.isEmpty || courtValue.contains(branch)) return courtValue;
    return '$courtValue - $branch';
  }

  Future<void> _loadPeople() async {
    final rows = await (widget.db.select(widget.db.casePeople)..where((p) => p.caseId.equals(widget.item.id))).get();
    if (!mounted) return;
    setState(() {
      _clearPartyLists();
      if (rows.isNotEmpty) {
        for (final person in rows) {
          final party = _PartyInput(role: person.role);
          party.nameController.text = person.name;
          party.isClient = (person.notes ?? '').contains('موکل');
          _listForRole(person.role).add(party);
        }
      } else {
        _loadFallbackPeople();
      }
      _ensureDefaultPartyRows();
      _peopleLoaded = true;
    });
  }

  void _clearPartyLists() {
    for (final list in [plaintiffs, defendants, complainants, accused]) {
      for (final p in list) {
        p.dispose();
      }
      list.clear();
    }
  }

  void _loadFallbackPeople() {
    final client = widget.item.clientName?.trim() ?? '';
    final opponent = widget.item.opponentName?.trim() ?? '';
    final role = widget.item.clientRole?.trim() ?? '';
    if (caseType == 'حقوقی') {
      if (role.contains('خوانده')) {
        _addParty(defendants, 'خوانده', client, true);
        _addParty(plaintiffs, 'خواهان', opponent, false);
      } else {
        _addParty(plaintiffs, 'خواهان', client, true);
        _addParty(defendants, 'خوانده', opponent, false);
      }
    } else {
      if (role.contains('متهم')) {
        _addParty(accused, 'متهم', client, true);
        _addParty(complainants, 'شاکی', opponent, false);
      } else {
        _addParty(complainants, 'شاکی', client, true);
        _addParty(accused, 'متهم', opponent, false);
      }
    }
  }

  void _addParty(List<_PartyInput> list, String role, String name, bool isClient) {
    final party = _PartyInput(role: role);
    party.nameController.text = name;
    party.isClient = isClient && name.trim().isNotEmpty;
    list.add(party);
  }

  List<_PartyInput> _listForRole(String role) {
    switch (role) {
      case 'خواهان':
        return plaintiffs;
      case 'خوانده':
        return defendants;
      case 'شاکی':
        return complainants;
      case 'متهم':
        return accused;
      default:
        return caseType == 'حقوقی' ? plaintiffs : complainants;
    }
  }

  void _ensureDefaultPartyRows() {
    if (plaintiffs.isEmpty) plaintiffs.add(_PartyInput(role: 'خواهان'));
    if (defendants.isEmpty) defendants.add(_PartyInput(role: 'خوانده'));
    if (complainants.isEmpty) complainants.add(_PartyInput(role: 'شاکی'));
    if (accused.isEmpty) accused.add(_PartyInput(role: 'متهم'));
  }

  @override
  void dispose() {
    title.dispose();
    subject.dispose();
    court.dispose();
    judge.dispose();
    caseNumber.dispose();
    archiveNumber.dispose();
    stage.dispose();
    currentRole.dispose();
    nextAction.dispose();
    _clearPartyLists();
    super.dispose();
  }

  void _setPartyClient(_PartyInput party, bool value) {
    if (value) {
      final opposite = caseType == 'حقوقی'
          ? (party.role == 'خواهان' ? defendants : plaintiffs)
          : (party.role == 'شاکی' ? accused : complainants);
      for (final p in opposite) {
        p.isClient = false;
      }
      currentRole.clear();
    }
    party.isClient = value;
  }

  @override
  Widget build(BuildContext context) {
    if (!_peopleLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('ویرایش پرونده'), actions: const [GlobalSettingsButton()]),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isLegal = caseType == 'حقوقی';
    return Scaffold(
      appBar: AppBar(title: const Text('ویرایش پرونده'), actions: const [GlobalSettingsButton()]),
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
                    onSelectionChanged: (v) => setState(() {
                      caseType = v.first;
                      stage.clear();
                      currentRole.clear();
                      _ensureDefaultPartyRows();
                    }),
                  ),
                  const SizedBox(height: 12),
                  _field(title, 'نام پرونده / عنوان نمایشی'),
                  _field(subject, isLegal ? 'خواسته' : 'اتهام'),
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
                  _field(court, 'شعبه و مرجع رسیدگی'),
                  _field(judge, 'قاضی'),
                  _field(caseNumber, 'شماره پرونده'),
                  _field(archiveNumber, 'شماره بایگانی'),
                  _stageField(),
                  if (_currentRoleOptions.isNotEmpty) _currentRoleField(),
                  _statusField(),
                  const SizedBox(height: 12),
                  _field(nextAction, 'اقدام بعدی؛ اختیاری'),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('ذخیره تغییرات'),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
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
      currentValue: stage.text.trim(),
    );
    if (selected != null) {
      setState(() {
        stage.text = selected;
        currentRole.clear();
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
    final selected = await _pickSearchableChoice(
      title: 'انتخاب سمت موکل در این مرحله',
      searchLabel: 'جستجو یا ثبت سمت موکل',
      hint: 'مثلاً تجدیدنظرخواه یا تجدیدنظرخوانده',
      options: _currentRoleOptions,
      currentValue: currentRole.text.trim(),
    );
    if (selected != null && selected.trim().isNotEmpty) {
      setState(() => currentRole.text = selected.trim());
    }
  }

  Widget _stageField() {
    final value = stage.text.trim();
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
    final value = currentRole.text.trim();
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

  Future<void> _save() async {
    final selectedClients = clients;
    if (selectedClients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای ذخیره پرونده، حداقل نام یک موکل را وارد و تیک «موکل من است» را فعال کنید.')),
      );
      return;
    }

    if (_currentRoleOptions.isNotEmpty && currentRole.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سمت موکل در این مرحله را انتخاب کنید.')));
      return;
    }

    final clientNames = selectedClients.map((p) => p.name.trim()).join('، ');
    final name = title.text.trim().isEmpty ? 'پرونده $clientNames' : title.text.trim();

    final updated = widget.item.copyWith(
      title: name,
      clientName: Value(clientNames),
      opponentName: Value(_opponents()),
      subject: Value(subject.text.trim()),
      caseType: Value(caseType),
      court: Value(court.text.trim()),
      branch: const Value(''),
      judge: Value(judge.text.trim()),
      caseNumber: Value(caseNumber.text.trim()),
      archiveNumber: Value(archiveNumber.text.trim()),
      stage: Value(stage.text.trim()),
      clientRole: Value(_clientRoles()),
      currentRole: Value(_resolvedCurrentRole()),
      status: status,
      nextAction: Value(nextAction.text.trim()),
    );

    await widget.db.update(widget.db.cases).replace(updated);
    await (widget.db.delete(widget.db.casePeople)..where((p) => p.caseId.equals(widget.item.id))).go();
    for (final party in activeParties.where((p) => p.name.trim().isNotEmpty)) {
      await widget.db.into(widget.db.casePeople).insert(
            CasePeopleCompanion.insert(
              caseId: widget.item.id,
              name: party.name.trim(),
              role: Value(party.role),
              notes: Value(party.isClient ? 'موکل من' : null),
            ),
          );
    }

    if (!mounted) return;
    Navigator.pop(context, updated);
  }
}

class _PartyInput {
  _PartyInput({required this.role});

  final String role;
  final TextEditingController nameController = TextEditingController();
  bool isClient = false;

  String get name => nameController.text;

  void dispose() {
    nameController.dispose();
  }
}
