import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/money_format.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../../core/widgets/global_settings_button.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('مالی'), actions: const [GlobalSettingsButton()]),
      body: StreamBuilder<List<FinanceItem>>(
        stream: db.select(db.financeItems).watch(),
        builder: (context, snapshot) {
          final items = List<FinanceItem>.of(snapshot.data ?? const <FinanceItem>[]);
          final income = items.where((i) => i.type == 'درآمد').fold<double>(0, (s, i) => s + i.amount);
          final expense = items.where((i) => i.type == 'هزینه').fold<double>(0, (s, i) => s + i.amount);
          items.sort((a, b) => b.date.compareTo(a.date));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              Card(
                child: ListTile(
                  title: const Text('خلاصه مالی'),
                  subtitle: Text(
                    'درآمد: ${formatMoney(income)} تومان\n'
                    'هزینه: ${formatMoney(expense)} تومان\n'
                    'مانده: ${formatMoney(income - expense)} تومان',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('ثبت‌های مالی', style: TextStyle(fontSize: 18)),
              if (items.isEmpty)
                const Card(child: ListTile(title: Text('ثبت مالی وجود ندارد.'))),
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: Icon(item.type == 'درآمد' ? Icons.trending_up : Icons.trending_down),
                    title: Text(item.title),
                    subtitle: Text(
                      '${item.type} | ${formatMoney(item.amount)} تومان | ${item.category ?? 'بدون دسته'}\n'
                      '${formatPersianLongDate(item.date)}${(item.notes ?? '').isEmpty ? '' : '\n${item.notes}'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showFinanceDialog(context, db, item: item);
                        } else if (value == 'delete') {
                          _deleteFinance(context, db, item);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFinanceDialog(context, db),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showFinanceDialog(BuildContext context, AppDatabase db, {FinanceItem? item}) {
    final titleController = TextEditingController(text: item?.title ?? '');
    final amountController = TextEditingController(text: item == null ? '' : formatMoneyInput(item.amount.toStringAsFixed(0)));
    final categoryController = TextEditingController(text: item?.category ?? '');
    final notesController = TextEditingController(text: item?.notes ?? '');
    String selectedType = item?.type ?? 'هزینه';
    DateTime selectedDate = item?.date ?? DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(item == null ? 'ثبت مالی' : 'ویرایش ثبت مالی'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'هزینه', child: Text('هزینه')),
                    DropdownMenuItem(value: 'درآمد', child: Text('درآمد')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => selectedType = v);
                  },
                  decoration: const InputDecoration(labelText: 'نوع', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoneyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'مبلغ', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تاریخ ثبت'),
                  subtitle: Text(formatPersianLongDate(selectedDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await _askFinanceDate(dialogContext, selectedDate);
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 8),
                TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'دسته‌بندی', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: notesController, decoration: const InputDecoration(labelText: 'یادداشت', border: OutlineInputBorder()), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final amount = parseMoney(amountController.text);
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
                          caseId: item.caseId,
                          type: selectedType,
                          title: title,
                          amount: amount,
                          category: categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
                          date: selectedDate,
                          notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                        ),
                      );
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(item == null ? 'ثبت شد' : 'تغییرات ذخیره شد')));
                }
              },
              child: Text(item == null ? 'ثبت' : 'ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _askFinanceDate(BuildContext context, DateTime current) async {
    final controller = TextEditingController(text: formatSimpleDate(current));
    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تاریخ شمسی ثبت مالی'),
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
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
          FilledButton(
            onPressed: () {
              final parsed = parsePersianDateInput(controller.text);
              if (parsed == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاریخ معتبر نیست.')));
                return;
              }
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFinance(BuildContext context, AppDatabase db, FinanceItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف ثبت مالی'),
        content: const Text('آیا این ثبت مالی حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    await (db.delete(db.financeItems)..where((f) => f.id.equals(item.id))).go();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حذف شد')));
    }
  }
}
