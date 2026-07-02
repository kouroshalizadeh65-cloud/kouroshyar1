import 'package:flutter/material.dart';
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
  late final TextEditingController clientName;
  late final TextEditingController opponentName;
  late final TextEditingController subject;
  late final TextEditingController court;
  late final TextEditingController branch;
  late final TextEditingController judge;
  late final TextEditingController caseNumber;
  late final TextEditingController stage;
  late final TextEditingController clientRole;
  late final TextEditingController currentRole;
  late final TextEditingController nextAction;

  final roleOptions = const [
    'خواهان',
    'خوانده',
    'شاکی',
    'متهم',
    'تجدیدنظرخواه',
    'تجدیدنظرخوانده',
    'محکوم‌له',
    'محکوم‌علیه',
    'معترض ثالث',
    'وارد ثالث',
    'جالب ثالث',
    'ذی‌نفع',
    'سایر',
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    title = TextEditingController(text: i.title);
    clientName = TextEditingController(text: i.clientName ?? '');
    opponentName = TextEditingController(text: i.opponentName ?? '');
    subject = TextEditingController(text: i.subject ?? '');
    court = TextEditingController(text: i.court ?? '');
    branch = TextEditingController(text: i.branch ?? '');
    judge = TextEditingController(text: i.judge ?? '');
    caseNumber = TextEditingController(text: i.caseNumber ?? '');
    stage = TextEditingController(text: i.stage ?? '');
    clientRole = TextEditingController(text: i.clientRole ?? '');
    currentRole = TextEditingController(text: i.currentRole ?? '');
    nextAction = TextEditingController(text: i.nextAction ?? '');
  }

  @override
  void dispose() {
    title.dispose();
    clientName.dispose();
    opponentName.dispose();
    subject.dispose();
    court.dispose();
    branch.dispose();
    judge.dispose();
    caseNumber.dispose();
    stage.dispose();
    clientRole.dispose();
    currentRole.dispose();
    nextAction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ویرایش پرونده')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          _field(title, 'عنوان پرونده'),
          _field(clientName, 'نام موکل'),
          _field(opponentName, 'طرف مقابل'),
          _field(subject, 'موضوع'),
          _field(court, 'مرجع قضایی'),
          _field(branch, 'شعبه'),
          _field(judge, 'قاضی'),
          _field(caseNumber, 'شماره پرونده'),
          _field(stage, 'مرحله رسیدگی'),
          _roleField(clientRole, 'سمت موکل در دعوای اصلی'),
          _roleField(currentRole, 'سمت موکل در مرحله فعلی'),
          _field(nextAction, 'اقدام بعدی؛ اختیاری'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('ذخیره تغییرات'),
          ),
        ],
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

  Widget _roleField(TextEditingController controller, String label) {
    final value = roleOptions.contains(controller.text.trim()) ? controller.text.trim() : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: roleOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => controller.text = v ?? '',
      ),
    );
  }

  Future<void> _save() async {
    final updated = widget.item.copyWith(
      title: title.text.trim(),
      clientName: Value(clientName.text.trim()),
      opponentName: Value(opponentName.text.trim()),
      subject: Value(subject.text.trim()),
      court: Value(court.text.trim()),
      branch: Value(branch.text.trim()),
      judge: Value(judge.text.trim()),
      caseNumber: Value(caseNumber.text.trim()),
      stage: Value(stage.text.trim()),
      clientRole: Value(clientRole.text.trim()),
      currentRole: Value(currentRole.text.trim()),
      nextAction: Value(nextAction.text.trim()),
    );

    await widget.db.update(widget.db.cases).replace(updated);

    if (!mounted) return;
    Navigator.pop(context, updated);
  }
}
