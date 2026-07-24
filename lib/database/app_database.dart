import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../core/security/backup_crypto.dart';
import '../features/notifications/notification_service.dart';

/// Lightweight local JSON database for KouroshYar.
///
/// Lightweight local storage used by the app screens.
const String kouroshyarDatabaseFileName = 'kouroshyar_data.json';
const String kouroshyarInstallGuardFileName = 'kouroshyar_install_guard_v1.json';
const String kouroshyarSecurityPolicyVersion = 'v3_6_51_encrypted_backup_notifications_v5';
const String kouroshyarBackupFormat = 'kouroshyar-backup-v1';
const MethodChannel _kouroshyarNoBackupChannel = MethodChannel('kouroshyar/no_backup');

class Value<T> {
  final T? value;
  final bool present;

  const Value(this.value) : present = true;
  const Value.absent()
      : value = null,
        present = false;
}

T _valueOr<T>(Value<T>? value, T fallback) {
  if (value == null || !value.present) return fallback;
  return value.value as T;
}

T? _nullableValueOr<T>(Value<T?>? value, T? fallback) {
  if (value == null || !value.present) return fallback;
  return value.value;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String _normalizePersonKey(String value) => value
    .trim()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp(r'[\s\u200c]+'), ' ')
    .toLowerCase();

DateTime? _dateOrNull(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

DateTime _dateOrNow(Object? value) => _dateOrNull(value) ?? DateTime.now();

typedef RowPredicate<T> = bool Function(T row);

class ColumnRef<T, V> {
  const ColumnRef(this.read);
  final V Function(T row) read;

  RowPredicate<T> equals(Object? value) => (row) => read(row) == value;
}

abstract class TableRef<T> {
  TableRef({
    required this.name,
    required this.fromJson,
    required this.toJson,
    required this.fromCompanion,
  });

  final String name;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T item) toJson;
  final T Function(Object companion, int id) fromCompanion;
}

class SelectQuery<T> {
  SelectQuery(this._db, this._table);

  final AppDatabase _db;
  final TableRef<T> _table;
  RowPredicate<T>? _predicate;

  void where(RowPredicate<T> Function(dynamic table) buildPredicate) {
    _predicate = buildPredicate(_table);
  }

  Future<List<T>> get() async {
    final items = await _db._readTable(_table);
    final predicate = _predicate;
    final filtered = predicate == null ? items : items.where(predicate).toList();
    // Return a normal mutable list. Several UI screens sort/filter this result
    // before rendering; returning List.unmodifiable causes runtime red-screen
    // errors such as: Unsupported operation: Cannot modify an unmodifiable list.
    return List<T>.of(filtered);
  }

  Stream<List<T>> watch() async* {
    yield await get();
    await for (final changed in _db._changes.stream) {
      if (changed == _table.name || changed == '*') {
        yield await get();
      }
    }
  }
}

class InsertStatement<T> {
  InsertStatement(this._db, this._table);

  final AppDatabase _db;
  final TableRef<T> _table;

  Future<int> insert(Object companion) async {
    final id = await _db._nextId(_table);
    final item = _table.fromCompanion(companion, id);
    final items = await _db._readTable(_table);
    items.add(item);
    await _db._writeTable(_table, items);
    return id;
  }
}

class UpdateStatement<T> {
  UpdateStatement(this._db, this._table);

  final AppDatabase _db;
  final TableRef<T> _table;

  Future<bool> replace(T item) async {
    final id = (item as dynamic).id as int;
    final items = await _db._readTable(_table);
    final index = items.indexWhere((e) => (e as dynamic).id == id);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
    await _db._writeTable(_table, items);
    return true;
  }
}

class DeleteStatement<T> {
  DeleteStatement(this._db, this._table);

  final AppDatabase _db;
  final TableRef<T> _table;
  RowPredicate<T>? _predicate;

  void where(RowPredicate<T> Function(dynamic table) buildPredicate) {
    _predicate = buildPredicate(_table);
  }

  Future<int> go() async {
    final predicate = _predicate;
    if (predicate == null) return 0;
    final items = await _db._readTable(_table);
    final before = items.length;
    items.removeWhere(predicate);
    await _db._writeTable(_table, items);
    return before - items.length;
  }
}

class AppDatabase {
  AppDatabase();

  final cases = CasesTable();
  final tasks = TasksTable();
  final legalTexts = LegalTextsTable();
  final inboxItems = InboxItemsTable();
  final caseDocuments = CaseDocumentsTable();
  final caseTimelineEvents = CaseTimelineEventsTable();
  final casePeople = CasePeopleTable();
  final deadlines = DeadlinesTable();
  final financeItems = FinanceItemsTable();
  final generatedDrafts = GeneratedDraftsTable();
  final experienceItems = ExperienceItemsTable();
  final checklistTemplates = ChecklistTemplatesTable();
  final securitySettings = SecuritySettingsTable();
  final userProfiles = UserProfilesTable();
  final aiSettings = AiSettingsTable();
  final calendarSettings = CalendarSettingsTable();
  final personalNotes = PersonalNotesTable();
  final personalAccountPersons = PersonalAccountPersonsTable();
  final personalAccountTransactions = PersonalAccountTransactionsTable();

  final StreamController<String> _changes = StreamController<String>.broadcast();
  Map<String, dynamic>? _store;
  File? _file;
  Future<void> _saveQueue = Future<void>.value();
  String? startupRecoveryNotice;

  Future<void> close() async {
    await _changes.close();
  }

  SelectQuery<T> select<T>(TableRef<T> table) => SelectQuery<T>(this, table);

  Stream<int> watchAny() async* {
    var revision = 0;
    yield revision;
    await for (final _ in _changes.stream) {
      revision += 1;
      yield revision;
    }
  }

  InsertStatement<T> into<T>(TableRef<T> table) => InsertStatement<T>(this, table);
  UpdateStatement<T> update<T>(TableRef<T> table) => UpdateStatement<T>(this, table);
  DeleteStatement<T> delete<T>(TableRef<T> table) => DeleteStatement<T>(this, table);


  Future<Directory> _noBackupDirectory() async {
    try {
      final path = await _kouroshyarNoBackupChannel.invokeMethod<String>('getNoBackupPath');
      if (path != null && path.trim().isNotEmpty) {
        final dir = Directory(path.trim());
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {
      // Fallback is used only if the Android method channel is unavailable.
    }

    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'no_backup_guard'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _newInstallGuardId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String> _readOrCreateInstallGuardId() async {
    final dir = await _noBackupDirectory();
    final file = File(p.join(dir.path, kouroshyarInstallGuardFileName));
    try {
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['installGuardId'] is String && (decoded['installGuardId'] as String).isNotEmpty) {
          return decoded['installGuardId'] as String;
        }
      }
    } catch (_) {}

    final id = _newInstallGuardId();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert({
      'installGuardId': id,
      'createdAt': DateTime.now().toIso8601String(),
      'note': 'This marker is stored in Android no-backup storage and must not be restored from cloud/device backup.',
    }));
    return id;
  }

  Map<String, dynamic> _meta() {
    final store = _store ?? <String, dynamic>{};
    final raw = store['meta'];
    final meta = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    store['meta'] = meta;
    _store = store;
    return meta;
  }

  bool _hasUserDataInStore() {
    final store = _store ?? const <String, dynamic>{};
    const userTables = [
      'cases',
      'tasks',
      'caseDocuments',
      'caseTimelineEvents',
      'casePeople',
      'deadlines',
      'financeItems',
      'generatedDrafts',
      'experienceItems',
      'inboxItems',
      'legalTexts',
      'checklistTemplates',
      'userProfiles',
      'personalNotes',
      'personalAccountPersons',
      'personalAccountTransactions',
    ];
    for (final table in userTables) {
      final rows = store[table];
      if (rows is List && rows.isNotEmpty) return true;
    }
    return false;
  }

  bool _hasLegacySecurityLockInStore() {
    final store = _store ?? const <String, dynamic>{};
    final rows = store['securitySettings'];
    if (rows is! List) return false;
    for (final row in rows.whereType<Map>()) {
      if (row['appLockEnabled'] == true) return true;
      final pin = row['pinCode'];
      if (pin is String && pin.trim().isNotEmpty) return true;
      if (row['biometricEnabled'] == true) return true;
    }
    return false;
  }


  Future<void> _deleteSensitiveLocalDirectories() async {
    final docDir = await getApplicationDocumentsDirectory();
    final supportDir = await getApplicationSupportDirectory();
    final tempDir = await getTemporaryDirectory();

    Future<void> deleteIfExists(FileSystemEntity entity) async {
      try {
        if (await entity.exists()) await entity.delete(recursive: true);
      } catch (_) {}
    }

    final dbFile = _file ?? await databaseFile();
    await deleteIfExists(File('${dbFile.path}.bak'));
    await deleteIfExists(Directory(p.join(docDir.path, 'kouroshyar_backups')));
    await deleteIfExists(Directory(p.join(docDir.path, 'case_documents')));
    await deleteIfExists(Directory(p.join(docDir.path, 'case_attachments')));
    await deleteIfExists(Directory(p.join(docDir.path, 'documents')));
    await deleteIfExists(Directory(p.join(supportDir.path, 'kouroshyar_backups')));
    await deleteIfExists(Directory(p.join(supportDir.path, 'case_documents')));
    await deleteIfExists(Directory(p.join(supportDir.path, 'case_attachments')));
    await deleteIfExists(Directory(p.join(tempDir.path, 'kouroshyar')));
  }

  Future<void> _replaceWithEmptyStore(String installGuardId, {required String reason}) async {
    await _deleteSensitiveLocalDirectories();
    _store = <String, dynamic>{
      'meta': <String, dynamic>{
        'security_backup_policy': kouroshyarSecurityPolicyVersion,
        'install_guard_id': installGuardId,
        'install_guard_reason': reason,
        'security_reset_at': DateTime.now().toIso8601String(),
      },
    };
    await _save();
    _changes.add('*');
  }

  Future<bool> _enforceInstallGuard({required bool databaseExisted}) async {
    final installGuardId = await _readOrCreateInstallGuardId();
    final meta = _meta();
    final storedGuard = meta['install_guard_id'];

    if (databaseExisted && storedGuard is String && storedGuard.isNotEmpty && storedGuard != installGuardId) {
      await _replaceWithEmptyStore(installGuardId, reason: 'restored_database_from_previous_install_blocked');
      return true;
    }

    // Legacy databases created before this guard may have been restored by Android/Samsung backup.
    // If they already contain the old app lock/password/biometric state, treat them as untrusted
    // and start clean. This prevents the reported case where uninstall + clear data + reinstall
    // still brought cases and app lock back from backup.
    final legacyWithoutGuard = storedGuard == null || (storedGuard is String && storedGuard.isEmpty);
    if (databaseExisted && legacyWithoutGuard && _hasUserDataInStore()) {
      await _replaceWithEmptyStore(installGuardId, reason: _hasLegacySecurityLockInStore()
          ? 'legacy_backup_with_app_lock_blocked'
          : 'legacy_backup_with_user_data_blocked');
      return true;
    }

    if (storedGuard != installGuardId) {
      meta['install_guard_id'] = installGuardId;
    }
    return false;
  }

