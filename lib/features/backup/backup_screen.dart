import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../database/database_provider.dart';
import '../../core/utils/date_format_fa.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String message = 'پشتیبان‌گیری خودکار فعال است.';
  List<File> backups = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final db = ref.read(databaseProvider);
    final files = await db.listBackups();
    if (!mounted) return;
    setState(() => backups = files);
  }

  Future<void> _createBackup() async {
    final db = ref.read(databaseProvider);
    final file = await db.createBackup(reason: 'manual');
    await _refresh();
    if (!mounted) return;
    setState(() => message = file == null ? 'فایل داده هنوز ایجاد نشده است.' : 'پشتیبان ساخته شد:\n${file.path}');
  }

  Future<void> _restore(File file) async {
    final db = ref.read(databaseProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بازیابی پشتیبان'),
        content: const Text('قبل از بازیابی، یک پشتیبان اضطراری از وضعیت فعلی گرفته می‌شود. ادامه می‌دهی؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بازیابی')),
        ],
      ),
    );
    if (ok != true) return;
    await db.restoreBackup(file);
    await _refresh();
    if (!mounted) return;
    setState(() => message = 'بازیابی انجام شد. برنامه را یک بار ببند و باز کن تا همه صفحه‌ها تازه شوند.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پشتیبان‌گیری')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.backup),
              title: Text('پشتیبان‌گیری خودکار چرخشی'),
              subtitle: Text('بعد از ثبت یا ویرایش اطلاعات، پشتیبان ساخته می‌شود. فقط ۱۰ پشتیبان آخر نگهداری می‌شود.'),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _createBackup,
            icon: const Icon(Icons.backup),
            label: const Text('اکنون پشتیبان بگیر'),
          ),
          const SizedBox(height: 16),
          SelectableText(message),
          const SizedBox(height: 16),
          Text('پشتیبان‌های موجود: ${backups.length}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (backups.isEmpty)
            const Card(child: ListTile(title: Text('هنوز پشتیبانی ثبت نشده است.')))
          else
            for (final file in backups)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text(p.basename(file.path)),
                  subtitle: Text(formatSimpleDateTime(file.lastModifiedSync())),
                  onTap: () => _restore(file),
                ),
              ),
        ],
      ),
    );
  }
}
