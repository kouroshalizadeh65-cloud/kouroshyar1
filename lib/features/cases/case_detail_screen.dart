import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/session/session_context.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../focus_mode/focus_mode_state.dart';
import 'ai/case_ai_screen.dart';
import 'documents/case_document_detail_screen.dart';
import 'drafts/case_draft_generator_screen.dart';
import 'edit_case_screen.dart';
import '../../core/widgets/global_search_button.dart';

class CaseDetailScreen extends ConsumerWidget {
  final Case item;

  const CaseDetailScreen({super.key, required this.item});

  static const List<String> documentTypes = [
    'دادخواست',
    'لایحه دفاعیه',
    'نظریه کارشناسی',
    'دادنامه',
    'قرار',
    'ابلاغیه',
    'قرارداد',
    'رسید پرداخت',
    'اظهارنامه',
    'وکالتنامه',
    'سند مالکیت',
    'صورتجلسه',
    'گزارش اصلاحی',
    'مدارک هویتی',
    'سایر',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    SessionContext.setLastCase(id: item.id, title: item.title);
    final nextAction = item.nextAction?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          const GlobalSearchButton(),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
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
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('خلاصه پرونده'),
              subtitle: Text(
                'مرحله: ${item.stage ?? 'ثبت نشده'}\n'
                'سمت اصلی موکل: ${item.clientRole ?? 'ثبت نشده'}\n'
                'سمت در مرحله فعلی: ${item.currentRole ?? 'ثبت نشده'}\n'
                'وضعیت: ${item.status}'
                '${nextAction.isEmpty ? '' : '\nاقدام بعدی: $nextAction'}',
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('مشخصات پرونده'),
              subtitle: Text(
                'موکل: ${item.clientName ?? 'ثبت نشده'}\n'
                'طرف مقابل: ${item.opponentName ?? 'ثبت نشده'}\n'
                'موضوع: ${item.subject ?? 'ثبت نشده'}\n'
                'مرجع: ${item.court ?? 'ثبت نشده'}\n'
                'شعبه: ${item.branch ?? 'ثبت نشده'}\n'
                'قاضی: ${item.judge ?? 'ثبت نشده'}\n'
                'شماره پرونده: ${item.caseNumber ?? 'ثبت نشده'}',
              ),
            ),
          ),
          if (nextAction.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'اقدام بعدی ثبت نشده است.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          _LegalCaseSnapshot(item: item, db: db),
          _CasePeopleSection(
            item: item,
            db: db,
            onAdd: () => _showCasePersonDialog(context, db),
            onEdit: (person) => _showCasePersonDialog(context, db, person: person),
            onDelete: (person) => _deleteCasePerson(context, db, person),
          ),
          _CaseFinanceSection(
            item: item,
            db: db,
            onAdd: () => _showCaseFinanceDialog(context, db),
            onEdit: (finance) => _showCaseFinanceDialog(context, db, item: finance),
            onDelete: (finance) => _deleteCaseFinance(context, db, finance),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.center_focus_strong),
              title: Text(FocusModeState.enabled && FocusModeState.caseId == item.id ? 'پایان حالت تمرکز' : 'حالت تمرکز'),
              subtitle: const Text('برای مدتی فقط روی همین پرونده تمرکز کن.'),
              onTap: () {
                if (FocusModeState.enabled && FocusModeState.caseId == item.id) {
                  FocusModeState.stop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حالت تمرکز پایان یافت')));
                } else {
                  FocusModeState.start(id: item.id, title: item.title);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حالت تمرکز روی ${item.title} فعال شد')));
                }
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description),
              title: const Text('تولید لایحه / دادخواست'),
              subtitle: const Text('تولید متن بر اساس اطلاعات پرونده و ذخیره در بانک متون'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseDraftGeneratorScreen(item: item))),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb),
              title: const Text('ثبت تجربه این پرونده'),
              subtitle: const Text('نتیجه، استراتژی مؤثر، اشتباهات و نکته برای آینده'),
              onTap: () => _addExperienceForCase(context, db),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('تحلیل پرونده'),
              subtitle: const Text('تحلیل و پیشنهاد دفاع بر اساس اطلاعات پرونده'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CaseAiScreen(item: item)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('مدارک و پیوست‌ها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _captureDocument(context, db),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('گرفتن عکس'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _pickDocumentFile(context, db),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('افزودن فایل'),
                ),
              ),
            ],
          ),
          StreamBuilder<List<CaseDocument>>(
            stream: (db.select(db.caseDocuments)..where((d) => d.caseId.equals(item.id))).watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(child: ListTile(title: Text('در دریافت مدارک پرونده خطا رخ داد. دوباره تلاش کنید.')));
              }
              final docs = List<CaseDocument>.of(snapshot.data ?? const <CaseDocument>[]);
              docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

              if (docs.isEmpty) {
                return const Card(child: ListTile(title: Text('مدرکی ثبت نشده است.')));
              }

              return Column(
                children: docs.map((d) {
                  return Card(
                    child: ListTile(
                      leading: Icon(d.filePath == null || d.filePath!.isEmpty ? Icons.note_alt : Icons.attach_file),
                      title: Text(d.title),
                      subtitle: Text('${d.documentType ?? 'سند'}${(d.notes ?? '').isEmpty ? '' : '\n${d.notes}'}'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CaseDocumentDetailScreen(document: d)),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text('خط زمان پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<List<CaseTimelineEvent>>(
            stream: (db.select(db.caseTimelineEvents)..where((e) => e.caseId.equals(item.id))).watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(child: ListTile(title: Text('در دریافت خط زمان پرونده خطا رخ داد. دوباره تلاش کنید.')));
              }

              final events = List<CaseTimelineEvent>.of(snapshot.data ?? const <CaseTimelineEvent>[]);
              try {
                events.sort((a, b) => b.eventDate.compareTo(a.eventDate));
              } catch (_) {
                return const Card(child: ListTile(title: Text('خط زمان نیاز به بازسازی دارد.')));
              }

              if (events.isEmpty) {
                return const Card(child: ListTile(title: Text('رویدادی ثبت نشده است.')));
              }

              return Column(
                children: events.map((e) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.timeline),
                      title: Text(e.title.isEmpty ? 'رویداد بدون عنوان' : e.title),
                      subtitle: Text('${e.eventType ?? 'رویداد'} | ${formatPersianLongDate(e.eventDate)}${(e.description ?? '').isEmpty ? '' : '\n${e.description}'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _editTimelineEvent(context, db, e);
                          } else if (value == 'delete') {
                            _deleteTimelineEvent(context, db, e);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text('کارهای پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<List<Task>>(
            stream: (db.select(db.tasks)..where((t) => t.caseId.equals(item.id))).watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Card(child: ListTile(title: Text('در دریافت کارهای پرونده خطا رخ داد. دوباره تلاش کنید.')));
              final tasks = List<Task>.of(snapshot.data ?? const <Task>[]);
              if (tasks.isEmpty) return const Card(child: ListTile(title: Text('کاری ثبت نشده است.')));

              return Column(
                children: tasks.map((task) {
                  return Card(
                    child: ListTile(
                      leading: Checkbox(
                        value: task.isDone,
                        onChanged: (value) async {
                          await db.update(db.tasks).replace(task.copyWith(isDone: value ?? false));
                        },
                      ),
                      title: Text(task.title),
                      subtitle: Text(_taskSubtitle(task)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _editTask(context, db, task);
                          } else if (value == 'delete') {
                            _deleteTask(context, db, task);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTask(context, db),
                  icon: const Icon(Icons.add_task),
                  label: const Text('افزودن کار'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _addTimelineEvent(context, db),
                  icon: const Icon(Icons.timeline),
                  label: const Text('رویداد'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _addDocumentManually(context, db),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('سند دستی'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  String _taskSubtitle(Task task) {
    final date = task.dueDate;
    if (date == null) return 'اولویت: ${task.priority}';
    return 'اولویت: ${task.priority} | ${formatPersianLongDate(date)}';
  }

  Future<DateTime?> _askCaseDate(BuildContext context, DateTime current, String title) async {
    final controller = TextEditingController(text: formatSimpleDate(current));
    return showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'تاریخ شمسی',
            helperText: 'مثال: ۱۴۰۵/۰۴/۲۰، امروز، فردا',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () {
              final parsed = parsePersianDateInput(controller.text);
              if (parsed == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاریخ معتبر نیست.')));
                return;
              }
              Navigator.pop(context, parsed);
            },
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
  }

  void _addTask(BuildContext context, AppDatabase db) {
    final controller = TextEditingController();
    DateTime selectedDate = DateTime.now();

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
                    const Text('افزودن کار پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'عنوان کار', border: OutlineInputBorder()),
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
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان کار را وارد کنید.')));
                                return;
                              }
                              await db.into(db.tasks).insert(
                                    TasksCompanion.insert(
                                      title: title,
                                      caseId: Value(item.id),
                                      dueDate: Value(selectedDate),
                                    ),
                                  );
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ثبت شد')));
                              }
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
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان کار را وارد کنید.')));
                                return;
                              }
                              await db.update(db.tasks).replace(
                                    task.copyWith(
                                      title: title,
                                      priority: priority,
                                      dueDate: Value(selectedDate),
                                    ),
                                  );
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تغییرات ذخیره شد')));
                              }
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
    await (db.delete(db.tasks)..where((t) => t.id.equals(task.id))).go();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حذف شد')));
    }
  }

  void _addTimelineEvent(BuildContext context, AppDatabase db) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String eventType = 'ثبت دستی';
    DateTime selectedDate = DateTime.now();

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
                    const Text('افزودن رویداد پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: eventType,
                      items: const ['ثبت دستی', 'جلسه', 'ابلاغیه', 'دادنامه', 'نظریه کارشناسی', 'لایحه', 'پیگیری', 'سایر']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => eventType = v ?? eventType),
                      decoration: const InputDecoration(labelText: 'نوع رویداد', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'عنوان رویداد', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ رویداد'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, 'تاریخ شمسی رویداد');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder()),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final title = titleController.text.trim();
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان رویداد را وارد کنید.')));
                                return;
                              }
                              await db.into(db.caseTimelineEvents).insert(
                                    CaseTimelineEventsCompanion.insert(
                                      caseId: item.id,
                                      title: title,
                                      eventType: Value(eventType),
                                      description: Value(descriptionController.text.trim()),
                                      eventDate: Value(selectedDate),
                                    ),
                                  );
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ثبت شد')));
                              }
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
    final titleController = TextEditingController(text: event.title);
    final descriptionController = TextEditingController(text: event.description ?? '');
    String eventType = event.eventType ?? 'ثبت دستی';
    const eventTypes = ['ثبت دستی', 'جلسه', 'ابلاغیه', 'دادنامه', 'نظریه کارشناسی', 'لایحه', 'پیگیری', 'سایر'];
    if (!eventTypes.contains(eventType)) eventType = 'سایر';
    DateTime selectedDate = event.eventDate;

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
                    const Text('ویرایش رویداد پرونده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: eventType,
                      items: eventTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => eventType = v ?? eventType),
                      decoration: const InputDecoration(labelText: 'نوع رویداد', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'عنوان رویداد', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ رویداد'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, 'تاریخ شمسی رویداد');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder()),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final title = titleController.text.trim();
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان رویداد را وارد کنید.')));
                                return;
                              }
                              await db.update(db.caseTimelineEvents).replace(
                                    CaseTimelineEvent(
                                      id: event.id,
                                      caseId: event.caseId,
                                      title: title,
                                      eventType: eventType,
                                      description: descriptionController.text.trim(),
                                      eventDate: selectedDate,
                                      createdAt: event.createdAt,
                                    ),
                                  );
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تغییرات ذخیره شد')));
                              }
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
    final confirmed = await _confirmDelete(context, 'حذف رویداد', 'آیا این رویداد از خط زمان پرونده حذف شود؟');
    if (confirmed != true) return;
    await (db.delete(db.caseTimelineEvents)..where((t) => t.id.equals(event.id))).go();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حذف شد')));
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

  Future<String> _copyToCaseFolder(String sourcePath) async {
    final source = File(sourcePath);
    final dir = await getApplicationDocumentsDirectory();
    final caseDir = Directory(p.join(dir.path, 'case_documents', 'case_${item.id}'));
    if (!await caseDir.exists()) {
      await caseDir.create(recursive: true);
    }
    final extension = p.extension(sourcePath);
    final safeName = '${DateTime.now().millisecondsSinceEpoch}$extension';
    final target = File(p.join(caseDir.path, safeName));
    await source.copy(target.path);
    return target.path;
  }

  Future<void> _captureDocument(BuildContext context, AppDatabase db) async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      if (image == null) return;
      final savedPath = await _copyToCaseFolder(image.path);
      if (!context.mounted) return;
      await _showDocumentMetaDialog(context, db, filePath: savedPath, defaultTitle: 'تصویر مدرک');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('دوربین یا ذخیره عکس در دسترس نبود.')));
    }
  }

  Future<void> _pickDocumentFile(BuildContext context, AppDatabase db) async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      final savedPath = await _copyToCaseFolder(path);
      if (!context.mounted) return;
      await _showDocumentMetaDialog(context, db, filePath: savedPath, defaultTitle: result?.files.single.name ?? 'فایل مدرک');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('افزودن فایل انجام نشد.')));
    }
  }

  void _addDocumentManually(BuildContext context, AppDatabase db) {
    _showDocumentMetaDialog(context, db, filePath: null, defaultTitle: 'سند پرونده');
  }

  Future<void> _showDocumentMetaDialog(
    BuildContext context,
    AppDatabase db, {
    required String? filePath,
    required String defaultTitle,
  }) async {
    final titleController = TextEditingController(text: defaultTitle);
    final notesController = TextEditingController();
    String type = documentTypes.first;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('ثبت مدرک پرونده'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('این مدرک به همین پرونده وصل می‌شود.'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'نوع مدرک', border: OutlineInputBorder()),
                  items: documentTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                const SizedBox(height: 8),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان مدرک')),
                TextField(controller: notesController, decoration: const InputDecoration(labelText: 'یادداشت'), maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                await db.into(db.caseDocuments).insert(
                      CaseDocumentsCompanion.insert(
                        caseId: item.id,
                        title: title,
                        documentType: Value(type),
                        filePath: Value(filePath),
                        notes: Value(notesController.text.trim()),
                      ),
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مدرک به پرونده اضافه شد')));
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
  }


  void _showCasePersonDialog(BuildContext context, AppDatabase db, {CasePerson? person}) {
    final nameController = TextEditingController(text: person?.name ?? '');
    final phoneController = TextEditingController(text: person?.phone ?? '');
    final notesController = TextEditingController(text: person?.notes ?? '');
    const roles = ['موکل', 'طرف مقابل', 'وکیل مقابل', 'کارشناس', 'شاهد', 'نماینده', 'سایر'];
    String role = person?.role ?? roles.first;
    if (!roles.contains(role)) role = 'سایر';

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
                      decoration: const InputDecoration(labelText: 'سمت', border: OutlineInputBorder()),
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
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نام شخص را وارد کنید.')));
                                return;
                              }
                              if (person == null) {
                                await db.into(db.casePeople).insert(
                                      CasePeopleCompanion.insert(
                                        caseId: item.id,
                                        name: name,
                                        role: Value(role),
                                        phone: Value(phoneController.text.trim()),
                                        notes: Value(notesController.text.trim()),
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
                                        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                        createdAt: person.createdAt,
                                      ),
                                    );
                              }
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(person == null ? 'ثبت شد' : 'تغییرات ذخیره شد')));
                              }
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حذف شد')));
    }
  }

  void _showCaseFinanceDialog(BuildContext context, AppDatabase db, {FinanceItem? item}) {
    final titleController = TextEditingController(text: item?.title ?? '');
    final amountController = TextEditingController(text: item == null ? '' : item.amount.toStringAsFixed(0));
    final categoryController = TextEditingController(text: item?.category ?? '');
    final notesController = TextEditingController(text: item?.notes ?? '');
    String selectedType = item?.type ?? 'هزینه';
    DateTime selectedDate = item?.date ?? DateTime.now();

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
                    Text(item == null ? 'ثبت مالی این پرونده' : 'ویرایش مالی این پرونده', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      items: const [
                        DropdownMenuItem(value: 'هزینه', child: Text('هزینه')),
                        DropdownMenuItem(value: 'درآمد', child: Text('درآمد')),
                      ],
                      onChanged: (v) => setState(() => selectedType = v ?? selectedType),
                      decoration: const InputDecoration(labelText: 'نوع', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: titleController, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ تومان', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ ثبت'),
                      subtitle: Text(formatPersianLongDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await _askCaseDate(sheetContext, selectedDate, 'تاریخ شمسی ثبت مالی');
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'دسته‌بندی', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(controller: notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'یادداشت', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final title = titleController.text.trim();
                              final amount = double.tryParse(amountController.text.trim().replaceAll(',', '').replaceAll('٬', ''));
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان ثبت مالی را وارد کنید.')));
                                return;
                              }
                              if (amount == null || amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مبلغ معتبر وارد کنید.')));
                                return;
                              }
                              if (item == null) {
                                await db.into(db.financeItems).insert(
                                      FinanceItemsCompanion.insert(
                                        caseId: Value(item?.caseId ?? this.item.id),
                                        type: selectedType,
                                        title: title,
                                        amount: amount,
                                        category: Value(categoryController.text.trim()),
                                        date: Value(selectedDate),
                                        notes: Value(notesController.text.trim()),
                                      ),
                                    );
                              } else {
                                await db.update(db.financeItems).replace(
                                      FinanceItem(
                                        id: item.id,
                                        caseId: item.caseId ?? this.item.id,
                                        type: selectedType,
                                        title: title,
                                        amount: amount,
                                        category: categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
                                        date: selectedDate,
                                        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                      ),
                                    );
                              }
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(item == null ? 'ثبت شد' : 'تغییرات ذخیره شد')));
                              }
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حذف شد')));
    }
  }

  void _addExperienceForCase(BuildContext context, AppDatabase db) {
    final titleController = TextEditingController(text: 'تجربه پرونده ${item.title}');
    final resultController = TextEditingController();
    final strategyController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ثبت تجربه پرونده'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان')),
              TextField(controller: resultController, decoration: const InputDecoration(labelText: 'نتیجه'), maxLines: 2),
              TextField(controller: strategyController, decoration: const InputDecoration(labelText: 'استراتژی مؤثر'), maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              await db.into(db.experienceItems).insert(
                    ExperienceItemsCompanion.insert(
                      caseId: Value(item.id),
                      title: title,
                      result: Value(resultController.text.trim()),
                      effectiveStrategy: Value(strategyController.text.trim()),
                    ),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('ثبت'),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: StreamBuilder<List<FinanceItem>>(
          stream: db.select(db.financeItems).watch(),
          builder: (context, snapshot) {
            final items = List<FinanceItem>.of(snapshot.data ?? const <FinanceItem>[])
                .where((f) => f.caseId == item.id)
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
            final income = items.where((i) => i.type == 'درآمد').fold<double>(0, (s, i) => s + i.amount);
            final expense = items.where((i) => i.type == 'هزینه').fold<double>(0, (s, i) => s + i.amount);
            final balance = income - expense;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet),
                  title: const Text('مالی پرونده'),
                  subtitle: Text(
                    'درآمد: ${toPersianDigits(income.toStringAsFixed(0))} تومان\n'
                    'هزینه: ${toPersianDigits(expense.toStringAsFixed(0))} تومان\n'
                    'مانده: ${toPersianDigits(balance.toStringAsFixed(0))} تومان',
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('ثبت'),
                  ),
                ),
                if (items.isEmpty)
                  const Text('ثبت مالی برای این پرونده وجود ندارد.', style: TextStyle(color: Colors.white60))
                else
                  ...items.take(5).map((finance) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(finance.type == 'درآمد' ? Icons.trending_up : Icons.trending_down),
                      title: Text(finance.title),
                      subtitle: Text(
                        '${finance.type} | ${toPersianDigits(finance.amount.toStringAsFixed(0))} تومان | ${formatPersianLongDate(finance.date)}'
                        '${(finance.notes ?? '').isEmpty ? '' : '\n${finance.notes}'}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') onEdit(finance);
                          if (value == 'delete') onDelete(finance);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}


class _LegalCaseSnapshot extends StatelessWidget {
  const _LegalCaseSnapshot({required this.item, required this.db});

  final Case item;
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        db.select(db.deadlines).get(),
        db.select(db.caseDocuments).get(),
        db.select(db.caseTimelineEvents).get(),
        db.select(db.financeItems).get(),
        db.select(db.casePeople).get(),
      ]),
      builder: (context, snapshot) {
        final deadlines = snapshot.hasData ? snapshot.data![0] as List<Deadline> : const <Deadline>[];
        final docs = snapshot.hasData ? snapshot.data![1] as List<CaseDocument> : const <CaseDocument>[];
        final timeline = snapshot.hasData ? snapshot.data![2] as List<CaseTimelineEvent> : const <CaseTimelineEvent>[];
        final finance = snapshot.hasData ? snapshot.data![3] as List<FinanceItem> : const <FinanceItem>[];
        final people = snapshot.hasData ? snapshot.data![4] as List<CasePerson> : const <CasePerson>[];

        final relatedDeadlines = deadlines.where((d) => d.caseId == item.id && !d.isDone).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final relatedDocs = docs.where((d) => d.caseId == item.id).toList();
        final relatedTimeline = timeline.where((e) => e.caseId == item.id).toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
        final relatedFinance = finance.where((f) => f.caseId == item.id).toList();
        final relatedPeople = people.where((p) => p.caseId == item.id).toList();
        final income = relatedFinance.where((i) => i.type == 'درآمد').fold<double>(0, (s, i) => s + i.amount);
        final expense = relatedFinance.where((i) => i.type == 'هزینه').fold<double>(0, (s, i) => s + i.amount);

        final nextDeadline = relatedDeadlines.isEmpty
            ? 'ثبت نشده'
            : '${relatedDeadlines.first.title} - ${formatPersianLongDate(relatedDeadlines.first.dueDate)}';
        final lastEvent = relatedTimeline.isEmpty
            ? 'ثبت نشده'
            : '${relatedTimeline.first.title} - ${formatPersianLongDate(relatedTimeline.first.eventDate)}';

        return Card(
          child: ListTile(
            leading: const Icon(Icons.gavel),
            title: const Text('نمای حقوقی پرونده'),
            subtitle: Text(
              'نقش/سمت اصلی: ${item.clientRole ?? 'ثبت نشده'}\n'
              'سمت مرحله فعلی: ${item.currentRole ?? 'ثبت نشده'}\n'
              'مرحله پرونده: ${item.stage ?? 'ثبت نشده'}\n'
              'موضوع دعوا: ${item.subject ?? 'ثبت نشده'}\n'
              'اقدام بعدی: ${(item.nextAction ?? '').trim().isEmpty ? 'ثبت نشده' : item.nextAction}\n'
              'نزدیک‌ترین مهلت: $nextDeadline\n'
              'آخرین رویداد خط زمان: $lastEvent\n'
              'تعداد اشخاص مرتبط: ${toPersianDigits(relatedPeople.length.toString())}\n'
              'تعداد اسناد مرتبط: ${toPersianDigits(relatedDocs.length.toString())}\n'
              'درآمد پرونده: ${toPersianDigits(income.toStringAsFixed(0))} تومان\n'
              'هزینه پرونده: ${toPersianDigits(expense.toStringAsFixed(0))} تومان\n'
              'مانده پرونده: ${toPersianDigits((income - expense).toStringAsFixed(0))} تومان',
            ),
          ),
        );
      },
    );
  }
}
