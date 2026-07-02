import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import '../../database/app_database.dart';
import 'kourosh_suggestion_engine.dart';

class KouroshSuggestionsScreen extends ConsumerWidget {
  const KouroshSuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('پیشنهاد کوروش‌یار')),
      body: FutureBuilder(
        future: Future.wait([
          db.select(db.tasks).get(),
          db.select(db.deadlines).get(),
          db.select(db.financeItems).get(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final tasks = snapshot.data![0] as List<Task>;
          final deadlines = snapshot.data![1] as List<Deadline>;
          final financeItems = snapshot.data![2] as List<FinanceItem>;

          final suggestions = buildKouroshSuggestions(
            tasks: tasks,
            deadlines: deadlines,
            financeItems: financeItems,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lightbulb),
                  title: Text('پیشنهاد کوروش‌یار به شما'),
                  subtitle: Text('فقط چند پیشنهاد محدود و قابل اقدام نمایش داده می‌شود تا برنامه شلوغ نشود.'),
                ),
              ),
              const SizedBox(height: 12),
              for (final s in suggestions)
                Card(
                  child: ListTile(
                    leading: Icon(_iconForLevel(s.level)),
                    title: Text(s.title),
                    subtitle: Text(s.message),
                    trailing: Text(s.level),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  IconData _iconForLevel(String level) {
    switch (level) {
      case 'فوری':
        return Icons.warning_amber;
      case 'مالی':
        return Icons.payments;
      case 'مهم':
        return Icons.priority_high;
      default:
        return Icons.lightbulb;
    }
  }
}
