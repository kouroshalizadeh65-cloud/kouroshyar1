import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/database_provider.dart';
import 'openai_service.dart';
import 'ai_prompt_templates_screen.dart';

class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final promptController = TextEditingController();
  String result = '';
  bool loading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('دستیار هوش مصنوعی')),
      body: FutureBuilder(
        future: db.select(db.aiSettings).get(),
        builder: (context, snapshot) {
          final settings = (snapshot.data ?? []).isNotEmpty ? (snapshot.data ?? []).first : null;
          final enabled = settings?.isEnabled ?? false;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(enabled ? Icons.check_circle : Icons.warning_amber),
                  title: Text(enabled ? 'هوش مصنوعی فعال است' : 'هوش مصنوعی فعال نیست'),
                  subtitle: const Text('برای استفاده، ابتدا از تنظیمات کلید API را ثبت کن.'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final selected = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (_) => const AiPromptTemplatesScreen()),
                  );
                  if (selected != null) {
                    promptController.text = selected;
                  }
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('انتخاب قالب آماده'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptController,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'درخواست',
                  hintText: 'درخواست حقوقی یا مدیریتی خود را وارد کن',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: loading || !enabled
                    ? null
                    : () async {
                        setState(() {
                          loading = true;
                          result = '';
                        });

                        try {
                          final service = OpenAiService(
                            apiKey: settings?.apiKey ?? '',
                            model: settings?.model ?? 'gpt-4.1-mini',
                          );

                          final prompt = '''
تو دستیار حقوقی یک وکیل ایرانی هستی.
پاسخ را فارسی، دقیق، کاربردی و با ساختار منظم بده.
در صورت نیاز، هشدار بده که تصمیم نهایی با وکیل است.

درخواست:
${promptController.text.trim()}
''';

                          final response = await service.sendPrompt(prompt);
                          setState(() => result = response);
                        } catch (e) {
                          setState(() => result = e.toString());
                        } finally {
                          if (mounted) setState(() => loading = false);
                        }
                      },
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(loading ? 'در حال دریافت پاسخ...' : 'ارسال به هوش مصنوعی'),
              ),
              const SizedBox(height: 16),
              if (result.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(result),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
