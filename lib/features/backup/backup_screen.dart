import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/security/pin_security.dart';
import '../../core/utils/date_format_fa.dart';
import '../../core/utils/persian_numbers.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../lock/app_lock_controller.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String message = 'پشتیبان‌گیری فقط با دستور شما انجام می‌شود.';
  List<File> backups = const [];
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final files = await ref.read(databaseProvider).listBackups();
    if (!mounted) return;
    setState(() => backups = files);
  }

  Future<String?> _askBackupPassword({
    required String title,
    required String description,
    bool confirm = false,
    int minimumLength = 6,
  }) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? validationMessage;
    bool hidden = true;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(description),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  autofocus: true,
                  obscureText: hidden,
                  maxLength: 64,
                  textInputAction: confirm ? TextInputAction.next : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'رمز فایل پشتیبان',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: hidden ? 'نمایش رمز' : 'پنهان‌کردن رمز',
                      onPressed: () => setDialogState(() => hidden = !hidden),
                      icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    obscureText: hidden,
                    maxLength: 64,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'تکرار رمز فایل پشتیبان',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (validationMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      validationMessage!,
                      style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
            FilledButton(
              onPressed: () {
                final password = passwordController.text.trim();
                if (password.length < minimumLength) {
                  setDialogState(
                    () => validationMessage =
                        'رمز پشتیبان باید حداقل ${toPersianDigits(minimumLength)} نویسه باشد.',
                  );
                  return;
                }
                if (confirm && password != confirmController.text.trim()) {
                  setDialogState(() => validationMessage = 'رمز و تکرار آن یکسان نیستند.');
                  return;
                }
                Navigator.pop(dialogContext, password);
              },
              child: const Text('تأیید'),
            ),
          ],
        ),
      ),
    );
    passwordController.dispose();
    confirmController.dispose();
    return result;
  }

  Future<bool> _confirmLargeBackup(int estimatedBytes) async {
    const warningThreshold = 250 * 1024 * 1024;
    if (estimatedBytes < warningThreshold) return true;
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('حجم پشتیبان زیاد است'),
            content: Text(
              'حجم تقریبی داده‌ها و مدارک ${_formatBytes(estimatedBytes)} است. ساخت ZIP و رمزگذاری ممکن است چند دقیقه طول بکشد و به فضای خالی و حافظه کافی نیاز دارد. ادامه می‌دهید؟',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ادامه ساخت')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _createBackup() async {
    if (_working) return;
    final db = ref.read(databaseProvider);
    try {
      final estimatedBytes = await db.estimateBackupInputSizeBytes();
      if (!await _confirmLargeBackup(estimatedBytes)) return;
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'برآورد حجم پشتیبان انجام نشد: $error');
      return;
    }
    final password = await _askBackupPassword(
      title: 'رمزگذاری پشتیبان',
      description:
          'برای حفاظت از پرونده‌ها و مدارک، فایل پشتیبان با AES-256 رمزگذاری می‌شود. این رمز در برنامه ذخیره نمی‌شود؛ آن را در محل امن نگهداری کنید.',
      confirm: true,
    );
    if (password == null) return;

    setState(() {
      _working = true;
      message = 'در حال ساخت و رمزگذاری پشتیبان کامل...';
    });
    try {
      final file = await db.createBackup(reason: 'manual', password: password);
      await _refresh();
      if (!mounted) return;
      setState(() {
        message = file == null
            ? 'فایل داده هنوز ایجاد نشده است.'
            : 'پشتیبان رمزگذاری‌شده ساخته شد:\n${file.path}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'ساخت پشتیبان انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<_RestoreCredentials?> _askRestoreConfirmation(BackupSummary summary) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? validationMessage;
    final result = await showDialog<_RestoreCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('تأیید بازیابی پشتیبان'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryLine('وضعیت', summary.encrypted ? 'رمزگذاری‌شده' : 'قدیمی و بدون رمزگذاری'),
                _summaryLine('نسخه سازنده', summary.appVersion),
                _summaryLine('تاریخ', formatSimpleDateTime(summary.createdAt)),
                _summaryLine('پرونده‌ها', toPersianDigits(summary.caseCount)),
                _summaryLine('مدارک و فایل‌ها', toPersianDigits(summary.attachmentCount)),
                _summaryLine('حجم فایل', _formatBytes(summary.sizeBytes)),
                const Divider(height: 24),
                const Text(
                  'قبل از بازیابی، وضعیت فعلی با رمز جدید زیر پشتیبان‌گیری می‌شود. پس از بازیابی نیز قفل برنامه با همین رمز فعال خواهد بود.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 12,
                  decoration: const InputDecoration(labelText: 'رمز جدید برنامه', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 12,
                  decoration: const InputDecoration(labelText: 'تکرار رمز جدید', border: OutlineInputBorder()),
                ),
                if (validationMessage != null)
                  Text(validationMessage!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
            FilledButton(
              onPressed: () {
                final pin = pinController.text.trim();
                if (pin.length < 4) {
                  setDialogState(() => validationMessage = 'رمز برنامه باید حداقل ۴ رقم باشد.');
                  return;
                }
                if (pin != confirmController.text.trim()) {
                  setDialogState(() => validationMessage = 'رمز و تکرار آن یکسان نیستند.');
                  return;
                }
                Navigator.pop(dialogContext, _RestoreCredentials(newPin: pin));
              },
              child: const Text('بازیابی'),
            ),
          ],
        ),
      ),
    );
    pinController.dispose();
    confirmController.dispose();
    return result;
  }

  Widget _summaryLine(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text('$title:')),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Future<void> _restore(File file) async {
    if (_working) return;
    final db = ref.read(databaseProvider);
    String? backupPassword;
    try {
      final encrypted = await db.isEncryptedBackup(file);
      if (encrypted) {
        backupPassword = await _askBackupPassword(
          title: 'بازکردن پشتیبان رمزگذاری‌شده',
          description: 'رمزی را وارد کنید که هنگام ساخت این فایل تعیین شده است.',
          minimumLength: 4,
        );
        if (backupPassword == null) return;
      }

      setState(() {
        _working = true;
        message = 'در حال بررسی صحت و محتوای پشتیبان...';
      });
      final summary = await db.inspectBackup(file, password: backupPassword);
      if (!mounted) return;
      setState(() => _working = false);
      final credentials = await _askRestoreConfirmation(summary);
      if (credentials == null) return;

      setState(() {
        _working = true;
        message = 'در حال بازیابی و کنترل مدارک...';
      });
      await db.restoreBackup(
        file,
        newPinHash: hashPinSecure(credentials.newPin),
        backupPassword: backupPassword,
        emergencyBackupPassword: credentials.newPin,
      );
      await _refresh();
      if (!mounted) return;
      setState(() => message = 'بازیابی کامل انجام شد و قفل جدید فعال است.');
      appLockController.lockNow();
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'بازیابی انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pickAndRestoreBackup() async {
    if (_working) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['zip', 'kybackup', 'json'],
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      await _restore(File(path));
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'انتخاب فایل پشتیبان انجام نشد: $error');
    }
  }

  Future<void> _shareBackup(File file) async {
    try {
      final encrypted = await ref.read(databaseProvider).isEncryptedBackup(file);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: encrypted ? 'پشتیبان رمزگذاری‌شده کوروش‌یار' : 'پشتیبان قدیمی کوروش‌یار',
        text: encrypted
            ? 'این فایل شامل اطلاعات و مدارک رمزگذاری‌شده کوروش‌یار است. رمز فایل را از مسیر جداگانه و امن نگهداری کنید.'
            : 'این فایل پشتیبان قدیمی رمزگذاری نشده است؛ آن را فقط از مسیر امن انتقال دهید.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'اشتراک‌گذاری پشتیبان انجام نشد: $error');
    }
  }

  Future<void> _deleteBackup(File file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف فایل پشتیبان'),
        content: Text('آیا از حذف این فایل پشتیبان مطمئن هستید؟\n${p.basename(file.path)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(databaseProvider).deleteBackup(file);
      await _refresh();
      if (!mounted) return;
      setState(() => message = 'فایل پشتیبان حذف شد.');
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'حذف فایل پشتیبان انجام نشد: $error');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${toPersianDigits(bytes)} بایت';
    final kb = bytes / 1024;
    if (kb < 1024) return '${toPersianDigits(kb.toStringAsFixed(1))} کیلوبایت';
    final mb = kb / 1024;
    return '${toPersianDigits(mb.toStringAsFixed(1))} مگابایت';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پشتیبان‌گیری'), actions: const [GlobalSettingsButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.enhanced_encryption_outlined),
              title: Text('پشتیبان کامل و رمزگذاری‌شده'),
              subtitle: Text(
                'دیتابیس، PDF، عکس و سایر مدارک داخل فایل با AES-256-GCM رمزگذاری می‌شوند. رمز فایل در برنامه ذخیره نمی‌شود و بدون آن بازیابی ممکن نیست.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _working ? null : _createBackup,
            icon: _working
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.backup),
            label: const Text('اکنون پشتیبان رمزگذاری‌شده بگیر'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickAndRestoreBackup,
            icon: const Icon(Icons.file_open),
            label: const Text('بررسی و بازیابی فایل پشتیبان'),
          ),
          const SizedBox(height: 16),
          SelectableText(message),
          const SizedBox(height: 16),
          Text('پشتیبان‌های موجود: ${toPersianDigits(backups.length)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (backups.isEmpty)
            const Card(child: ListTile(title: Text('هنوز پشتیبانی ثبت نشده است.')))
          else
            for (final file in backups)
              Card(
                child: ListTile(
                  leading: Icon(
                    p.extension(file.path).toLowerCase() == '.kybackup' ? Icons.lock_outline : Icons.warning_amber_outlined,
                  ),
                  title: Text(p.basename(file.path)),
                  subtitle: Text(
                    '${formatSimpleDateTime(file.lastModifiedSync())}\n${_formatBytes(file.lengthSync())} — ${p.extension(file.path).toLowerCase() == '.kybackup' ? 'رمزگذاری‌شده' : 'پشتیبان قدیمی'}',
                  ),
                  isThreeLine: true,
                  onTap: _working ? null : () => _restore(file),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'گزینه‌های پشتیبان',
                    enabled: !_working,
                    onSelected: (value) {
                      if (value == 'share') _shareBackup(file);
                      if (value == 'delete') _deleteBackup(file);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'share', child: Text('اشتراک‌گذاری / ذخیره بیرون برنامه')),
                      PopupMenuItem(value: 'delete', child: Text('حذف پشتیبان')),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _RestoreCredentials {
  const _RestoreCredentials({required this.newPin});

  final String newPin;
}
