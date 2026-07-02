import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/session/session_context.dart';
import '../focus_mode/focus_mode_state.dart';
import '../../core/utils/kourosh_datetime_parser.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/voice/voice_input_button.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../ai/openai_service.dart';
import '../kourosh_suggestions/kourosh_suggestions_screen.dart';
import '../settings/settings_screen.dart';
import '../search/global_search_screen.dart';
import 'command_intent.dart';
import 'command_result.dart';
import 'kourosh_command_history.dart';
import '../../core/widgets/global_search_button.dart';

class KouroshCommandScreen extends ConsumerStatefulWidget {
  const KouroshCommandScreen({super.key});

  @override
  ConsumerState<KouroshCommandScreen> createState() => _KouroshCommandScreenState();
}

class _KouroshCommandScreenState extends ConsumerState<KouroshCommandScreen> {
  final controller = TextEditingController();
  CommandResult? lastResult;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    final contextText = FocusModeState.enabled
        ? 'حالت تمرکز: پرونده ${FocusModeState.caseTitle}'
        : SessionContext.lastCaseTitle == null
            ? 'زمینه فعلی: عمومی'
            : 'زمینه فعلی: پرونده ${SessionContext.lastCaseTitle}';

    return Scaffold(
      appBar: AppBar(title: const Text('فرمان سریع'), actions: const [GlobalSearchButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.assistant),
              title: const Text('ثبت و فرمان سریع'),
              subtitle: Text('$contextText\nهر کاری داری بنویس؛ فرمان سریع تشخیص می‌دهد چه باید بکند.'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'چه کاری برایت انجام بدهم؟',
              hintText: 'فرمان یا ثبت موردنظر را اینجا بنویس',
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
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : _handleCommand,
            icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.flash_on),
            label: Text(loading ? 'در حال انجام...' : 'انجام بده'),
          ),
          const SizedBox(height: 16),
          if (KouroshCommandHistory.items.isNotEmpty) ...[
            const Text('فرمان‌های اخیر', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: KouroshCommandHistory.items.take(8).map((e) {
                return ActionChip(
                  label: Text(e),
                  onPressed: () => setState(() => controller.text = e),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (lastResult != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(lastResult!.message),
                    if (lastResult!.canUndo) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _undoLast,
                        icon: const Icon(Icons.undo),
                        label: Text(lastResult!.undoLabel ?? 'برگردان'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleCommand() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    if (text.contains('لغو') || text.contains('برگرد')) {
      await _undoLast();
      return;
    }

    SessionContext.setLastCommand(text);
    KouroshCommandHistory.add(text);
    if (text.contains('پیشنهاد')) {
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const KouroshSuggestionsScreen()));
      }
      setState(() => lastResult = const CommandResult(
        message: 'بخش پیشنهاد کوروش‌یار باز شد. پیشنهادها بر اساس کارها، مهلت‌ها و مالی ثبت‌شده ساخته می‌شوند.',
      ));
      return;
    }

    final intent = detectCommandIntent(text);

    if (intent.needsConfirmation && !intent.needsOnlineAi) {
      final ok = await _confirmAction(intent.title, text);
      if (!ok) {
        setState(() => lastResult = const CommandResult(message: 'لغو شد.'));
        return;
      }
    }

    if (intent.needsOnlineAi) {
      if (_looksSensitive(text)) {
        final sensitiveOk = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('هشدار اطلاعات حساس'),
            content: const Text('متن شما حاوی نشانه‌های اطلاعات حساس است. قبل از ارسال، بهتر است آن را ناشناس‌سازی کنی. با همین متن ادامه بدهم؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ادامه')),
            ],
          ),
        );
        if (sensitiveOk != true) {
          setState(() => lastResult = const CommandResult(message: 'لغو شد. متن به هوش آنلاین ارسال نشد.'));
          return;
        }
      }
      final allowed = await _confirmOnlineAi();
      if (!allowed) {
        setState(() => lastResult = const CommandResult(message: 'لغو شد. این درخواست بدون هوش آنلاین انجام نشد.'));
        return;
      }
    }

    setState(() {
      loading = true;
      lastResult = null;
    });

    try {
      switch (intent.type) {
        case CommandIntentType.task:
          await _createTask(text);
          break;
        case CommandIntentType.session:
          await _createSession(text);
          break;
        case CommandIntentType.deadline:
          await _createDeadline(text);
          break;
        case CommandIntentType.finance:
          await _createFinance(text);
          break;
        case CommandIntentType.report:
          await _showTodayReport();
          break;
        case CommandIntentType.openCase:
        case CommandIntentType.search:
          await _search(text);
          break;
        case CommandIntentType.ai:
          await _runAi(text);
          break;
        case CommandIntentType.settings:
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }
          setState(() => lastResult = const CommandResult(message: 'تنظیمات باز شد.'));
          break;
        case CommandIntentType.unknown:
          setState(() => lastResult = const CommandResult(message: 'متوجه نشدم. کمی واضح‌تر بنویس.'));
          break;
      }
    } catch (e) {
      setState(() => lastResult = CommandResult(message: e.toString()));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _confirmAction(String title, String text) async {
    final value = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text('این مورد انجام شود؟\n\n$text'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأیید')),
        ],
      ),
    );
    return value ?? false;
  }

  bool _looksSensitive(String text) {
    return text.contains('کد ملی') ||
        text.contains('شماره پرونده') ||
        text.contains('رمز') ||
        text.contains('محرمانه') ||
        text.contains('موکل');
  }

  Future<bool> _confirmOnlineAi() async {
    final value = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('نیاز به هوش آنلاین'),
        content: const Text('برای این درخواست باید از هوش آنلاین استفاده شود. ممکن است بخشی از متن پرونده یا فرمان شما ارسال شود. ادامه بدهم؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ادامه')),
        ],
      ),
    );
    return value ?? false;
  }

  Future<void> _undoLast() async {
    final action = lastResult?.undoAction;
    if (action == null) {
      setState(() => lastResult = const CommandResult(message: 'چیزی برای برگرداندن وجود ندارد.'));
      return;
    }

    await action();
    setState(() => lastResult = const CommandResult(message: 'آخرین عملیات برگردانده شد.'));
  }

  String _normalizeDigits(String value) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var result = value;
    for (var i = 0; i < 10; i++) {
      result = result.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    return result;
  }

  Future<int?> _caseIdFromCommandText(AppDatabase db, String text) async {
    final focusedId = FocusModeState.caseId ?? SessionContext.lastCaseId;
    if (focusedId != null) return focusedId;

    final cases = await db.select(db.cases).get();
    for (final item in cases) {
      final values = [
        item.title,
        item.clientName,
        item.opponentName,
        item.caseNumber,
      ].whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty);
      if (values.any(text.contains)) {
        SessionContext.setLastCase(id: item.id, title: item.title);
        return item.id;
      }
    }
    return null;
  }

  Future<Case?> _caseFromId(AppDatabase db, int? id) async {
    if (id == null) return null;
    final cases = await db.select(db.cases).get();
    for (final item in cases) {
      if (item.id == id) return item;
    }
    return null;
  }

  String _withoutCommonCommandWords(String text) {
    var value = _normalizeDigits(text)
        .replaceAll('‌', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final amountPattern = RegExp(r'\d+[\d,]*(\s*(تومان|ریال|هزار|میلیون))?');
    value = value.replaceAll(amountPattern, ' ');

    const words = [
      'برای پرونده',
      'پرونده',
      'لطفا',
      'لطفاً',
      'ثبت کن',
      'ذخیره کن',
      'اضافه کن',
      'ثبت شود',
      'ثبت',
      'ذخیره',
      'کن',
      'دارم',
      'یادآوری',
      'امروز',
      'فردا',
      'پس فردا',
      'هزینه',
      'درآمد',
      'دریافتی',
      'پرداخت',
      'پرداختم',
      'گرفتم',
      'جلسه',
      'مهلت',
      'کار',
    ];
    for (final word in words) {
      value = value.replaceAll(word, ' ');
    }
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _cleanTitle(String text, String fallback) {
    final cleaned = _withoutCommonCommandWords(text);
    if (cleaned.isEmpty) return fallback;
    if (cleaned.length < 3) return fallback;
    return cleaned;
  }

  String _financeTitle(String text, String type, String? caseTitle) {
    if (caseTitle != null && caseTitle.trim().isNotEmpty) {
      return '$type پرونده ${caseTitle.trim()}';
    }
    final cleaned = _cleanTitle(text, '$type ثبت سریع');
    return cleaned == '$type ثبت سریع' ? cleaned : '$type - $cleaned';
  }

  Future<void> _recordInbox(AppDatabase db, String rawText, String detectedType) async {
    await db.into(db.inboxItems).insert(
      InboxItemsCompanion.insert(
        rawText: rawText,
        detectedType: Value(detectedType),
        isProcessed: const Value(true),
      ),
    );
  }

  Future<void> _createTask(String text) async {
    final db = ref.read(databaseProvider);
    final dueDate = parseKouroshDate(text);
    final timeText = parseKouroshTime(text);
    final caseId = await _caseIdFromCommandText(db, text);
    final caseItem = await _caseFromId(db, caseId);
    final title = _cleanTitle(text, caseItem == null ? 'کار ثبت سریع' : 'کار پرونده ${caseItem.title}');
    final id = await db.into(db.tasks).insert(
      TasksCompanion.insert(
        title: title,
        caseId: Value(caseId),
        priority: const Value('متوسط'),
        dueDate: Value(dueDate),
      ),
    );
    await _recordInbox(db, text, 'کار');
    controller.clear();
    setState(() => lastResult = CommandResult(
      message: '''کار ثبت شد و در امروز/گزارش‌ها قابل مشاهده است:
$title
زمان تشخیص‌داده‌شده: ${formatKouroshDateTime(dueDate, timeText)}''',
      undoLabel: 'حذف این کار',
      undoAction: () => (db.delete(db.tasks)..where((t) => t.id.equals(id))).go(),
    ));
  }

  Future<void> _createSession(String text) async {
    final db = ref.read(databaseProvider);
    final caseId = await _caseIdFromCommandText(db, text);
    final dueDate = parseKouroshDate(text);
    final timeText = parseKouroshTime(text);
    final title = _cleanTitle(text, 'جلسه');

    if (caseId == null) {
      final taskId = await db.into(db.tasks).insert(
        TasksCompanion.insert(
          title: 'جلسه: $title',
          priority: const Value('زیاد'),
          dueDate: Value(dueDate),
        ),
      );
      await _recordInbox(db, text, 'جلسه');
      controller.clear();
      setState(() => lastResult = CommandResult(
        message: '''پرونده مشخص نبود؛ جلسه به‌صورت کار زمان‌دار ثبت شد تا در امروز و گزارش‌ها گم نشود.
عنوان: جلسه: $title
زمان: ${formatKouroshDateTime(dueDate, timeText)}''',
        undoLabel: 'حذف این ثبت',
        undoAction: () => (db.delete(db.tasks)..where((t) => t.id.equals(taskId))).go(),
      ));
      return;
    }

    final id = await db.into(db.caseTimelineEvents).insert(
      CaseTimelineEventsCompanion.insert(
        caseId: caseId,
        title: title,
        eventType: const Value('جلسه'),
        description: Value(timeText == null ? 'ثبت‌شده از فرمان سریع' : 'ساعت: $timeText'),
        eventDate: Value(dueDate),
      ),
    );
    await _recordInbox(db, text, 'جلسه');

    controller.clear();
    setState(() => lastResult = CommandResult(
      message: '''جلسه ثبت شد و در خط زمان پرونده، امروز، تقویم و گزارش‌ها نمایش داده می‌شود:
$title
زمان: ${formatKouroshDateTime(dueDate, timeText)}''',
      undoLabel: 'حذف این جلسه',
      undoAction: () => (db.delete(db.caseTimelineEvents)..where((e) => e.id.equals(id))).go(),
    ));
  }

  Future<void> _createDeadline(String text) async {
    final db = ref.read(databaseProvider);
    final caseId = await _caseIdFromCommandText(db, text);
    final caseItem = await _caseFromId(db, caseId);
    final dueDate = parseKouroshDate(text);
    final title = _cleanTitle(text, caseItem == null ? 'مهلت ثبت سریع' : 'مهلت پرونده ${caseItem.title}');
    final id = await db.into(db.deadlines).insert(
      DeadlinesCompanion.insert(
        caseId: Value(caseId),
        title: title,
        deadlineType: const Value('ثبت سریع'),
        dueDate: dueDate,
      ),
    );
    await _recordInbox(db, text, 'مهلت');
    controller.clear();
    setState(() => lastResult = CommandResult(
      message: '''مهلت ثبت شد و در امروز/گزارش‌ها قابل مشاهده است:
$title
تاریخ: ${formatPersianLongDate(dueDate)}''',
      undoLabel: 'حذف این مهلت',
      undoAction: () => (db.delete(db.deadlines)..where((d) => d.id.equals(id))).go(),
    ));
  }

  Future<void> _createFinance(String text) async {
    final db = ref.read(databaseProvider);
    final normalizedText = _normalizeDigits(text).replaceAll('٬', ',');
    final amountMatch = RegExp(r'(\d+[\d,]*)').firstMatch(normalizedText);
    var amount = double.tryParse((amountMatch?.group(1) ?? '0').replaceAll(',', '')) ?? 0;
    if (amount > 0 && normalizedText.contains('میلیون')) amount *= 1000000;
    if (amount > 0 && normalizedText.contains('هزار')) amount *= 1000;

    if (amount <= 0) {
      setState(() => lastResult = const CommandResult(message: 'فرمان مالی تشخیص داده شد، اما مبلغ پیدا نشد. چیزی ذخیره نشد.'));
      return;
    }

    final caseId = await _caseIdFromCommandText(db, text);
    final caseItem = await _caseFromId(db, caseId);
    final type = text.contains('درآمد') || text.contains('گرفتم') || text.contains('حق‌الوکاله') || text.contains('دریافتی') ? 'درآمد' : 'هزینه';
    final title = _financeTitle(text, type, caseItem?.title);
    final date = parseKouroshDate(text);
    final id = await db.into(db.financeItems).insert(
      FinanceItemsCompanion.insert(
        caseId: Value(caseId),
        type: type,
        title: title,
        amount: amount,
        category: const Value('ثبت سریع'),
        date: Value(date),
        notes: Value(text),
      ),
    );
    await _recordInbox(db, text, 'مالی');

    controller.clear();
    setState(() => lastResult = CommandResult(
      message: '''ثبت مالی انجام شد و در مالی/گزارش‌ها قابل مشاهده است:
$title
$type: ${amount.toStringAsFixed(0)} تومان
تاریخ: ${formatPersianLongDate(date)}''',
      undoLabel: 'حذف این ثبت مالی',
      undoAction: () => (db.delete(db.financeItems)..where((f) => f.id.equals(id))).go(),
    ));
  }

  Future<void> _showTodayReport() async {
    final db = ref.read(databaseProvider);
    final tasks = await db.select(db.tasks).get();
    final deadlines = await db.select(db.deadlines).get();
    final finance = await db.select(db.financeItems).get();
    final cases = await db.select(db.cases).get();
    final income = finance.where((f) => f.type == 'درآمد').fold<double>(0, (s, f) => s + f.amount);
    final expense = finance.where((f) => f.type == 'هزینه').fold<double>(0, (s, f) => s + f.amount);
    final casesWithoutNextAction = cases.where((c) => c.status != 'مختومه' && (c.nextAction ?? '').trim().isEmpty).length;

    setState(() {
      lastResult = CommandResult(message: 'گزارش سریع امروز:\n'
          'کارهای باز: ${tasks.where((t) => !t.isDone).length}\n'
          'مهلت‌های باز: ${deadlines.where((d) => !d.isDone).length}\n'
          'پرونده‌های بدون اقدام بعدی: $casesWithoutNextAction\n'
          'مانده مالی: ${(income - expense).toStringAsFixed(0)} تومان\n'
          'پیشنهاد کوروش‌یار: ابتدا مهلت‌های نزدیک، کارهای عقب‌افتاده و پرونده‌های بدون اقدام بعدی را بررسی کن.');
    });
  }

  Future<void> _search(String text) async {
    final db = ref.read(databaseProvider);
    final q = text
        .replaceAll('پیدا کن', '')
        .replaceAll('جستجو', '')
        .replaceAll('باز کن', '')
        .replaceAll('پرونده', '')
        .trim();

    if (q.isEmpty) {
      setState(() => lastResult = const CommandResult(message: 'برای جستجو، نام پرونده، شخص، مهلت، سند یا عبارت موردنظر را بنویس.'));
      return;
    }

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalSearchScreen(initialQuery: q)));
    }

    final cases = await db.select(db.cases).get();
    final legalTexts = await db.select(db.legalTexts).get();
    final deadlines = await db.select(db.deadlines).get();
    final finance = await db.select(db.financeItems).get();
    final docs = await db.select(db.caseDocuments).get();
    final timeline = await db.select(db.caseTimelineEvents).get();

    bool contains(String? value) => (value ?? '').contains(q);

    final matchedCases = cases.where((c) =>
      contains(c.title) ||
      contains(c.clientName) ||
      contains(c.opponentName) ||
      contains(c.subject) ||
      contains(c.stage) ||
      contains(c.caseNumber) ||
      contains(c.nextAction)
    ).toList();

    final matchedDeadlines = deadlines.where((d) =>
      contains(d.title) ||
      contains(d.deadlineType) ||
      contains(d.notes) ||
      contains(formatPersianLongDate(d.dueDate))
    ).toList();

    final matchedFinance = finance.where((f) =>
      contains(f.title) ||
      contains(f.type) ||
      contains(f.category) ||
      contains(f.notes) ||
      contains(f.amount.toStringAsFixed(0)) ||
      contains(formatPersianLongDate(f.date))
    ).toList();

    final matchedDocs = docs.where((d) =>
      contains(d.title) ||
      contains(d.documentType) ||
      contains(d.notes) ||
      contains(d.extractedText) ||
      contains(d.aiSummary)
    ).toList();

    final matchedTimeline = timeline.where((e) =>
      contains(e.title) ||
      contains(e.eventType) ||
      contains(e.description) ||
      contains(formatPersianLongDate(e.eventDate))
    ).toList();

    final matchedTexts = legalTexts.where((t) =>
      contains(t.title) ||
      contains(t.body) ||
      contains(t.subject) ||
      contains(t.tags) ||
      contains(t.type)
    ).toList();

    if (matchedCases.length == 1) {
      SessionContext.setLastCase(id: matchedCases.first.id, title: matchedCases.first.title);
    }

    setState(() {
      lastResult = CommandResult(message: 'نتایج جستجو برای "$q":\n\n'
          'پرونده‌ها:\n${matchedCases.isEmpty ? '- موردی پیدا نشد' : matchedCases.map((c) => '- ${c.title}').join('\n')}\n\n'
          'مهلت‌ها:\n${matchedDeadlines.isEmpty ? '- موردی پیدا نشد' : matchedDeadlines.map((d) => '- ${d.title}').join('\n')}\n\n'
          'مالی:\n${matchedFinance.isEmpty ? '- موردی پیدا نشد' : matchedFinance.map((f) => '- ${f.title}؛ ${f.amount.toStringAsFixed(0)} تومان').join('\n')}\n\n'
          'اسناد:\n${matchedDocs.isEmpty ? '- موردی پیدا نشد' : matchedDocs.map((d) => '- ${d.title}').join('\n')}\n\n'
          'خط زمان:\n${matchedTimeline.isEmpty ? '- موردی پیدا نشد' : matchedTimeline.map((e) => '- ${e.title}').join('\n')}\n\n'
          'بانک متون:\n${matchedTexts.isEmpty ? '- موردی پیدا نشد' : matchedTexts.map((t) => '- ${t.title}').join('\n')}');
    });
  }

  Future<void> _runAi(String text) async {
    final db = ref.read(databaseProvider);
    final settings = await db.select(db.aiSettings).get();

    if (settings.isEmpty || !settings.first.isEnabled) {
      setState(() => lastResult = const CommandResult(message: 'هوش آنلاین فعال نیست. ابتدا API Key را در تنظیمات هوش مصنوعی وارد کن.'));
      return;
    }

    final cases = await db.select(db.cases).get();
    final tasks = await db.select(db.tasks).get();
    final deadlines = await db.select(db.deadlines).get();

    final prompt = '''
تو کوروش‌یار هستی؛ دستیار حقوقی و شخصی یک وکیل ایرانی.
پاسخ را فارسی، دقیق، کوتاه و کاربردی بده.

زمینه فعلی:
${FocusModeState.caseTitle ?? SessionContext.lastCaseTitle ?? 'عمومی'}

درخواست:
$text

پرونده‌ها:
${cases.map((c) => '- ${c.title} | ${c.subject ?? ''} | ${c.stage ?? ''}').join('\n')}

کارها:
${tasks.map((t) => '- ${t.title} | ${t.priority} | ${t.isDone ? 'انجام شده' : 'باز'}').join('\n')}

مهلت‌ها:
${deadlines.map((d) => '- ${d.title} | ${d.deadlineType ?? ''} | ${formatPersianLongDate(d.dueDate)}').join('\n')}
''';

    final service = OpenAiService(
      apiKey: settings.first.apiKey ?? '',
      model: settings.first.model,
    );

    final response = await service.sendPrompt(prompt);
    setState(() => lastResult = CommandResult(message: response));
  }
}
