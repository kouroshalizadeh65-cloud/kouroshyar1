import 'package:flutter/material.dart';
import '../cases/cases_screen.dart';
import '../calendar/calendar_screen.dart';
import '../deadlines/deadlines_screen.dart';
import '../documents/documents_screen.dart';
import '../finance/finance_screen.dart';
import '../kourosh_command/kourosh_command_screen.dart';
import '../legal_texts/legal_texts_screen.dart';
import '../quick_entry/quick_entry_screen.dart';
import '../tasks/tasks_screen.dart';

class QuickActionSheet extends StatelessWidget {
  const QuickActionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: QuickActionSheet()),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const ListTile(
          leading: Icon(Icons.add_circle_outline),
          title: Text('ثبت و اقدام سریع', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('به‌جای رفتن بین چند صفحه، مسیر اصلی ثبت را از همین‌جا انتخاب کن.'),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _QuickTile(icon: Icons.bolt, title: 'فرمان متنی', onTap: () => _open(context, const KouroshCommandScreen())),
            _QuickTile(icon: Icons.inbox, title: 'ثبت سریع', onTap: () => _open(context, const QuickEntryScreen())),
            _QuickTile(icon: Icons.task_alt, title: 'کار', onTap: () => _open(context, const TasksScreen())),
            _QuickTile(icon: Icons.alarm, title: 'مهلت', onTap: () => _open(context, const DeadlinesScreen())),
            _QuickTile(icon: Icons.groups, title: 'جلسه', onTap: () => _open(context, const CalendarScreen())),
            _QuickTile(icon: Icons.payments, title: 'مالی', onTap: () => _open(context, const FinanceScreen())),
            _QuickTile(icon: Icons.gavel, title: 'پرونده', onTap: () => _open(context, const CasesScreen())),
            _QuickTile(icon: Icons.description, title: 'سند', onTap: () => _open(context, const DocumentsScreen())),
            _QuickTile(icon: Icons.menu_book, title: 'بانک متون', onTap: () => _open(context, const LegalTextsScreen())),
          ],
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon),
                const SizedBox(height: 8),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
