import 'package:flutter/material.dart';

import '../cases/cases_screen.dart';
import '../personal/personal_screen.dart';
import '../tasks/tasks_screen.dart';

class QuickActionSheet extends StatelessWidget {
  const QuickActionSheet({super.key});

  static Future<void> show(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: QuickActionSheet()),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add_circle_outline),
            title: Text('ثبت و اقدام سریع', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('ثبت مستقیم موارد پرکاربرد برنامه.'),
          ),
          const SizedBox(height: 4),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: _QuickTile(
                  icon: Icons.task_alt,
                  title: 'کارهای و یادآوری‌های شخصی',
                  onTap: () => _open(
                    context,
                    const TasksScreen(personalOnly: true, openAddOnStart: true, initialAddType: 'task'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickTile(
                  icon: Icons.alarm,
                  title: 'مهلت',
                  onTap: () => _open(
                    context,
                    const TasksScreen(personalOnly: true, openAddOnStart: true, initialAddType: 'deadline'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: _QuickTile(
                  icon: Icons.payments,
                  title: 'هزینه و درآمدها',
                  onTap: () => _open(context, const PersonalFinanceScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickTile(
                  icon: Icons.people_alt_outlined,
                  title: 'طلب و بدهی‌ها',
                  onTap: () => _open(context, const PersonalAccountsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _QuickTile(
              icon: Icons.gavel,
              title: 'پرونده',
              horizontal: true,
              onTap: () => _open(context, const CasesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.horizontal = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: horizontal
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon),
                    const SizedBox(width: 10),
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : SizedBox(
                height: 126,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
