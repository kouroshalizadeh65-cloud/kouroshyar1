import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final apiKeyController = TextEditingController();
  final modelController = TextEditingController(text: 'gpt-4.1-mini');
  bool enabled = false;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('هوش مصنوعی')),
      body: FutureBuilder(
        future: db.select(db.aiSettings).get(),
        builder: (context, snapshot) {
          final current = (snapshot.data ?? []).isNotEmpty ? (snapshot.data ?? []).first : null;
          if (current != null && apiKeyController.text.isEmpty) {
            enabled = current.isEnabled;
            apiKeyController.text = current.apiKey ?? '';
            modelController.text = current.model;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                value: enabled,
                title: const Text('فعال‌سازی اتصال مستقیم'),
                subtitle: const Text('بدون سرور؛ کلید فقط روی گوشی ذخیره می‌شود.'),
                onChanged: (v) => setState(() => enabled = v),
              ),
              TextField(
                controller: apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'OpenAI API Key',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: 'مدل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final existing = await db.select(db.aiSettings).get();
                  if (existing.isEmpty) {
                    await db.into(db.aiSettings).insert(
                          AiSettingsCompanion.insert(
                            isEnabled: Value(enabled),
                            apiKey: Value(apiKeyController.text.trim()),
                            model: Value(modelController.text.trim()),
                          ),
                        );
                  } else {
                    await db.update(db.aiSettings).replace(
                          existing.first.copyWith(
                            isEnabled: enabled,
                            apiKey: Value(apiKeyController.text.trim()),
                            model: modelController.text.trim(),
                            updatedAt: DateTime.now(),
                          ),
                        );
                  }

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تنظیمات ذخیره شد')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('ذخیره'),
              ),
              const SizedBox(height: 16),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.warning_amber),
                  title: Text('نکته امنیتی'),
                  subtitle: Text('برای استفاده شخصی قابل قبول است، اما برای انتشار عمومی بهتر است سرور واسط داشته باشی. در نسخه فعلی هیچ اطلاعاتی خودکار ارسال نمی‌شود.'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