  Future<File> databaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, kouroshyarDatabaseFileName));
  }

  Future<Map<String, dynamic>?> _readValidStore(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_store != null) return;
    _file = await databaseFile();
    final mainFile = _file!;
    final tempFile = File('${mainFile.path}.tmp');
    final backupFile = File('${mainFile.path}.bak');
    final databaseExisted = await mainFile.exists();

    Map<String, dynamic>? decoded = await _readValidStore(mainFile);
    String? recoveredFrom;
    if (decoded == null) {
      decoded = await _readValidStore(tempFile);
      if (decoded != null) recoveredFrom = 'فایل موقت سالم';
    }
    if (decoded == null) {
      decoded = await _readValidStore(backupFile);
      if (decoded != null) recoveredFrom = 'نسخه ایمن قبلی';
    }

    if (decoded == null) {
      if (databaseExisted) {
        final corrupt = File('${mainFile.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}.bak');
        try {
          await mainFile.copy(corrupt.path);
        } catch (_) {}
        startupRecoveryNotice = 'فایل داده آسیب دیده بود و نسخه خالی امن ایجاد شد. نسخه خراب برای بازیابی تخصصی نگهداری شد.';
      }
      _store = <String, dynamic>{'meta': <String, dynamic>{}};
      final handled = await _enforceInstallGuard(databaseExisted: false);
      if (!handled) {
        _applySecurityMigrations();
        await _save();
      }
      return;
    }

    _store = decoded;
    if (recoveredFrom != null) {
      startupRecoveryNotice = 'اطلاعات برنامه از $recoveredFrom بازیابی شد.';
      _meta()['recovered_at'] = DateTime.now().toIso8601String();
      _meta()['recovered_from'] = recoveredFrom;
      await _save();
    }

    final handled = await _enforceInstallGuard(databaseExisted: databaseExisted);
    if (handled) return;
    if (_applySecurityMigrations()) {
      await _save();
    } else {
      final meta = _meta();
      if (meta['security_backup_policy'] != kouroshyarSecurityPolicyVersion) {
        meta['security_backup_policy'] = kouroshyarSecurityPolicyVersion;
        await _save();
      }
    }
  }

  bool _applySecurityMigrations() {
    final meta = _meta();
    var changed = false;
    if (meta['security_backup_policy'] != kouroshyarSecurityPolicyVersion) {
      // Legacy security settings remain usable, but their password hash is
      // upgraded automatically after the next successful unlock.
      meta['security_backup_policy'] = kouroshyarSecurityPolicyVersion;
      meta['security_migrated_at'] = DateTime.now().toIso8601String();
      changed = true;
    }

    final personRows = (_store?['personalAccountPersons'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final transactionRows = (_store?['personalAccountTransactions'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    if (personRows.isNotEmpty && transactionRows.isNotEmpty) {
      final byName = <String, Map>{};
      for (final row in personRows) {
        final key = _normalizePersonKey((row['name'] ?? '').toString());
        if (key.isNotEmpty) byName.putIfAbsent(key, () => row);
      }
      for (final row in transactionRows) {
        if (row['personId'] is num) continue;
        final person = byName[_normalizePersonKey((row['personName'] ?? '').toString())];
        if (person != null && person['id'] is num) {
          row['personId'] = (person['id'] as num).toInt();
          row['personName'] = (person['name'] ?? row['personName']).toString();
          changed = true;
        }
      }
    }
    return changed;
  }

  Future<void> _save() {
    final completer = Completer<void>();
    final payload = jsonEncode(_store ?? <String, dynamic>{'meta': <String, dynamic>{}});
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      try {
        await _savePayloadAtomically(payload);
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> _savePayloadAtomically(String payload) async {
    final file = _file ?? await databaseFile();
    _file = file;
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final tempFile = File('${file.path}.tmp');
    final backupFile = File('${file.path}.bak');
    await tempFile.writeAsString(payload, flush: true);

    final verified = await _readValidStore(tempFile);
    if (verified == null) {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      throw const FormatException('ذخیره موقت دیتابیس قابل اعتبارسنجی نیست.');
    }

    if (await file.exists()) {
      final currentIsValid = await _readValidStore(file) != null;
      if (currentIsValid) {
        if (await backupFile.exists()) await backupFile.delete();
        await file.rename(backupFile.path);
      } else {
        await file.delete();
      }
    }
    try {
      await tempFile.rename(file.path);
      // Keep the last valid database as .bak for startup recovery.
    } catch (_) {
      if (!await file.exists() && await backupFile.exists()) await backupFile.rename(file.path);
      rethrow;
    }
  }

  Future<Directory> backupDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'kouroshyar_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<List<File>> _collectBackupFiles() async {
    final docDir = await getApplicationDocumentsDirectory();
    final supportDir = await getApplicationSupportDirectory();
    final roots = <Directory>[
      Directory(p.join(docDir.path, 'case_documents')),
      Directory(p.join(docDir.path, 'case_attachments')),
      Directory(p.join(docDir.path, 'documents')),
      Directory(p.join(supportDir.path, 'case_documents')),
      Directory(p.join(supportDir.path, 'case_attachments')),
    ];
    final files = <File>[];
    final seen = <String>{};
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final normalized = p.normalize(entity.absolute.path);
        if (seen.add(normalized)) files.add(entity);
      }
    }
    return files;
  }

  Future<int> estimateBackupInputSizeBytes() async {
    await _ensureLoaded();
    await _saveQueue;
    var total = 0;
    final source = _file ?? await databaseFile();
    if (await source.exists()) total += await source.length();
    for (final file in await _collectBackupFiles()) {
      try {
        total += await file.length();
      } catch (_) {
        // A file that disappears during estimation will be handled again while
        // the actual backup is being built.
      }
    }
    return total;
  }

  Future<Uint8List> _buildBackupZipBytes() async {
    final source = _file ?? await databaseFile();
    if (!await source.exists()) {
      throw const FileSystemException('فایل داده هنوز ایجاد نشده است.');
    }

    final archive = Archive();
    final dbBytes = await source.readAsBytes();
    archive.addFile(ArchiveFile('database/kouroshyar_data.json', dbBytes.length, dbBytes));
    final manifestFiles = <Map<String, dynamic>>[];
    final attachments = await _collectBackupFiles();
    for (var index = 0; index < attachments.length; index++) {
      final file = attachments[index];
      final bytes = await file.readAsBytes();
      final safeBase = p.basename(file.path).replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
      final entryName = 'files/${index.toString().padLeft(6, '0')}_$safeBase';
      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      manifestFiles.add({
        'entry': entryName,
        'originalPath': p.normalize(file.absolute.path),
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
    final now = DateTime.now();
    final manifest = <String, dynamic>{
      'format': kouroshyarBackupFormat,
      'createdAt': now.toIso8601String(),
      'appVersion': '3.6.60+132',
      'databaseSha256': sha256.convert(dbBytes).toString(),
      'files': manifestFiles,
    };
    final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw const FileSystemException('ساخت فایل ZIP پشتیبان انجام نشد.');
    return Uint8List.fromList(zipBytes);
  }

  Future<File?> createBackup({
    String reason = 'auto',
    String? password,
  }) async {
    await _ensureLoaded();
    await _saveQueue;
    final source = _file ?? await databaseFile();
    if (!await source.exists()) return null;

    final backupDir = await backupDirectory();
    final now = DateTime.now();
    final stamp = [
      now.year.toString().padLeft(4, '0'),
      now.month.toString().padLeft(2, '0'),
      now.day.toString().padLeft(2, '0'),
      now.hour.toString().padLeft(2, '0'),
      now.minute.toString().padLeft(2, '0'),
      now.second.toString().padLeft(2, '0'),
    ].join('');
    final safeReason = reason.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final encrypted = password != null && password.trim().isNotEmpty;
    final extension = encrypted ? 'kybackup' : 'zip';
    final backup = File(p.join(backupDir.path, 'kouroshyar_backup_${stamp}_$safeReason.$extension'));

    final zipBytes = await _buildBackupZipBytes();
    final outputBytes = encrypted
        ? await BackupCrypto.encryptBytes(zipBytes, password: password.trim())
        : zipBytes;
    final temporary = File('${backup.path}.tmp');
    try {
      await temporary.writeAsBytes(outputBytes, flush: true);
      if (await backup.exists()) await backup.delete();
      await temporary.rename(backup.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    await _trimBackups(maxCount: 10);
    return backup;
  }

  Future<List<File>> listBackups() async {
    final backupDir = await backupDirectory();
    final files = await backupDir
        .list()
        .where((entity) {
          if (entity is! File) return false;
          final name = p.basename(entity.path);
          final extension = p.extension(name).toLowerCase();
          return name.startsWith('kouroshyar_backup_') && (extension == '.zip' || extension == '.kybackup');
        })
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> deleteBackup(File backup) async {
    final backupDir = await backupDirectory();
    final backupPath = p.normalize(backup.absolute.path);
    final allowedDir = p.normalize(backupDir.absolute.path);
    if (!p.isWithin(allowedDir, backupPath)) throw FileSystemException('فایل انتخاب‌شده داخل پوشه پشتیبان داخلی نیست.');
    if (await backup.exists()) await backup.delete();
  }

  Future<bool> isEncryptedBackup(File backup) async {
    if (!await backup.exists()) return false;
    final randomAccess = await backup.open();
    try {
      final prefix = await randomAccess.read(64);
      return BackupCrypto.isEncryptedBytes(prefix);
    } finally {
      await randomAccess.close();
    }
  }

  Future<Uint8List> _readBackupZipBytes(
    File backup, {
    String? password,
  }) async {
    final rawBytes = await backup.readAsBytes();
    if (!BackupCrypto.isEncryptedBytes(rawBytes)) return rawBytes;
    if (password == null || password.trim().isEmpty) {
      throw const BackupDecryptionException('این فایل پشتیبان رمزگذاری شده است؛ رمز آن را وارد کنید.');
    }
    return BackupCrypto.decryptBytes(rawBytes, password: password.trim());
  }

  ({Archive archive, Map<String, dynamic> manifest, Uint8List databaseBytes, Map<String, dynamic> data})
      _parseBackupArchive(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    ArchiveFile? manifestFile;
    ArchiveFile? databaseEntry;
    for (final entry in archive.files) {
      if (entry.name == 'manifest.json') manifestFile = entry;
      if (entry.name == 'database/kouroshyar_data.json') databaseEntry = entry;
    }
    if (manifestFile == null || databaseEntry == null) {
      throw const FormatException('ساختار ZIP پشتیبان کوروش‌یار کامل نیست.');
    }
    final manifestRaw = jsonDecode(utf8.decode(List<int>.from(manifestFile.content as List)));
    if (manifestRaw is! Map || manifestRaw['format'] != kouroshyarBackupFormat) {
      throw const FormatException('نسخه یا قالب پشتیبان پشتیبانی نمی‌شود.');
    }
    final manifest = Map<String, dynamic>.from(manifestRaw);
    final databaseBytes = Uint8List.fromList(List<int>.from(databaseEntry.content as List));
    if (sha256.convert(databaseBytes).toString() != manifest['databaseSha256']) {
      throw const FormatException('کنترل صحت دیتابیس پشتیبان ناموفق بود.');
    }
    final decodedRaw = jsonDecode(utf8.decode(databaseBytes));
    if (decodedRaw is! Map) throw const FormatException('دیتابیس داخل پشتیبان معتبر نیست.');
    return (
      archive: archive,
      manifest: manifest,
      databaseBytes: databaseBytes,
      data: Map<String, dynamic>.from(decodedRaw),
    );
  }

  Future<BackupSummary> inspectBackup(
    File backup, {
    String? password,
  }) async {
    final encrypted = await isEncryptedBackup(backup);
    final extension = p.extension(backup.path).toLowerCase();
    if (extension == '.json') {
      final decoded = jsonDecode(await backup.readAsString());
      if (decoded is! Map) throw const FormatException('پشتیبان JSON معتبر نیست.');
      final data = Map<String, dynamic>.from(decoded);
      return BackupSummary(
        encrypted: false,
        appVersion: 'نسخه قدیمی',
        createdAt: backup.lastModifiedSync(),
        caseCount: (data['cases'] as List?)?.length ?? 0,
        attachmentCount: 0,
        sizeBytes: await backup.length(),
      );
    }
    final zipBytes = await _readBackupZipBytes(backup, password: password);
    final parsed = _parseBackupArchive(zipBytes);
    final files = parsed.manifest['files'];
    return BackupSummary(
      encrypted: encrypted,
      appVersion: parsed.manifest['appVersion']?.toString() ?? 'نامشخص',
      createdAt: DateTime.tryParse(parsed.manifest['createdAt']?.toString() ?? '') ?? backup.lastModifiedSync(),
      caseCount: (parsed.data['cases'] as List?)?.length ?? 0,
      attachmentCount: files is List ? files.length : 0,
      sizeBytes: await backup.length(),
    );
  }

  dynamic _replacePaths(dynamic value, Map<String, String> replacements) {
    if (value is String) return replacements[p.normalize(value)] ?? value;
    if (value is List) return value.map((item) => _replacePaths(item, replacements)).toList();
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _replacePaths(item, replacements)));
    }
    return value;
  }

  Future<({Map<String, dynamic> data, Directory extractedRoot})> _decodeZipBackupBytes(List<int> zipBytes) async {
    final parsed = _parseBackupArchive(zipBytes);
    final archive = parsed.archive;
    final manifest = parsed.manifest;
    final decoded = parsed.data;

    // همه فایل‌ها ابتدا در حافظه اعتبارسنجی می‌شوند تا پشتیبان ناقص، پوشه نیمه‌کاره نسازد.
    final validatedFiles = <({String originalPath, String fileName, List<int> bytes})>[];
    final fileRows = manifest['files'];
    if (fileRows is List) {
      final byName = {for (final entry in archive.files) entry.name: entry};
      for (final raw in fileRows.whereType<Map>()) {
        final entryName = raw['entry']?.toString() ?? '';
        final originalPath = raw['originalPath']?.toString() ?? '';
        if (!entryName.startsWith('files/') || entryName.contains('..') || originalPath.isEmpty) {
          throw const FormatException('مسیر فایل در پشتیبان معتبر نیست.');
        }
        final entry = byName[entryName];
        if (entry == null || !entry.isFile) throw FormatException('فایل $entryName در پشتیبان پیدا نشد.');
        final fileBytes = List<int>.from(entry.content as List);
        if (fileBytes.length != (raw['size'] as num?)?.toInt() || sha256.convert(fileBytes).toString() != raw['sha256']) {
          throw FormatException('کنترل صحت فایل $entryName ناموفق بود.');
        }
        validatedFiles.add((originalPath: originalPath, fileName: p.basename(entryName), bytes: fileBytes));
      }
    }

    final docDir = await getApplicationDocumentsDirectory();
    final restoreRoot = Directory(
      p.join(docDir.path, 'case_attachments', 'restored_${DateTime.now().millisecondsSinceEpoch}'),
    );
    final replacements = <String, String>{};
    try {
      await restoreRoot.create(recursive: true);
      for (final file in validatedFiles) {
        final target = File(p.join(restoreRoot.path, file.fileName));
        await target.writeAsBytes(file.bytes, flush: true);
        replacements[p.normalize(file.originalPath)] = target.path;
      }
      final replaced = _replacePaths(Map<String, dynamic>.from(decoded), replacements);
      return (data: Map<String, dynamic>.from(replaced as Map), extractedRoot: restoreRoot);
    } catch (_) {
      if (await restoreRoot.exists()) await restoreRoot.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> restoreBackup(
    File backup, {
    required String newPinHash,
    String? backupPassword,
    required String emergencyBackupPassword,
  }) async {
    await _ensureLoaded();
    final previousStore = _store;
    Directory? extractedRoot;
    var committed = false;
    try {
      final extension = p.extension(backup.path).toLowerCase();
      Map<String, dynamic> decodedMap;
      if (extension == '.zip' || extension == '.kybackup') {
        final zipBytes = await _readBackupZipBytes(backup, password: backupPassword);
        final decoded = await _decodeZipBackupBytes(zipBytes);
        decodedMap = decoded.data;
        extractedRoot = decoded.extractedRoot;
      } else {
        final decoded = jsonDecode(await backup.readAsString());
        if (decoded is! Map) throw const FormatException('فایل انتخاب‌شده پشتیبان معتبر کوروش‌یار نیست.');
        decodedMap = Map<String, dynamic>.from(decoded);
      }
      final looksLikeKouroshYar =
          decodedMap.containsKey('cases') || decodedMap.containsKey('tasks') || decodedMap.containsKey('meta');
      if (!looksLikeKouroshYar) {
        throw const FormatException('فایل انتخاب‌شده ساختار پشتیبان کوروش‌یار را ندارد.');
      }

      // وضعیت فعلی قبل از بازیابی با رمز جدید کاربر در یک پشتیبان اضطراری
      // ذخیره می‌شود تا فایل حساس بدون رمز در حافظه باقی نماند.
      await createBackup(
        reason: 'before_manual_restore',
        password: emergencyBackupPassword,
      );

      final installGuardId = await _readOrCreateInstallGuardId();
      _store = decodedMap;
      final now = DateTime.now();
      _store!['securitySettings'] = <Map<String, dynamic>>[
        SecuritySetting(
          id: 1,
          appLockEnabled: true,
          pinCode: newPinHash,
          biometricEnabled: false,
          updatedAt: now,
        ).toJson(),
      ];
      final meta = _meta();
      meta['security_backup_policy'] = kouroshyarSecurityPolicyVersion;
      meta['install_guard_id'] = installGuardId;
      meta['manual_restore_at'] = now.toIso8601String();
      meta['security_lock_reset_at'] = now.toIso8601String();
      meta['requires_new_lock_after_restore'] = false;
      _file = _file ?? await databaseFile();
      await _save();
      committed = true;
      await syncNotifications();
      _changes.add('*');
    } catch (_) {
      if (!committed) {
        _store = previousStore;
        if (extractedRoot != null && await extractedRoot.exists()) {
          await extractedRoot.delete(recursive: true);
        }
      }
      rethrow;
    }
  }

  Future<void> _trimBackups({required int maxCount}) async {
    final files = await listBackups();
    if (files.length <= maxCount) return;
    for (final file in files.skip(maxCount)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> wipeAllLocalData() async {
    await _ensureLoaded();
    final docDir = await getApplicationDocumentsDirectory();
    final supportDir = await getApplicationSupportDirectory();
    final tempDir = await getTemporaryDirectory();

    Future<void> deleteIfExists(FileSystemEntity entity) async {
      try {
        if (await entity.exists()) {
          await entity.delete(recursive: true);
        }
      } catch (_) {
        // پاکسازی کامل نباید با خطای یک فایل متوقف شود.
      }
    }

    final dbFile = _file ?? await databaseFile();
    await deleteIfExists(dbFile);
    await deleteIfExists(File('${dbFile.path}.bak'));
    await deleteIfExists(File('${dbFile.path}.tmp'));
    try {
      await for (final entity in dbFile.parent.list()) {
        if (entity is File && p.basename(entity.path).startsWith('${p.basename(dbFile.path)}.corrupt_')) {
          await deleteIfExists(entity);
        }
      }
    } catch (_) {}
    await deleteIfExists(Directory(p.join(docDir.path, 'kouroshyar_backups')));
    await deleteIfExists(Directory(p.join(docDir.path, 'case_documents')));
    await deleteIfExists(Directory(p.join(docDir.path, 'case_attachments')));
    await deleteIfExists(Directory(p.join(docDir.path, 'documents')));
    await deleteIfExists(Directory(p.join(supportDir.path, 'kouroshyar_backups')));
    await deleteIfExists(Directory(p.join(supportDir.path, 'case_documents')));
    await deleteIfExists(Directory(p.join(supportDir.path, 'case_attachments')));
    await deleteIfExists(Directory(p.join(tempDir.path, 'kouroshyar')));

    final installGuardId = await _readOrCreateInstallGuardId();
    _store = <String, dynamic>{
      'meta': <String, dynamic>{
        'security_backup_policy': kouroshyarSecurityPolicyVersion,
        'install_guard_id': installGuardId,
        'wiped_at': DateTime.now().toIso8601String(),
      },
    };
    _file = dbFile;
    await _save();
    try {
      await NotificationService.cancelAll();
    } catch (_) {}
    _changes.add('*');
  }

  DateTime _historySafeDate(DateTime requested) {
    final now = DateTime.now();
    final requestedDay = DateTime(requested.year, requested.month, requested.day);
    final today = DateTime(now.year, now.month, now.day);
    if (requestedDay.isAfter(today)) return now;
    return requested;
  }

  Future<void> _syncTimelineEventRows(
    List<CaseTimelineEvent> events, {
    required int caseId,
    required String sourceType,
    required int sourceId,
    required String eventType,
    required String title,
    required DateTime eventDate,
    String? description,
    bool includeInNarrative = true,
    bool preserveExistingDate = false,
  }) async {
    final index = events.indexWhere(
      (event) => event.caseId == caseId && event.sourceType == sourceType && event.sourceId == sourceId,
    );
    if (index >= 0) {
      final existing = events[index];
      events[index] = existing.copyWith(
        title: title.trim().isEmpty ? eventType : title.trim(),
        eventType: Value<String?>(eventType),
        description: Value<String?>(_blankToNull(description)),
        eventDate: preserveExistingDate ? existing.eventDate : _historySafeDate(eventDate),
        isDone: true,
        includeInNarrative: includeInNarrative,
      );
      return;
    }

    final id = await _nextId(caseTimelineEvents);
    events.add(
      CaseTimelineEvent(
        id: id,
        caseId: caseId,
        title: title.trim().isEmpty ? eventType : title.trim(),
        eventType: eventType,
        description: _blankToNull(description),
        eventDate: _historySafeDate(eventDate),
        isDone: true,
        sourceType: sourceType,
        sourceId: sourceId,
        decisionSummary: null,
        actorRole: null,
        attachmentPath: null,
        attachmentName: null,
        attachmentType: null,
        includeInNarrative: includeInNarrative,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> ensureTimelineEventFromSource({
    required int caseId,
    required String sourceType,
    required int sourceId,
    required String eventType,
    required String title,
    required DateTime eventDate,
    String? description,
    bool includeInNarrative = true,
    bool preserveExistingDate = false,
  }) async {
    final events = await _readTable(caseTimelineEvents);
    await _syncTimelineEventRows(
      events,
      caseId: caseId,
      sourceType: sourceType,
      sourceId: sourceId,
      eventType: eventType,
      title: title,
      eventDate: eventDate,
      description: description,
      includeInNarrative: includeInNarrative,
      preserveExistingDate: preserveExistingDate,
    );
    await _writeTable(caseTimelineEvents, events);
  }

  Future<void> removeTimelineEventFromSource({
    required String sourceType,
    required int sourceId,
  }) async {
    final events = await _readTable(caseTimelineEvents);
    final before = events.length;
    events.removeWhere((event) => event.sourceType == sourceType && event.sourceId == sourceId);
    if (events.length == before) return;
    await _writeTable(caseTimelineEvents, events);
  }

  Future<void> setTaskDone(Task task, bool done) async {
    await _ensureLoaded();
    final taskRows = await _readTable(tasks);
    final taskIndex = taskRows.indexWhere((item) => item.id == task.id);
    final updatedTask = task.copyWith(isDone: done);
    if (taskIndex < 0) {
      taskRows.add(updatedTask);
    } else {
      taskRows[taskIndex] = updatedTask;
    }

    final events = await _readTable(caseTimelineEvents);
    if (done && task.caseId != null) {
      await _syncTimelineEventRows(
        events,
        caseId: task.caseId!,
        sourceType: 'task',
        sourceId: task.id,
        eventType: 'انجام کار / اقدام',
        title: 'انجام کار: ${task.title}',
        eventDate: DateTime.now(),
        description: 'عنوان کار: ${task.title}\nاولویت: ${task.priority}',
        includeInNarrative: true,
        preserveExistingDate: true,
      );
    } else {
      events.removeWhere((event) => event.sourceType == 'task' && event.sourceId == task.id);
    }

    _store![tasks.name] = taskRows.map(tasks.toJson).toList();
    _store![caseTimelineEvents.name] = events.map(caseTimelineEvents.toJson).toList();
    await _save();
    await _syncNotificationTable(tasks, taskRows);
    await _syncNotificationTable(caseTimelineEvents, events);
    _changes.add('*');
  }

  Future<void> setDeadlineDone(Deadline deadline, bool done) async {
    await _ensureLoaded();
    final deadlineRows = await _readTable(deadlines);
    final deadlineIndex = deadlineRows.indexWhere((item) => item.id == deadline.id);
    final updatedDeadline = deadline.copyWith(isDone: done);
    if (deadlineIndex < 0) {
      deadlineRows.add(updatedDeadline);
    } else {
      deadlineRows[deadlineIndex] = updatedDeadline;
    }

    final events = await _readTable(caseTimelineEvents);
    if (done && deadline.caseId != null) {
      await _syncTimelineEventRows(
        events,
        caseId: deadline.caseId!,
        sourceType: 'deadline',
        sourceId: deadline.id,
        eventType: 'انجام مهلت قانونی',
        title: 'انجام مهلت: ${deadline.title}',
        eventDate: DateTime.now(),
        description: [
          'نوع مهلت: ${deadline.deadlineType ?? deadline.title}',
          if ((deadline.notes ?? '').trim().isNotEmpty) deadline.notes!.trim(),
        ].join('\n'),
        includeInNarrative: true,
        preserveExistingDate: true,
      );
    } else {
      events.removeWhere((event) => event.sourceType == 'deadline' && event.sourceId == deadline.id);
    }

    _store![deadlines.name] = deadlineRows.map(deadlines.toJson).toList();
    _store![caseTimelineEvents.name] = events.map(caseTimelineEvents.toJson).toList();
    await _save();
    await _syncNotificationTable(deadlines, deadlineRows);
    await _syncNotificationTable(caseTimelineEvents, events);
    _changes.add('*');
  }

  Future<void> setCaseSessionDone(CaseTimelineEvent session, bool done) async {
    await _ensureLoaded();
    final events = await _readTable(caseTimelineEvents);
    final sessionIndex = events.indexWhere((item) => item.id == session.id);
    final updatedSession = session.copyWith(isDone: done);
    if (sessionIndex < 0) {
      events.add(updatedSession);
    } else {
      events[sessionIndex] = updatedSession;
    }

    if (done) {
      await _syncTimelineEventRows(
        events,
        caseId: session.caseId,
        sourceType: 'hearing',
        sourceId: session.id,
        eventType: 'برگزاری جلسه رسیدگی',
        title: 'برگزاری جلسه: ${session.title}',
        eventDate: session.eventDate,
        description: [
          'نوع جلسه: ${session.title}',
          if ((session.description ?? '').trim().isNotEmpty) session.description!.trim(),
        ].join('\n'),
        includeInNarrative: true,
      );
    } else {
      events.removeWhere((event) => event.sourceType == 'hearing' && event.sourceId == session.id);
    }

    _store![caseTimelineEvents.name] = events.map(caseTimelineEvents.toJson).toList();
    await _save();
    await _syncNotificationTable(caseTimelineEvents, events);
    _changes.add('*');
  }

  Future<void> deleteTaskWithTimeline(int taskId) async {
    await _ensureLoaded();
    final taskRows = await _readTable(tasks);
    taskRows.removeWhere((item) => item.id == taskId);
    final events = await _readTable(caseTimelineEvents);
    events.removeWhere((event) => event.sourceType == 'task' && event.sourceId == taskId);
    _store![tasks.name] = taskRows.map(tasks.toJson).toList();
    _store![caseTimelineEvents.name] = events.map(caseTimelineEvents.toJson).toList();
    await _save();
    await _syncNotificationTable(tasks, taskRows);
    await _syncNotificationTable(caseTimelineEvents, events);
    _changes.add('*');
  }

  Future<void> deleteDeadlineWithTimeline(int deadlineId) async {
    await _ensureLoaded();
    final deadlineRows = await _readTable(deadlines);
    deadlineRows.removeWhere((item) => item.id == deadlineId);
    final events = await _readTable(caseTimelineEvents);
    events.removeWhere((event) => event.sourceType == 'deadline' && event.sourceId == deadlineId);
    _store![deadlines.name] = deadlineRows.map(deadlines.toJson).toList();
    _store![caseTimelineEvents.name] = events.map(caseTimelineEvents.toJson).toList();
    await _save();
    await _syncNotificationTable(deadlines, deadlineRows);
    await _syncNotificationTable(caseTimelineEvents, events);
    _changes.add('*');
  }

  Future<void> deleteCaseSessionWithTimeline(int sessionId) async {
    await _ensureLoaded();
    final events = await _readTable(caseTimelineEvents);
    events.removeWhere(
      (event) => event.id == sessionId || (event.sourceType == 'hearing' && event.sourceId == sessionId),
    );
    _store![caseTimelineEvents.name] = events.map(caseTimelineEvents.toJson).toList();
    await _save();
    await _syncNotificationTable(caseTimelineEvents, events);
    _changes.add('*');
  }

  Future<void> updatePersonalAccountPersonWithTransactions(
    PersonalAccountPerson person, {
    required String previousName,
  }) async {
    await _ensureLoaded();
    final persons = await _readTable(personalAccountPersons);
    final personIndex = persons.indexWhere((item) => item.id == person.id);
    if (personIndex < 0) {
      persons.add(person);
    } else {
      persons[personIndex] = person;
    }

    final oldKey = _normalizePersonKey(previousName);
    final transactions = await _readTable(personalAccountTransactions);
    for (var i = 0; i < transactions.length; i++) {
      final item = transactions[i];
      final belongsToPerson = item.personId == person.id ||
          (item.personId == null && _normalizePersonKey(item.personName) == oldKey);
      if (!belongsToPerson) continue;
      transactions[i] = item.copyWith(
        personId: Value<int?>(person.id),
        personName: person.name,
      );
    }

    _store![personalAccountPersons.name] = persons.map(personalAccountPersons.toJson).toList();
    _store![personalAccountTransactions.name] = transactions.map(personalAccountTransactions.toJson).toList();
    await _save();
    _changes.add('*');
  }

  Future<void> deletePersonalAccountPersonCascade({
    int? personId,
    required String personName,
  }) async {
    await _ensureLoaded();
    final nameKey = _normalizePersonKey(personName);
    final persons = await _readTable(personalAccountPersons);
    final idsToDelete = <int>{
      if (personId != null) personId,
      ...persons
          .where((item) => personId == null && _normalizePersonKey(item.name) == nameKey)
          .map((item) => item.id),
    };
    persons.removeWhere((item) => idsToDelete.contains(item.id));

    final transactions = await _readTable(personalAccountTransactions);
    transactions.removeWhere((item) =>
        (item.personId != null && idsToDelete.contains(item.personId)) ||
        (item.personId == null && _normalizePersonKey(item.personName) == nameKey));

    _store![personalAccountPersons.name] = persons.map(personalAccountPersons.toJson).toList();
    _store![personalAccountTransactions.name] = transactions.map(personalAccountTransactions.toJson).toList();
    await _save();
    _changes.add('*');
  }

  String? takeStartupRecoveryNotice() {
    final notice = startupRecoveryNotice;
    startupRecoveryNotice = null;
    return notice;
  }

  Future<void> deleteCaseCascade(int caseId) async {
    await _ensureLoaded();
    final peopleRows = await _readTable(casePeople);
    final timelineRows = await _readTable(caseTimelineEvents);
    final documentRows = await _readTable(caseDocuments);
    final taskRows = await _readTable(tasks);
    final deadlineRows = await _readTable(deadlines);
    final financeRows = await _readTable(financeItems);
    final draftRows = await _readTable(generatedDrafts);
    final experienceRows = await _readTable(experienceItems);
    final caseRows = await _readTable(cases);

    final attachmentPaths = <String>{
      ...timelineRows
          .where((item) => item.caseId == caseId)
          .map((item) => item.attachmentPath)
          .whereType<String>()
          .where((path) => path.trim().isNotEmpty),
      ...financeRows
          .where((item) => item.caseId == caseId)
          .map((item) => item.attachmentPath)
          .whereType<String>()
          .where((path) => path.trim().isNotEmpty),
      ...documentRows
          .where((item) => item.caseId == caseId)
          .map((item) => item.filePath)
          .whereType<String>()
          .where((path) => path.trim().isNotEmpty),
    };

    peopleRows.removeWhere((item) => item.caseId == caseId);
    timelineRows.removeWhere((item) => item.caseId == caseId);
    documentRows.removeWhere((item) => item.caseId == caseId);
    taskRows.removeWhere((item) => item.caseId == caseId);
    deadlineRows.removeWhere((item) => item.caseId == caseId);
    financeRows.removeWhere((item) => item.caseId == caseId);
    draftRows.removeWhere((item) => item.caseId == caseId);
    experienceRows.removeWhere((item) => item.caseId == caseId);
    caseRows.removeWhere((item) => item.id == caseId);

    _store![casePeople.name] = peopleRows.map(casePeople.toJson).toList();
    _store![caseTimelineEvents.name] = timelineRows.map(caseTimelineEvents.toJson).toList();
    _store![caseDocuments.name] = documentRows.map(caseDocuments.toJson).toList();
    _store![tasks.name] = taskRows.map(tasks.toJson).toList();
    _store![deadlines.name] = deadlineRows.map(deadlines.toJson).toList();
    _store![financeItems.name] = financeRows.map(financeItems.toJson).toList();
    _store![generatedDrafts.name] = draftRows.map(generatedDrafts.toJson).toList();
    _store![experienceItems.name] = experienceRows.map(experienceItems.toJson).toList();
    _store![cases.name] = caseRows.map(cases.toJson).toList();
    await _save();
    await _syncNotificationTable(tasks, taskRows);
    await _syncNotificationTable(deadlines, deadlineRows);
    await _syncNotificationTable(caseTimelineEvents, timelineRows);
    _changes.add('*');

    // حذف فایل‌ها بعد از ثبت موفق وضعیت جدید انجام می‌شود؛ شکست حذف فایل
    // نباید رکوردهای باقی‌مانده را به فایل ازبین‌رفته ارجاع دهد.
    for (final path in attachmentPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<AttachmentCleanupResult> cleanupOrphanAttachments() async {
    await _ensureLoaded();
    final documentRows = await _readTable(caseDocuments);
    final timelineRows = await _readTable(caseTimelineEvents);
    final financeRows = await _readTable(financeItems);
    final referenced = <String?>{
      ...documentRows.map((item) => item.filePath),
      ...timelineRows.map((item) => item.attachmentPath),
      ...financeRows.map((item) => item.attachmentPath),
    }
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .map((path) => p.normalize(File(path).absolute.path))
        .toSet();

    final docDir = await getApplicationDocumentsDirectory();
    final supportDir = await getApplicationSupportDirectory();
    final roots = <Directory>[
      Directory(p.join(docDir.path, 'case_attachments')),
      Directory(p.join(docDir.path, 'case_documents')),
      Directory(p.join(docDir.path, 'documents')),
      Directory(p.join(supportDir.path, 'case_attachments')),
      Directory(p.join(supportDir.path, 'case_documents')),
      Directory(p.join(supportDir.path, 'documents')),
    ];

    var scanned = 0;
    var deleted = 0;
    var kept = 0;
    var failed = 0;
    for (final root in roots) {
      if (!await root.exists()) continue;
      final files = await root.list(recursive: true, followLinks: false).where((entity) => entity is File).cast<File>().toList();
      for (final file in files) {
        scanned += 1;
        final normalized = p.normalize(file.absolute.path);
        if (referenced.contains(normalized)) {
          kept += 1;
          continue;
        }
        try {
          await file.delete();
          deleted += 1;
        } catch (_) {
          failed += 1;
        }
      }
      final directories = await root.list(recursive: true, followLinks: false).where((entity) => entity is Directory).cast<Directory>().toList();
      directories.sort((a, b) => b.path.length.compareTo(a.path.length));
      for (final directory in directories) {
        try {
          if (await directory.list().isEmpty) await directory.delete();
        } catch (_) {}
      }
    }
    return AttachmentCleanupResult(scanned: scanned, deleted: deleted, kept: kept, failed: failed);
  }

  Future<void> syncNotifications() async {
    await _ensureLoaded();
    NotificationService.resetSyncReport();
    for (final tableName in const ['tasks', 'deadlines', 'caseTimelineEvents']) {
      final raw = _store?[tableName];
      final rows = raw is List
          ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      try {
        await NotificationService.syncTable(tableName, rows);
      } catch (_) {}
    }
  }

  Future<List<T>> _readTable<T>(TableRef<T> table) async {
    await _ensureLoaded();
    final raw = _store![table.name];
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((item) => table.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  void _scheduleAutoBackup(String _) {
    // Auto backup is intentionally disabled for security. Legal case data,
    // app-lock state and documents must not be silently copied and later
    // restored after uninstall/reinstall. Manual backup remains available
    // only when the user explicitly taps the backup button.
    return;
  }

  Future<void> _syncNotificationTable<T>(TableRef<T> table, List<T> rows) async {
    if (table.name != 'tasks' && table.name != 'deadlines' && table.name != 'caseTimelineEvents') return;
    NotificationService.resetSyncReport();
    try {
      await NotificationService.syncTable(table.name, rows.map(table.toJson).toList());
    } catch (_) {
      // Saving legal data must never fail because Android notifications are unavailable.
    }
  }

  Future<void> _writeTable<T>(TableRef<T> table, List<T> rows) async {
    await _ensureLoaded();
    _store![table.name] = rows.map(table.toJson).toList();
    await _save();
    _changes.add(table.name);
    _scheduleAutoBackup(table.name);
    await _syncNotificationTable(table, rows);
  }

  Future<int> _nextId<T>(TableRef<T> table) async {
    await _ensureLoaded();
    final metaRaw = _store!['meta'];
    final meta = metaRaw is Map<String, dynamic> ? metaRaw : <String, dynamic>{};
    _store!['meta'] = meta;
    final key = '${table.name}_last_id';
    final next = ((meta[key] as num?)?.toInt() ?? 0) + 1;
    meta[key] = next;
    return next;
  }
}

class BackupSummary {
  const BackupSummary({
    required this.encrypted,
    required this.appVersion,
    required this.createdAt,
    required this.caseCount,
    required this.attachmentCount,
    required this.sizeBytes,
  });

  final bool encrypted;
  final String appVersion;
  final DateTime createdAt;
  final int caseCount;
  final int attachmentCount;
  final int sizeBytes;
}

class AttachmentCleanupResult {
  const AttachmentCleanupResult({
    required this.scanned,
    required this.deleted,
    required this.kept,
    required this.failed,
  });

  final int scanned;
  final int deleted;
  final int kept;
  final int failed;
}

class CasesTable extends TableRef<Case> {
  CasesTable()
      : super(
          name: 'cases',
          fromJson: Case.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => Case.fromCompanion(companion as CasesCompanion, id),
        );

  final id = ColumnRef<Case, int>((row) => row.id);
}

class TasksTable extends TableRef<Task> {
  TasksTable()
      : super(
          name: 'tasks',
          fromJson: Task.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => Task.fromCompanion(companion as TasksCompanion, id),
        );

  final id = ColumnRef<Task, int>((row) => row.id);
  final caseId = ColumnRef<Task, int?>((row) => row.caseId);
  final isDone = ColumnRef<Task, bool>((row) => row.isDone);
}

class LegalTextsTable extends TableRef<LegalText> {
  LegalTextsTable()
      : super(
          name: 'legalTexts',
          fromJson: LegalText.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => LegalText.fromCompanion(companion as LegalTextsCompanion, id),
        );

  final id = ColumnRef<LegalText, int>((row) => row.id);
}

class InboxItemsTable extends TableRef<InboxItem> {
  InboxItemsTable()
      : super(
          name: 'inboxItems',
          fromJson: InboxItem.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => InboxItem.fromCompanion(companion as InboxItemsCompanion, id),
        );

  final id = ColumnRef<InboxItem, int>((row) => row.id);
}

class CaseDocumentsTable extends TableRef<CaseDocument> {
  CaseDocumentsTable()
      : super(
          name: 'caseDocuments',
          fromJson: CaseDocument.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => CaseDocument.fromCompanion(companion as CaseDocumentsCompanion, id),
        );

  final id = ColumnRef<CaseDocument, int>((row) => row.id);
  final caseId = ColumnRef<CaseDocument, int>((row) => row.caseId);
}

class CaseTimelineEventsTable extends TableRef<CaseTimelineEvent> {
  CaseTimelineEventsTable()
      : super(
          name: 'caseTimelineEvents',
          fromJson: CaseTimelineEvent.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => CaseTimelineEvent.fromCompanion(companion as CaseTimelineEventsCompanion, id),
        );

  final id = ColumnRef<CaseTimelineEvent, int>((row) => row.id);
  final caseId = ColumnRef<CaseTimelineEvent, int>((row) => row.caseId);
}

class CasePeopleTable extends TableRef<CasePerson> {
  CasePeopleTable()
      : super(
          name: 'casePeople',
          fromJson: CasePerson.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => CasePerson.fromCompanion(companion as CasePeopleCompanion, id),
        );

  final id = ColumnRef<CasePerson, int>((row) => row.id);
  final caseId = ColumnRef<CasePerson, int>((row) => row.caseId);
}

class DeadlinesTable extends TableRef<Deadline> {
  DeadlinesTable()
      : super(
          name: 'deadlines',
          fromJson: Deadline.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => Deadline.fromCompanion(companion as DeadlinesCompanion, id),
        );

  final id = ColumnRef<Deadline, int>((row) => row.id);
  final caseId = ColumnRef<Deadline, int?>((row) => row.caseId);
  final isDone = ColumnRef<Deadline, bool>((row) => row.isDone);
}

class FinanceItemsTable extends TableRef<FinanceItem> {
  FinanceItemsTable()
      : super(
          name: 'financeItems',
          fromJson: FinanceItem.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => FinanceItem.fromCompanion(companion as FinanceItemsCompanion, id),
        );

  final id = ColumnRef<FinanceItem, int>((row) => row.id);
  final caseId = ColumnRef<FinanceItem, int?>((row) => row.caseId);
}

class GeneratedDraftsTable extends TableRef<GeneratedDraft> {
  GeneratedDraftsTable()
      : super(
          name: 'generatedDrafts',
          fromJson: GeneratedDraft.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => GeneratedDraft.fromCompanion(companion as GeneratedDraftsCompanion, id),
        );

  final id = ColumnRef<GeneratedDraft, int>((row) => row.id);
  final caseId = ColumnRef<GeneratedDraft, int?>((row) => row.caseId);
}

class ExperienceItemsTable extends TableRef<ExperienceItem> {
  ExperienceItemsTable()
      : super(
          name: 'experienceItems',
          fromJson: ExperienceItem.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => ExperienceItem.fromCompanion(companion as ExperienceItemsCompanion, id),
        );

  final id = ColumnRef<ExperienceItem, int>((row) => row.id);
  final caseId = ColumnRef<ExperienceItem, int?>((row) => row.caseId);
}

class ChecklistTemplatesTable extends TableRef<ChecklistTemplate> {
  ChecklistTemplatesTable()
      : super(
          name: 'checklistTemplates',
          fromJson: ChecklistTemplate.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => ChecklistTemplate.fromCompanion(companion as ChecklistTemplatesCompanion, id),
        );

  final id = ColumnRef<ChecklistTemplate, int>((row) => row.id);
}

class SecuritySettingsTable extends TableRef<SecuritySetting> {
  SecuritySettingsTable()
      : super(
          name: 'securitySettings',
          fromJson: SecuritySetting.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => SecuritySetting.fromCompanion(companion as SecuritySettingsCompanion, id),
        );

  final id = ColumnRef<SecuritySetting, int>((row) => row.id);
}

class UserProfilesTable extends TableRef<UserProfile> {
  UserProfilesTable()
      : super(
          name: 'userProfiles',
          fromJson: UserProfile.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => UserProfile.fromCompanion(companion as UserProfilesCompanion, id),
        );

  final id = ColumnRef<UserProfile, int>((row) => row.id);
}

class AiSettingsTable extends TableRef<AiSetting> {
  AiSettingsTable()
      : super(
          name: 'aiSettings',
          fromJson: AiSetting.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => AiSetting.fromCompanion(companion as AiSettingsCompanion, id),
        );

  final id = ColumnRef<AiSetting, int>((row) => row.id);
}

class CalendarSettingsTable extends TableRef<CalendarSetting> {
  CalendarSettingsTable()
      : super(
          name: 'calendarSettings',
          fromJson: CalendarSetting.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => CalendarSetting.fromCompanion(companion as CalendarSettingsCompanion, id),
        );

  final id = ColumnRef<CalendarSetting, int>((row) => row.id);
}

class PersonalNotesTable extends TableRef<PersonalNote> {
  PersonalNotesTable()
      : super(
          name: 'personalNotes',
          fromJson: PersonalNote.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => PersonalNote.fromCompanion(companion as PersonalNotesCompanion, id),
        );

  final id = ColumnRef<PersonalNote, int>((row) => row.id);
}


class PersonalAccountPersonsTable extends TableRef<PersonalAccountPerson> {
  PersonalAccountPersonsTable()
      : super(
          name: 'personalAccountPersons',
          fromJson: PersonalAccountPerson.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => PersonalAccountPerson.fromCompanion(companion as PersonalAccountPersonsCompanion, id),
        );

  final id = ColumnRef<PersonalAccountPerson, int>((row) => row.id);
  final personName = ColumnRef<PersonalAccountPerson, String>((row) => row.name);
}

class PersonalAccountTransactionsTable extends TableRef<PersonalAccountTransaction> {
  PersonalAccountTransactionsTable()
      : super(
          name: 'personalAccountTransactions',
          fromJson: PersonalAccountTransaction.fromJson,
          toJson: (item) => item.toJson(),
          fromCompanion: (companion, id) => PersonalAccountTransaction.fromCompanion(companion as PersonalAccountTransactionsCompanion, id),
        );

  final id = ColumnRef<PersonalAccountTransaction, int>((row) => row.id);
  final personName = ColumnRef<PersonalAccountTransaction, String>((row) => row.personName);
  final personId = ColumnRef<PersonalAccountTransaction, int?>((row) => row.personId);
}

class Case {
  const Case({
    required this.id,
    required this.title,
    this.clientName,
    this.opponentName,
    this.subject,
    this.caseType,
    this.archiveNumber,
    this.court,
    this.branch,
    this.judge,
    this.caseNumber,
    this.stage,
    this.clientRole,
    this.currentRole,
    required this.status,
    this.nextAction,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String? clientName;
  final String? opponentName;
  final String? subject;
  final String? caseType;
  final String? archiveNumber;
  final String? court;
  final String? branch;
  final String? judge;
  final String? caseNumber;
  final String? stage;
  final String? clientRole;
  final String? currentRole;
  final String status;
  final String? nextAction;
  final DateTime createdAt;

  factory Case.fromCompanion(CasesCompanion c, int id) => Case(
        id: id,
        title: c.title,
        clientName: _blankToNull(_nullableValueOr(c.clientName, null)),
        opponentName: _blankToNull(_nullableValueOr(c.opponentName, null)),
        subject: _blankToNull(_nullableValueOr(c.subject, null)),
        caseType: _blankToNull(_nullableValueOr(c.caseType, null)),
        archiveNumber: _blankToNull(_nullableValueOr(c.archiveNumber, null)),
        court: _blankToNull(_nullableValueOr(c.court, null)),
        branch: _blankToNull(_nullableValueOr(c.branch, null)),
        judge: _blankToNull(_nullableValueOr(c.judge, null)),
        caseNumber: _blankToNull(_nullableValueOr(c.caseNumber, null)),
        stage: _blankToNull(_nullableValueOr(c.stage, null)),
        clientRole: _blankToNull(_nullableValueOr(c.clientRole, null)),
        currentRole: _blankToNull(_nullableValueOr(c.currentRole, null)),
        status: _valueOr(c.status, 'فعال'),
        nextAction: _blankToNull(_nullableValueOr(c.nextAction, null)),
        createdAt: DateTime.now(),
      );

  factory Case.fromJson(Map<String, dynamic> json) => Case(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '').toString(),
        clientName: json['clientName']?.toString(),
        opponentName: json['opponentName']?.toString(),
        subject: json['subject']?.toString(),
        caseType: json['caseType']?.toString(),
        archiveNumber: json['archiveNumber']?.toString(),
        court: json['court']?.toString(),
        branch: json['branch']?.toString(),
        judge: json['judge']?.toString(),
        caseNumber: json['caseNumber']?.toString(),
        stage: json['stage']?.toString(),
        clientRole: json['clientRole']?.toString(),
        currentRole: json['currentRole']?.toString(),
        status: (json['status'] ?? 'فعال').toString(),
        nextAction: json['nextAction']?.toString(),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'clientName': clientName,
        'opponentName': opponentName,
        'subject': subject,
        'caseType': caseType,
        'archiveNumber': archiveNumber,
        'court': court,
        'branch': branch,
        'judge': judge,
        'caseNumber': caseNumber,
        'stage': stage,
        'clientRole': clientRole,
        'currentRole': currentRole,
        'status': status,
        'nextAction': nextAction,
        'createdAt': createdAt.toIso8601String(),
      };

  Case copyWith({
    String? title,
    Value<String?>? clientName,
    Value<String?>? opponentName,
    Value<String?>? subject,
    Value<String?>? caseType,
    Value<String?>? archiveNumber,
    Value<String?>? court,
    Value<String?>? branch,
    Value<String?>? judge,
    Value<String?>? caseNumber,
    Value<String?>? stage,
    Value<String?>? clientRole,
    Value<String?>? currentRole,
    String? status,
    Value<String?>? nextAction,
    DateTime? createdAt,
  }) =>
      Case(
        id: id,
        title: title ?? this.title,
        clientName: _blankToNull(_nullableValueOr(clientName, this.clientName)),
        opponentName: _blankToNull(_nullableValueOr(opponentName, this.opponentName)),
        subject: _blankToNull(_nullableValueOr(subject, this.subject)),
        caseType: _blankToNull(_nullableValueOr(caseType, this.caseType)),
        archiveNumber: _blankToNull(_nullableValueOr(archiveNumber, this.archiveNumber)),
        court: _blankToNull(_nullableValueOr(court, this.court)),
        branch: _blankToNull(_nullableValueOr(branch, this.branch)),
        judge: _blankToNull(_nullableValueOr(judge, this.judge)),
        caseNumber: _blankToNull(_nullableValueOr(caseNumber, this.caseNumber)),
        stage: _blankToNull(_nullableValueOr(stage, this.stage)),
        clientRole: _blankToNull(_nullableValueOr(clientRole, this.clientRole)),
        currentRole: _blankToNull(_nullableValueOr(currentRole, this.currentRole)),
        status: status ?? this.status,
        nextAction: _blankToNull(_nullableValueOr(nextAction, this.nextAction)),
        createdAt: createdAt ?? this.createdAt,
      );
}

class CasesCompanion {
  const CasesCompanion.insert({
    required this.title,
    this.clientName,
    this.opponentName,
    this.subject,
    this.caseType,
    this.archiveNumber,
    this.court,
    this.branch,
    this.judge,
    this.caseNumber,
    this.stage,
    this.clientRole,
    this.currentRole,
    this.status,
    this.nextAction,
  });

  final String title;
  final Value<String?>? clientName;
  final Value<String?>? opponentName;
  final Value<String?>? subject;
  final Value<String?>? caseType;
  final Value<String?>? archiveNumber;
  final Value<String?>? court;
  final Value<String?>? branch;
  final Value<String?>? judge;
  final Value<String?>? caseNumber;
  final Value<String?>? stage;
  final Value<String?>? clientRole;
  final Value<String?>? currentRole;
  final Value<String>? status;
  final Value<String?>? nextAction;
}

class Task {
  const Task({
    required this.id,
    this.caseId,
    required this.title,
    required this.priority,
    this.dueDate,
    required this.isDone,
    required this.createdAt,
  });

  final int id;
  final int? caseId;
  final String title;
  final String priority;
  final DateTime? dueDate;
  final bool isDone;
  final DateTime createdAt;

  factory Task.fromCompanion(TasksCompanion c, int id) => Task(
        id: id,
        caseId: _nullableValueOr(c.caseId, null),
        title: c.title,
        priority: _valueOr(c.priority, 'متوسط'),
        dueDate: _nullableValueOr(c.dueDate, null),
        isDone: _valueOr(c.isDone, false),
        createdAt: DateTime.now(),
      );

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt(),
        title: (json['title'] ?? '').toString(),
        priority: (json['priority'] ?? 'متوسط').toString(),
        dueDate: _dateOrNull(json['dueDate']),
        isDone: json['isDone'] == true,
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'title': title,
        'priority': priority,
        'dueDate': dueDate?.toIso8601String(),
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
      };

  Task copyWith({
    int? caseId,
    String? title,
    String? priority,
    Value<DateTime?>? dueDate,
    bool? isDone,
    DateTime? createdAt,
  }) =>
      Task(
        id: id,
        caseId: caseId ?? this.caseId,
        title: title ?? this.title,
        priority: priority ?? this.priority,
        dueDate: _nullableValueOr(dueDate, this.dueDate),
        isDone: isDone ?? this.isDone,
        createdAt: createdAt ?? this.createdAt,
      );
}

class TasksCompanion {
  const TasksCompanion.insert({
    required this.title,
    this.caseId,
    this.priority,
    this.dueDate,
    this.isDone,
  });

  final String title;
  final Value<int?>? caseId;
  final Value<String>? priority;
  final Value<DateTime?>? dueDate;
  final Value<bool>? isDone;
}

class LegalText {
  const LegalText({
    required this.id,
    this.code,
    required this.title,
    required this.type,
    this.subject,
    required this.body,
    this.tags,
    this.qualityScore,
    this.usageNote,
    this.successReason,
    required this.versionNumber,
    required this.createdAt,
  });

  final int id;
  final String? code;
  final String title;
  final String type;
  final String? subject;
  final String body;
  final String? tags;
  final int? qualityScore;
  final String? usageNote;
  final String? successReason;
  final int versionNumber;
  final DateTime createdAt;

  factory LegalText.fromCompanion(LegalTextsCompanion c, int id) => LegalText(
        id: id,
        code: _blankToNull(_nullableValueOr(c.code, null)),
        title: c.title,
        type: c.type,
        subject: _blankToNull(_nullableValueOr(c.subject, null)),
        body: c.body,
        tags: _blankToNull(_nullableValueOr(c.tags, null)),
        qualityScore: _nullableValueOr(c.qualityScore, null),
        usageNote: _blankToNull(_nullableValueOr(c.usageNote, null)),
        successReason: _blankToNull(_nullableValueOr(c.successReason, null)),
        versionNumber: _valueOr(c.versionNumber, 1),
        createdAt: DateTime.now(),
      );

  factory LegalText.fromJson(Map<String, dynamic> json) => LegalText(
        id: (json['id'] as num?)?.toInt() ?? 0,
        code: json['code']?.toString(),
        title: (json['title'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        subject: json['subject']?.toString(),
        body: (json['body'] ?? '').toString(),
        tags: json['tags']?.toString(),
        qualityScore: (json['qualityScore'] as num?)?.toInt(),
        usageNote: json['usageNote']?.toString(),
        successReason: json['successReason']?.toString(),
        versionNumber: (json['versionNumber'] as num?)?.toInt() ?? 1,
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'title': title,
        'type': type,
        'subject': subject,
        'body': body,
        'tags': tags,
        'qualityScore': qualityScore,
        'usageNote': usageNote,
        'successReason': successReason,
        'versionNumber': versionNumber,
        'createdAt': createdAt.toIso8601String(),
      };
}

class LegalTextsCompanion {
  const LegalTextsCompanion.insert({
    this.code,
    required this.title,
    required this.type,
    this.subject,
    required this.body,
    this.tags,
    this.qualityScore,
    this.usageNote,
    this.successReason,
    this.versionNumber,
  });

  final Value<String?>? code;
  final String title;
  final String type;
  final Value<String?>? subject;
  final String body;
  final Value<String?>? tags;
  final Value<int?>? qualityScore;
  final Value<String?>? usageNote;
  final Value<String?>? successReason;
  final Value<int>? versionNumber;
}

class InboxItem {
  const InboxItem({
    required this.id,
    required this.rawText,
    this.detectedType,
    required this.isProcessed,
    required this.createdAt,
  });

  final int id;
  final String rawText;
  final String? detectedType;
  final bool isProcessed;
  final DateTime createdAt;

  factory InboxItem.fromCompanion(InboxItemsCompanion c, int id) => InboxItem(
        id: id,
        rawText: c.rawText,
        detectedType: _blankToNull(_nullableValueOr(c.detectedType, null)),
        isProcessed: _valueOr(c.isProcessed, false),
        createdAt: DateTime.now(),
      );

  factory InboxItem.fromJson(Map<String, dynamic> json) => InboxItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        rawText: (json['rawText'] ?? '').toString(),
        detectedType: json['detectedType']?.toString(),
        isProcessed: json['isProcessed'] == true,
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawText': rawText,
        'detectedType': detectedType,
        'isProcessed': isProcessed,
        'createdAt': createdAt.toIso8601String(),
      };
}

class InboxItemsCompanion {
  const InboxItemsCompanion.insert({required this.rawText, this.detectedType, this.isProcessed});

  final String rawText;
  final Value<String?>? detectedType;
  final Value<bool>? isProcessed;
}

class CaseDocument {
  const CaseDocument({
    required this.id,
    required this.caseId,
    required this.title,
    this.documentType,
    this.filePath,
    this.notes,
    this.extractedText,
    this.aiSummary,
    required this.createdAt,
  });

  final int id;
  final int caseId;
  final String title;
  final String? documentType;
  final String? filePath;
  final String? notes;
  final String? extractedText;
  final String? aiSummary;
  final DateTime createdAt;

  factory CaseDocument.fromCompanion(CaseDocumentsCompanion c, int id) => CaseDocument(
        id: id,
        caseId: c.caseId,
        title: c.title,
        documentType: _blankToNull(_nullableValueOr(c.documentType, null)),
        filePath: _blankToNull(_nullableValueOr(c.filePath, null)),
        notes: _blankToNull(_nullableValueOr(c.notes, null)),
        extractedText: _blankToNull(_nullableValueOr(c.extractedText, null)),
        aiSummary: _blankToNull(_nullableValueOr(c.aiSummary, null)),
        createdAt: DateTime.now(),
      );

  factory CaseDocument.fromJson(Map<String, dynamic> json) => CaseDocument(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '').toString(),
        documentType: json['documentType']?.toString(),
        filePath: json['filePath']?.toString(),
        notes: json['notes']?.toString(),
        extractedText: json['extractedText']?.toString(),
        aiSummary: json['aiSummary']?.toString(),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'title': title,
        'documentType': documentType,
        'filePath': filePath,
        'notes': notes,
        'extractedText': extractedText,
        'aiSummary': aiSummary,
        'createdAt': createdAt.toIso8601String(),
      };

  CaseDocument copyWith({
    String? title,
    Value<String?>? documentType,
    Value<String?>? filePath,
    Value<String?>? notes,
    Value<String?>? extractedText,
    Value<String?>? aiSummary,
    DateTime? createdAt,
  }) =>
      CaseDocument(
        id: id,
        caseId: caseId,
        title: title ?? this.title,
        documentType: _blankToNull(_nullableValueOr(documentType, this.documentType)),
        filePath: _blankToNull(_nullableValueOr(filePath, this.filePath)),
        notes: _blankToNull(_nullableValueOr(notes, this.notes)),
        extractedText: _blankToNull(_nullableValueOr(extractedText, this.extractedText)),
        aiSummary: _blankToNull(_nullableValueOr(aiSummary, this.aiSummary)),
        createdAt: createdAt ?? this.createdAt,
      );
}

class CaseDocumentsCompanion {
  const CaseDocumentsCompanion.insert({
    required this.caseId,
    required this.title,
    this.documentType,
    this.filePath,
    this.notes,
    this.extractedText,
    this.aiSummary,
  });

  final int caseId;
  final String title;
  final Value<String?>? documentType;
  final Value<String?>? filePath;
  final Value<String?>? notes;
  final Value<String?>? extractedText;
  final Value<String?>? aiSummary;
}

class CasePerson {
  const CasePerson({
    required this.id,
    required this.caseId,
    required this.name,
    required this.role,
    this.phone,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final int caseId;
  final String name;
  final String role;
  final String? phone;
  final String? notes;
  final DateTime createdAt;

  factory CasePerson.fromCompanion(CasePeopleCompanion c, int id) => CasePerson(
        id: id,
        caseId: c.caseId,
        name: c.name,
        role: _valueOr(c.role, 'سایر'),
        phone: _blankToNull(_nullableValueOr(c.phone, null)),
        notes: _blankToNull(_nullableValueOr(c.notes, null)),
        createdAt: _valueOr(c.createdAt, DateTime.now()),
      );

  factory CasePerson.fromJson(Map<String, dynamic> json) => CasePerson(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '').toString(),
        role: (json['role'] ?? 'سایر').toString(),
        phone: json['phone']?.toString(),
        notes: json['notes']?.toString(),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'name': name,
        'role': role,
        'phone': phone,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };
}

class CasePeopleCompanion {
  const CasePeopleCompanion.insert({
    required this.caseId,
    required this.name,
    this.role,
    this.phone,
    this.notes,
    this.createdAt,
  });

  final int caseId;
  final String name;
  final Value<String>? role;
  final Value<String?>? phone;
  final Value<String?>? notes;
  final Value<DateTime>? createdAt;
}

class CaseTimelineEvent {
  const CaseTimelineEvent({
    required this.id,
    required this.caseId,
    required this.title,
    this.eventType,
    this.description,
    required this.eventDate,
    required this.isDone,
    this.sourceType,
    this.sourceId,
    this.decisionSummary,
    this.actorRole,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
    required this.includeInNarrative,
    required this.createdAt,
  });

  final int id;
  final int caseId;
  final String title;
  final String? eventType;
  final String? description;
  final DateTime eventDate;
  final bool isDone;
  final String? sourceType;
  final int? sourceId;
  final String? decisionSummary;
  final String? actorRole;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentType;
  final bool includeInNarrative;
  final DateTime createdAt;

  factory CaseTimelineEvent.fromCompanion(CaseTimelineEventsCompanion c, int id) => CaseTimelineEvent(
        id: id,
        caseId: c.caseId,
        title: c.title,
        eventType: _blankToNull(_nullableValueOr(c.eventType, null)),
        description: _blankToNull(_nullableValueOr(c.description, null)),
        eventDate: _valueOr(c.eventDate, DateTime.now()),
        isDone: _valueOr(c.isDone, false),
        sourceType: _blankToNull(_nullableValueOr(c.sourceType, null)),
        sourceId: _nullableValueOr(c.sourceId, null),
        decisionSummary: _blankToNull(_nullableValueOr(c.decisionSummary, null)),
        actorRole: _blankToNull(_nullableValueOr(c.actorRole, null)),
        attachmentPath: _blankToNull(_nullableValueOr(c.attachmentPath, null)),
        attachmentName: _blankToNull(_nullableValueOr(c.attachmentName, null)),
        attachmentType: _blankToNull(_nullableValueOr(c.attachmentType, null)),
        includeInNarrative: _valueOr(c.includeInNarrative, true),
        createdAt: DateTime.now(),
      );

  factory CaseTimelineEvent.fromJson(Map<String, dynamic> json) => CaseTimelineEvent(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '').toString(),
        eventType: json['eventType']?.toString(),
        description: json['description']?.toString(),
        eventDate: _dateOrNow(json['eventDate']),
        isDone: json['isDone'] == true,
        sourceType: json['sourceType']?.toString(),
        sourceId: (json['sourceId'] as num?)?.toInt(),
        decisionSummary: json['decisionSummary']?.toString(),
        actorRole: json['actorRole']?.toString(),
        attachmentPath: json['attachmentPath']?.toString(),
        attachmentName: json['attachmentName']?.toString(),
        attachmentType: json['attachmentType']?.toString(),
        includeInNarrative: json['includeInNarrative'] != false,
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'title': title,
        'eventType': eventType,
        'description': description,
        'eventDate': eventDate.toIso8601String(),
        'isDone': isDone,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'decisionSummary': decisionSummary,
        'actorRole': actorRole,
        'attachmentPath': attachmentPath,
        'attachmentName': attachmentName,
        'attachmentType': attachmentType,
        'includeInNarrative': includeInNarrative,
        'createdAt': createdAt.toIso8601String(),
      };

  CaseTimelineEvent copyWith({
    int? caseId,
    String? title,
    Value<String?>? eventType,
    Value<String?>? description,
    DateTime? eventDate,
    bool? isDone,
    Value<String?>? sourceType,
    Value<int?>? sourceId,
    Value<String?>? decisionSummary,
    Value<String?>? actorRole,
    Value<String?>? attachmentPath,
    Value<String?>? attachmentName,
    Value<String?>? attachmentType,
    bool? includeInNarrative,
    DateTime? createdAt,
  }) =>
      CaseTimelineEvent(
        id: id,
        caseId: caseId ?? this.caseId,
        title: title ?? this.title,
        eventType: _blankToNull(_nullableValueOr(eventType, this.eventType)),
        description: _blankToNull(_nullableValueOr(description, this.description)),
        eventDate: eventDate ?? this.eventDate,
        isDone: isDone ?? this.isDone,
        sourceType: _blankToNull(_nullableValueOr(sourceType, this.sourceType)),
        sourceId: _nullableValueOr(sourceId, this.sourceId),
        decisionSummary: _blankToNull(_nullableValueOr(decisionSummary, this.decisionSummary)),
        actorRole: _blankToNull(_nullableValueOr(actorRole, this.actorRole)),
        attachmentPath: _blankToNull(_nullableValueOr(attachmentPath, this.attachmentPath)),
        attachmentName: _blankToNull(_nullableValueOr(attachmentName, this.attachmentName)),
        attachmentType: _blankToNull(_nullableValueOr(attachmentType, this.attachmentType)),
        includeInNarrative: includeInNarrative ?? this.includeInNarrative,
        createdAt: createdAt ?? this.createdAt,
      );
}

class CaseTimelineEventsCompanion {
  const CaseTimelineEventsCompanion.insert({
    required this.caseId,
    required this.title,
    this.eventType,
    this.description,
    this.eventDate,
    this.isDone,
    this.sourceType,
    this.sourceId,
    this.decisionSummary,
    this.actorRole,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
    this.includeInNarrative,
  });

  final int caseId;
  final String title;
  final Value<String?>? eventType;
  final Value<String?>? description;
  final Value<DateTime>? eventDate;
  final Value<bool>? isDone;
  final Value<String?>? sourceType;
  final Value<int?>? sourceId;
  final Value<String?>? decisionSummary;
  final Value<String?>? actorRole;
  final Value<String?>? attachmentPath;
  final Value<String?>? attachmentName;
  final Value<String?>? attachmentType;
  final Value<bool>? includeInNarrative;
}

class Deadline {
  const Deadline({
    required this.id,
    this.caseId,
    required this.title,
    this.deadlineType,
    required this.dueDate,
    required this.priority,
    this.reminderMinutesBefore = 0,
    required this.isDone,
    this.notes,
    this.extractedText,
    this.aiSummary,
    required this.createdAt,
  });

  final int id;
  final int? caseId;
  final String title;
  final String? deadlineType;
  final DateTime dueDate;
  final String priority;
  final int reminderMinutesBefore;
  final bool isDone;
  final String? notes;
  final String? extractedText;
  final String? aiSummary;
  final DateTime createdAt;

  factory Deadline.fromCompanion(DeadlinesCompanion c, int id) => Deadline(
        id: id,
        caseId: _nullableValueOr(c.caseId, null),
        title: c.title,
        deadlineType: _blankToNull(_nullableValueOr(c.deadlineType, null)),
        dueDate: c.dueDate,
        priority: _valueOr(c.priority, 'خیلی زیاد'),
        reminderMinutesBefore: _valueOr(c.reminderMinutesBefore, 0),
        isDone: _valueOr(c.isDone, false),
        notes: _blankToNull(_nullableValueOr(c.notes, null)),
        extractedText: _blankToNull(_nullableValueOr(c.extractedText, null)),
        aiSummary: _blankToNull(_nullableValueOr(c.aiSummary, null)),
        createdAt: DateTime.now(),
      );

  factory Deadline.fromJson(Map<String, dynamic> json) => Deadline(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt(),
        title: (json['title'] ?? '').toString(),
        deadlineType: json['deadlineType']?.toString(),
        dueDate: _dateOrNow(json['dueDate']),
        priority: (json['priority'] ?? 'خیلی زیاد').toString(),
        reminderMinutesBefore: (json['reminderMinutesBefore'] as num?)?.toInt() ?? 0,
        isDone: json['isDone'] == true,
        notes: json['notes']?.toString(),
        extractedText: json['extractedText']?.toString(),
        aiSummary: json['aiSummary']?.toString(),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'title': title,
        'deadlineType': deadlineType,
        'dueDate': dueDate.toIso8601String(),
        'priority': priority,
        'reminderMinutesBefore': reminderMinutesBefore,
        'isDone': isDone,
        'notes': notes,
        'extractedText': extractedText,
        'aiSummary': aiSummary,
        'createdAt': createdAt.toIso8601String(),
      };

  Deadline copyWith({
    int? caseId,
    String? title,
    Value<String?>? deadlineType,
    DateTime? dueDate,
    String? priority,
    int? reminderMinutesBefore,
    bool? isDone,
    Value<String?>? notes,
    Value<String?>? extractedText,
    Value<String?>? aiSummary,
    DateTime? createdAt,
  }) =>
      Deadline(
        id: id,
        caseId: caseId ?? this.caseId,
        title: title ?? this.title,
        deadlineType: _blankToNull(_nullableValueOr(deadlineType, this.deadlineType)),
        dueDate: dueDate ?? this.dueDate,
        priority: priority ?? this.priority,
        reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
        isDone: isDone ?? this.isDone,
        notes: _blankToNull(_nullableValueOr(notes, this.notes)),
        extractedText: _blankToNull(_nullableValueOr(extractedText, this.extractedText)),
        aiSummary: _blankToNull(_nullableValueOr(aiSummary, this.aiSummary)),
        createdAt: createdAt ?? this.createdAt,
      );
}

class DeadlinesCompanion {
  const DeadlinesCompanion.insert({
    this.caseId,
    required this.title,
    this.deadlineType,
    required this.dueDate,
    this.priority,
    this.reminderMinutesBefore,
    this.isDone,
    this.notes,
    this.extractedText,
    this.aiSummary,
  });

  final Value<int?>? caseId;
  final String title;
  final Value<String?>? deadlineType;
  final DateTime dueDate;
  final Value<String>? priority;
  final Value<int>? reminderMinutesBefore;
  final Value<bool>? isDone;
  final Value<String?>? notes;
  final Value<String?>? extractedText;
  final Value<String?>? aiSummary;
}

class FinanceItem {
  const FinanceItem({
    required this.id,
    this.caseId,
    required this.type,
    required this.title,
    required this.amount,
    this.category,
    required this.date,
    this.notes,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
    this.isLawyerCost = false,
  });

  final int id;
  final int? caseId;
  final String type;
  final String title;
  final double amount;
  final String? category;
  final DateTime date;
  final String? notes;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentType;
  final bool isLawyerCost;

  factory FinanceItem.fromCompanion(FinanceItemsCompanion c, int id) => FinanceItem(
        id: id,
        caseId: _nullableValueOr(c.caseId, null),
        type: c.type,
        title: c.title,
        amount: c.amount,
        category: _blankToNull(_nullableValueOr(c.category, null)),
        date: _valueOr(c.date, DateTime.now()),
        notes: _blankToNull(_nullableValueOr(c.notes, null)),
        attachmentPath: _blankToNull(_nullableValueOr(c.attachmentPath, null)),
        attachmentName: _blankToNull(_nullableValueOr(c.attachmentName, null)),
        attachmentType: _blankToNull(_nullableValueOr(c.attachmentType, null)),
        isLawyerCost: _valueOr(c.isLawyerCost, false),
      );

  factory FinanceItem.fromJson(Map<String, dynamic> json) => FinanceItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt(),
        type: (json['type'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        category: json['category']?.toString(),
        date: _dateOrNow(json['date']),
        notes: json['notes']?.toString(),
        attachmentPath: json['attachmentPath']?.toString(),
        attachmentName: json['attachmentName']?.toString(),
        attachmentType: json['attachmentType']?.toString(),
        isLawyerCost: json['isLawyerCost'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'type': type,
        'title': title,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'notes': notes,
        'attachmentPath': attachmentPath,
        'attachmentName': attachmentName,
        'attachmentType': attachmentType,
        'isLawyerCost': isLawyerCost,
      };
}

class FinanceItemsCompanion {
  const FinanceItemsCompanion.insert({
    this.caseId,
    required this.type,
    required this.title,
    required this.amount,
    this.category,
    this.date,
    this.notes,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
    this.isLawyerCost,
  });

  final Value<int?>? caseId;
  final String type;
  final String title;
  final double amount;
  final Value<String?>? category;
  final Value<DateTime>? date;
  final Value<String?>? notes;
  final Value<String?>? attachmentPath;
  final Value<String?>? attachmentName;
  final Value<String?>? attachmentType;
  final Value<bool>? isLawyerCost;
}

class GeneratedDraft {
  const GeneratedDraft({
    required this.id,
    this.caseId,
    required this.title,
    required this.draftType,
    required this.body,
    this.prompt,
    required this.savedToLegalTexts,
    required this.createdAt,
  });

  final int id;
  final int? caseId;
  final String title;
  final String draftType;
  final String body;
  final String? prompt;
  final bool savedToLegalTexts;
  final DateTime createdAt;

  factory GeneratedDraft.fromCompanion(GeneratedDraftsCompanion c, int id) => GeneratedDraft(
        id: id,
        caseId: _nullableValueOr(c.caseId, null),
        title: c.title,
        draftType: c.draftType,
        body: c.body,
        prompt: _blankToNull(_nullableValueOr(c.prompt, null)),
        savedToLegalTexts: _valueOr(c.savedToLegalTexts, false),
        createdAt: DateTime.now(),
      );

  factory GeneratedDraft.fromJson(Map<String, dynamic> json) => GeneratedDraft(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt(),
        title: (json['title'] ?? '').toString(),
        draftType: (json['draftType'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        prompt: json['prompt']?.toString(),
        savedToLegalTexts: json['savedToLegalTexts'] == true,
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'title': title,
        'draftType': draftType,
        'body': body,
        'prompt': prompt,
        'savedToLegalTexts': savedToLegalTexts,
        'createdAt': createdAt.toIso8601String(),
      };
}

class GeneratedDraftsCompanion {
  const GeneratedDraftsCompanion.insert({
    this.caseId,
    required this.title,
    required this.draftType,
    required this.body,
    this.prompt,
    this.savedToLegalTexts,
  });

  final Value<int?>? caseId;
  final String title;
  final String draftType;
  final String body;
  final Value<String?>? prompt;
  final Value<bool>? savedToLegalTexts;
}

class ExperienceItem {
  const ExperienceItem({
    required this.id,
    this.caseId,
    required this.title,
    this.result,
    this.effectiveStrategy,
    this.mistakes,
    this.judgeNotes,
    this.futureTip,
    this.rating,
    required this.createdAt,
  });

  final int id;
  final int? caseId;
  final String title;
  final String? result;
  final String? effectiveStrategy;
  final String? mistakes;
  final String? judgeNotes;
  final String? futureTip;
  final int? rating;
  final DateTime createdAt;

  factory ExperienceItem.fromCompanion(ExperienceItemsCompanion c, int id) => ExperienceItem(
        id: id,
        caseId: _nullableValueOr(c.caseId, null),
        title: c.title,
        result: _blankToNull(_nullableValueOr(c.result, null)),
        effectiveStrategy: _blankToNull(_nullableValueOr(c.effectiveStrategy, null)),
        mistakes: _blankToNull(_nullableValueOr(c.mistakes, null)),
        judgeNotes: _blankToNull(_nullableValueOr(c.judgeNotes, null)),
        futureTip: _blankToNull(_nullableValueOr(c.futureTip, null)),
        rating: _nullableValueOr(c.rating, null),
        createdAt: DateTime.now(),
      );

  factory ExperienceItem.fromJson(Map<String, dynamic> json) => ExperienceItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt(),
        title: (json['title'] ?? '').toString(),
        result: json['result']?.toString(),
        effectiveStrategy: json['effectiveStrategy']?.toString(),
        mistakes: json['mistakes']?.toString(),
        judgeNotes: json['judgeNotes']?.toString(),
        futureTip: json['futureTip']?.toString(),
        rating: (json['rating'] as num?)?.toInt(),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'title': title,
        'result': result,
        'effectiveStrategy': effectiveStrategy,
        'mistakes': mistakes,
        'judgeNotes': judgeNotes,
        'futureTip': futureTip,
        'rating': rating,
        'createdAt': createdAt.toIso8601String(),
      };
}

class ExperienceItemsCompanion {
  const ExperienceItemsCompanion.insert({
    this.caseId,
    required this.title,
    this.result,
    this.effectiveStrategy,
    this.mistakes,
    this.judgeNotes,
    this.futureTip,
    this.rating,
  });

  final Value<int?>? caseId;
  final String title;
  final Value<String?>? result;
  final Value<String?>? effectiveStrategy;
  final Value<String?>? mistakes;
  final Value<String?>? judgeNotes;
  final Value<String?>? futureTip;
  final Value<int?>? rating;
}

class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.title,
    this.caseType,
    required this.items,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String? caseType;
  final String items;
  final DateTime createdAt;

  factory ChecklistTemplate.fromCompanion(ChecklistTemplatesCompanion c, int id) => ChecklistTemplate(
        id: id,
        title: c.title,
        caseType: _blankToNull(_nullableValueOr(c.caseType, null)),
        items: c.items,
        createdAt: DateTime.now(),
      );

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) => ChecklistTemplate(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '').toString(),
        caseType: json['caseType']?.toString(),
        items: (json['items'] ?? '').toString(),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'caseType': caseType,
        'items': items,
        'createdAt': createdAt.toIso8601String(),
      };
}

class ChecklistTemplatesCompanion {
  const ChecklistTemplatesCompanion.insert({required this.title, this.caseType, required this.items});

  final String title;
  final Value<String?>? caseType;
  final String items;
}


class PersonalNote {
  const PersonalNote({
    required this.id,
    required this.title,
    required this.body,
    this.category,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String body;
  final String? category;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PersonalNote.fromCompanion(PersonalNotesCompanion c, int id) {
    final now = DateTime.now();
    return PersonalNote(
      id: id,
      title: c.title,
      body: c.body,
      category: _blankToNull(_nullableValueOr(c.category, null)),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory PersonalNote.fromJson(Map<String, dynamic> json) => PersonalNote(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        category: _blankToNull(json['category']?.toString()),
        createdAt: _dateOrNow(json['createdAt']),
        updatedAt: _dateOrNow(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  PersonalNote copyWith({
    String? title,
    String? body,
    Value<String?>? category,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PersonalNote(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        category: _blankToNull(_nullableValueOr(category, this.category)),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class PersonalNotesCompanion {
  const PersonalNotesCompanion.insert({
    required this.title,
    required this.body,
    this.category,
  });

  final String title;
  final String body;
  final Value<String?>? category;
}


class PersonalAccountPerson {
  const PersonalAccountPerson({
    required this.id,
    required this.name,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PersonalAccountPerson.fromCompanion(PersonalAccountPersonsCompanion c, int id) {
    final now = DateTime.now();
    return PersonalAccountPerson(
      id: id,
      name: c.name.trim(),
      notes: _blankToNull(_nullableValueOr(c.notes, null)),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory PersonalAccountPerson.fromJson(Map<String, dynamic> json) => PersonalAccountPerson(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '').toString().trim(),
        notes: _blankToNull(json['notes']?.toString()),
        createdAt: _dateOrNow(json['createdAt']),
        updatedAt: _dateOrNow(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  PersonalAccountPerson copyWith({
    String? name,
    Value<String?>? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PersonalAccountPerson(
        id: id,
        name: name ?? this.name,
        notes: _blankToNull(_nullableValueOr(notes, this.notes)),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class PersonalAccountPersonsCompanion {
  const PersonalAccountPersonsCompanion.insert({
    required this.name,
    this.notes,
  });

  final String name;
  final Value<String?>? notes;
}

class PersonalAccountTransaction {
  const PersonalAccountTransaction({
    required this.id,
    this.personId,
    required this.personName,
    required this.type,
    required this.amount,
    required this.date,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final int? personId;
  final String personName;
  final String type;
  final double amount;
  final DateTime date;
  final String? notes;
  final DateTime createdAt;

  factory PersonalAccountTransaction.fromCompanion(PersonalAccountTransactionsCompanion c, int id) => PersonalAccountTransaction(
        id: id,
        personId: _nullableValueOr(c.personId, null),
        personName: c.personName.trim(),
        type: c.type,
        amount: c.amount,
        date: _valueOr(c.date, DateTime.now()),
        notes: _blankToNull(_nullableValueOr(c.notes, null)),
        createdAt: DateTime.now(),
      );

  factory PersonalAccountTransaction.fromJson(Map<String, dynamic> json) => PersonalAccountTransaction(
        id: (json['id'] as num?)?.toInt() ?? 0,
        personId: (json['personId'] as num?)?.toInt(),
        personName: (json['personName'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        date: _dateOrNow(json['date']),
        notes: _blankToNull(json['notes']?.toString()),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'personId': personId,
        'personName': personName,
        'type': type,
        'amount': amount,
        'date': date.toIso8601String(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  PersonalAccountTransaction copyWith({
    Value<int?>? personId,
    String? personName,
    String? type,
    double? amount,
    DateTime? date,
    Value<String?>? notes,
    DateTime? createdAt,
  }) =>
      PersonalAccountTransaction(
        id: id,
        personId: _nullableValueOr(personId, this.personId),
        personName: personName ?? this.personName,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        notes: _blankToNull(_nullableValueOr(notes, this.notes)),
        createdAt: createdAt ?? this.createdAt,
      );
}

class PersonalAccountTransactionsCompanion {
  const PersonalAccountTransactionsCompanion.insert({
    this.personId,
    required this.personName,
    required this.type,
    required this.amount,
    this.date,
    this.notes,
  });

  final Value<int?>? personId;
  final String personName;
  final String type;
  final double amount;
  final Value<DateTime>? date;
  final Value<String?>? notes;
}

class UserProfile {
  const UserProfile({
    required this.id,
    this.displayName,
    this.legalTitle,
    this.licenseNumber,
    this.barAssociation,
    required this.useNameInLegalTexts,
    required this.useLicenseInLegalTexts,
    required this.useBarInLegalTexts,
    required this.updatedAt,
  });

  final int id;
  final String? displayName;
  final String? legalTitle;
  final String? licenseNumber;
  final String? barAssociation;
  final bool useNameInLegalTexts;
  final bool useLicenseInLegalTexts;
  final bool useBarInLegalTexts;
  final DateTime updatedAt;

  factory UserProfile.fromCompanion(UserProfilesCompanion c, int id) => UserProfile(
        id: id,
        displayName: _blankToNull(_nullableValueOr(c.displayName, null)),
        legalTitle: _blankToNull(_nullableValueOr(c.legalTitle, null)),
        licenseNumber: _blankToNull(_nullableValueOr(c.licenseNumber, null)),
        barAssociation: _blankToNull(_nullableValueOr(c.barAssociation, null)),
        useNameInLegalTexts: _valueOr(c.useNameInLegalTexts, false),
        useLicenseInLegalTexts: _valueOr(c.useLicenseInLegalTexts, false),
        useBarInLegalTexts: _valueOr(c.useBarInLegalTexts, false),
        updatedAt: DateTime.now(),
      );

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        displayName: _blankToNull(json['displayName']?.toString()),
        legalTitle: _blankToNull(json['legalTitle']?.toString()),
        licenseNumber: _blankToNull(json['licenseNumber']?.toString()),
        barAssociation: _blankToNull(json['barAssociation']?.toString()),
        useNameInLegalTexts: json['useNameInLegalTexts'] == true,
        useLicenseInLegalTexts: json['useLicenseInLegalTexts'] == true,
        useBarInLegalTexts: json['useBarInLegalTexts'] == true,
        updatedAt: _dateOrNow(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'legalTitle': legalTitle,
        'licenseNumber': licenseNumber,
        'barAssociation': barAssociation,
        'useNameInLegalTexts': useNameInLegalTexts,
        'useLicenseInLegalTexts': useLicenseInLegalTexts,
        'useBarInLegalTexts': useBarInLegalTexts,
        'updatedAt': updatedAt.toIso8601String(),
      };

  UserProfile copyWith({
    Value<String?>? displayName,
    Value<String?>? legalTitle,
    Value<String?>? licenseNumber,
    Value<String?>? barAssociation,
    bool? useNameInLegalTexts,
    bool? useLicenseInLegalTexts,
    bool? useBarInLegalTexts,
    DateTime? updatedAt,
  }) =>
      UserProfile(
        id: id,
        displayName: _blankToNull(_nullableValueOr(displayName, this.displayName)),
        legalTitle: _blankToNull(_nullableValueOr(legalTitle, this.legalTitle)),
        licenseNumber: _blankToNull(_nullableValueOr(licenseNumber, this.licenseNumber)),
        barAssociation: _blankToNull(_nullableValueOr(barAssociation, this.barAssociation)),
        useNameInLegalTexts: useNameInLegalTexts ?? this.useNameInLegalTexts,
        useLicenseInLegalTexts: useLicenseInLegalTexts ?? this.useLicenseInLegalTexts,
        useBarInLegalTexts: useBarInLegalTexts ?? this.useBarInLegalTexts,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class UserProfilesCompanion {
  const UserProfilesCompanion.insert({
    this.displayName,
    this.legalTitle,
    this.licenseNumber,
    this.barAssociation,
    this.useNameInLegalTexts,
    this.useLicenseInLegalTexts,
    this.useBarInLegalTexts,
  });

  final Value<String?>? displayName;
  final Value<String?>? legalTitle;
  final Value<String?>? licenseNumber;
  final Value<String?>? barAssociation;
  final Value<bool>? useNameInLegalTexts;
  final Value<bool>? useLicenseInLegalTexts;
  final Value<bool>? useBarInLegalTexts;
}

class SecuritySetting {
  const SecuritySetting({
    required this.id,
    required this.appLockEnabled,
    this.pinCode,
    required this.biometricEnabled,
    this.screenCaptureAllowed = false,
    required this.updatedAt,
  });

  final int id;
  final bool appLockEnabled;
  final String? pinCode;
  final bool biometricEnabled;
  final bool screenCaptureAllowed;
  final DateTime updatedAt;

  factory SecuritySetting.fromCompanion(SecuritySettingsCompanion c, int id) => SecuritySetting(
        id: id,
        appLockEnabled: _valueOr(c.appLockEnabled, false),
        pinCode: _blankToNull(_nullableValueOr(c.pinCode, null)),
        biometricEnabled: _valueOr(c.biometricEnabled, false),
        screenCaptureAllowed: _valueOr(c.screenCaptureAllowed, false),
        updatedAt: DateTime.now(),
      );

  factory SecuritySetting.fromJson(Map<String, dynamic> json) => SecuritySetting(
        id: (json['id'] as num?)?.toInt() ?? 0,
        appLockEnabled: json['appLockEnabled'] == true,
        pinCode: json['pinCode']?.toString(),
        biometricEnabled: json['biometricEnabled'] == true,
        screenCaptureAllowed: json['screenCaptureAllowed'] == true,
        updatedAt: _dateOrNow(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'appLockEnabled': appLockEnabled,
        'pinCode': pinCode,
        'biometricEnabled': biometricEnabled,
        'screenCaptureAllowed': screenCaptureAllowed,
        'updatedAt': updatedAt.toIso8601String(),
      };

  SecuritySetting copyWith({
    bool? appLockEnabled,
    Value<String?>? pinCode,
    bool? biometricEnabled,
    bool? screenCaptureAllowed,
    DateTime? updatedAt,
  }) =>
      SecuritySetting(
        id: id,
        appLockEnabled: appLockEnabled ?? this.appLockEnabled,
        pinCode: _blankToNull(_nullableValueOr(pinCode, this.pinCode)),
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        screenCaptureAllowed: screenCaptureAllowed ?? this.screenCaptureAllowed,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class SecuritySettingsCompanion {
  const SecuritySettingsCompanion.insert({this.appLockEnabled, this.pinCode, this.biometricEnabled, this.screenCaptureAllowed});

  final Value<bool>? appLockEnabled;
  final Value<String?>? pinCode;
  final Value<bool>? biometricEnabled;
  final Value<bool>? screenCaptureAllowed;
}

class AiSetting {
  const AiSetting({
    required this.id,
    required this.isEnabled,
    this.apiKey,
    required this.model,
    required this.updatedAt,
  });

  final int id;
  final bool isEnabled;
  final String? apiKey;
  final String model;
  final DateTime updatedAt;

  factory AiSetting.fromCompanion(AiSettingsCompanion c, int id) => AiSetting(
        id: id,
        isEnabled: _valueOr(c.isEnabled, false),
        apiKey: _blankToNull(_nullableValueOr(c.apiKey, null)),
        model: _valueOr(c.model, 'gpt-4.1-mini'),
        updatedAt: DateTime.now(),
      );

  factory AiSetting.fromJson(Map<String, dynamic> json) => AiSetting(
        id: (json['id'] as num?)?.toInt() ?? 0,
        isEnabled: json['isEnabled'] == true,
        apiKey: json['apiKey']?.toString(),
        model: (json['model'] ?? 'gpt-4.1-mini').toString(),
        updatedAt: _dateOrNow(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isEnabled': isEnabled,
        'apiKey': apiKey,
        'model': model,
        'updatedAt': updatedAt.toIso8601String(),
      };

  AiSetting copyWith({
    bool? isEnabled,
    Value<String?>? apiKey,
    String? model,
    DateTime? updatedAt,
  }) =>
      AiSetting(
        id: id,
        isEnabled: isEnabled ?? this.isEnabled,
        apiKey: _blankToNull(_nullableValueOr(apiKey, this.apiKey)),
        model: model ?? this.model,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class AiSettingsCompanion {
  const AiSettingsCompanion.insert({this.isEnabled, this.apiKey, this.model});

  final Value<bool>? isEnabled;
  final Value<String?>? apiKey;
  final Value<String>? model;
}

class CalendarSetting {
  const CalendarSetting({
    required this.id,
    required this.weekendMode,
    required this.showOfficialHolidays,
    required this.defaultView,
    required this.updatedAt,
  });

  final int id;
  final String weekendMode;
  final bool showOfficialHolidays;
  final String defaultView;
  final DateTime updatedAt;

  static CalendarSetting defaults() => CalendarSetting(
        id: 0,
        weekendMode: 'friday',
        showOfficialHolidays: true,
        defaultView: 'month',
        updatedAt: DateTime.now(),
      );

  factory CalendarSetting.fromCompanion(CalendarSettingsCompanion c, int id) => CalendarSetting(
        id: id,
        weekendMode: _valueOr(c.weekendMode, 'friday'),
        showOfficialHolidays: _valueOr(c.showOfficialHolidays, true),
        defaultView: _valueOr(c.defaultView, 'month'),
        updatedAt: DateTime.now(),
      );

  factory CalendarSetting.fromJson(Map<String, dynamic> json) => CalendarSetting(
        id: (json['id'] as num?)?.toInt() ?? 0,
        weekendMode: (json['weekendMode'] ?? 'friday').toString(),
        showOfficialHolidays: json['showOfficialHolidays'] != false,
        defaultView: (json['defaultView'] ?? 'month').toString(),
        updatedAt: _dateOrNow(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'weekendMode': weekendMode,
        'showOfficialHolidays': showOfficialHolidays,
        'defaultView': defaultView,
        'updatedAt': updatedAt.toIso8601String(),
      };

  CalendarSetting copyWith({
    String? weekendMode,
    bool? showOfficialHolidays,
    String? defaultView,
    DateTime? updatedAt,
  }) =>
      CalendarSetting(
        id: id,
        weekendMode: weekendMode ?? this.weekendMode,
        showOfficialHolidays: showOfficialHolidays ?? this.showOfficialHolidays,
        defaultView: defaultView ?? this.defaultView,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class CalendarSettingsCompanion {
  const CalendarSettingsCompanion.insert({this.weekendMode, this.showOfficialHolidays, this.defaultView});

  final Value<String>? weekendMode;
  final Value<bool>? showOfficialHolidays;
  final Value<String>? defaultView;
}
