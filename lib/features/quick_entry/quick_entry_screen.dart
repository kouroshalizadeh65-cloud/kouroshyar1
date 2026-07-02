import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../../core/utils/entry_detector.dart';
import '../../core/utils/simple_persian_date_parser.dart';
import '../../core/voice/voice_input_button.dart';

class QuickEntryScreen extends ConsumerStatefulWidget {
  const QuickEntryScreen({super.key});

  @override
  ConsumerState<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends ConsumerState<QuickEntryScreen> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت سریع')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'متن کار، مهلت، مالی یا یادداشت را وارد کن',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: VoiceInputButton(
                onText: (text) {
                  setState(() {
                    controller.text = text;
                    controller.selection = TextSelection.collapsed(offset: controller.text.length);
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;

                final detectedType = detectEntryType(text);
                final parsedDate = parseSimplePersianRelativeDate(text);

                await db.into(db.inboxItems).insert(
                      InboxItemsCompanion.insert(
                        rawText: text,
                        detectedType: Value(detectedType),
                      ),
                    );

                if (detectedType == 'مهلت') {
                  await db.into(db.deadlines).insert(
                        DeadlinesCompanion.insert(
                          title: text,
                          dueDate: parsedDate ?? DateTime.now(),
                          deadlineType: const Value('ثبت سریع'),
                        ),
                      );
                } else if (detectedType == 'مالی') {
                  final amountMatch = RegExp(r'(\d+[\d,]*)').firstMatch(text.replaceAll('٬', ','));
                  final amount = double.tryParse((amountMatch?.group(1) ?? '0').replaceAll(',', '')) ?? 0;
                  if (amount > 0) {
                    await db.into(db.financeItems).insert(
                          FinanceItemsCompanion.insert(
                            type: text.contains('درآمد') || text.contains('گرفتم') || text.contains('حق‌الوکاله') ? 'درآمد' : 'هزینه',
                            title: text,
                            amount: amount,
                            category: const Value('ثبت سریع'),
                          ),
                        );
                  }
                } else {
                  await db.into(db.tasks).insert(
                        TasksCompanion.insert(
                          title: text,
                          dueDate: Value(parsedDate),
                          priority: Value(detectedType == 'حقوقی' ? 'زیاد' : 'متوسط'),
                        ),
                      );
                }

                controller.clear();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ثبت شد')),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}
