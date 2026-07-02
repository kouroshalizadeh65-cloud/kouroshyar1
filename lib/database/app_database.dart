import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight local JSON database for KouroshYar.
///
/// Lightweight local storage used by the app screens.
const String kouroshyarDatabaseFileName = 'kouroshyar_data.json';

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

  final StreamController<String> _changes = StreamController<String>.broadcast();
  Map<String, dynamic>? _store;
  File? _file;

  Future<void> close() async {
    await _changes.close();
  }

  SelectQuery<T> select<T>(TableRef<T> table) => SelectQuery<T>(this, table);
  InsertStatement<T> into<T>(TableRef<T> table) => InsertStatement<T>(this, table);
  UpdateStatement<T> update<T>(TableRef<T> table) => UpdateStatement<T>(this, table);
  DeleteStatement<T> delete<T>(TableRef<T> table) => DeleteStatement<T>(this, table);

  Future<File> databaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, kouroshyarDatabaseFileName));
  }

  Future<void> _ensureLoaded() async {
    if (_store != null) return;
    _file = await databaseFile();
    if (!await _file!.exists()) {
      _store = <String, dynamic>{'meta': <String, dynamic>{}};
      await _save();
      return;
    }

    try {
      final raw = await _file!.readAsString();
      final decoded = jsonDecode(raw);
      _store = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{'meta': <String, dynamic>{}};
    } catch (_) {
      final backup = File('${_file!.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}.bak');
      if (await _file!.exists()) {
        await _file!.copy(backup.path);
      }
      _store = <String, dynamic>{'meta': <String, dynamic>{}};
      await _save();
    }
  }

  Future<void> _save() async {
    final file = _file ?? await databaseFile();
    _file = file;
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_store ?? <String, dynamic>{'meta': <String, dynamic>{}}));
  }

  Future<Directory> backupDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'kouroshyar_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<File?> createBackup({String reason = 'auto'}) async {
    await _ensureLoaded();
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
    final backup = File(p.join(backupDir.path, 'kouroshyar_backup_${stamp}_$safeReason.json'));
    await source.copy(backup.path);
    await _trimBackups(maxCount: 10);
    return backup;
  }

  Future<List<File>> listBackups() async {
    final backupDir = await backupDirectory();
    final files = await backupDir
        .list()
        .where((e) => e is File && p.basename(e.path).startsWith('kouroshyar_backup_'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> restoreBackup(File backup) async {
    await _ensureLoaded();
    await createBackup(reason: 'before_restore');
    final target = _file ?? await databaseFile();
    await backup.copy(target.path);
    _store = null;
    await _ensureLoaded();
    _changes.add('*');
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

  Future<List<T>> _readTable<T>(TableRef<T> table) async {
    await _ensureLoaded();
    final raw = _store![table.name];
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((item) => table.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _writeTable<T>(TableRef<T> table, List<T> rows) async {
    await _ensureLoaded();
    _store![table.name] = rows.map(table.toJson).toList();
    await _save();
    try {
      await createBackup(reason: table.name);
    } catch (_) {
      // Backup failure must not block saving the user's data.
    }
    _changes.add(table.name);
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

class Case {
  const Case({
    required this.id,
    required this.title,
    this.clientName,
    this.opponentName,
    this.subject,
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
    required this.createdAt,
  });

  final int id;
  final int caseId;
  final String title;
  final String? eventType;
  final String? description;
  final DateTime eventDate;
  final DateTime createdAt;

  factory CaseTimelineEvent.fromCompanion(CaseTimelineEventsCompanion c, int id) => CaseTimelineEvent(
        id: id,
        caseId: c.caseId,
        title: c.title,
        eventType: _blankToNull(_nullableValueOr(c.eventType, null)),
        description: _blankToNull(_nullableValueOr(c.description, null)),
        eventDate: _valueOr(c.eventDate, DateTime.now()),
        createdAt: DateTime.now(),
      );

  factory CaseTimelineEvent.fromJson(Map<String, dynamic> json) => CaseTimelineEvent(
        id: (json['id'] as num?)?.toInt() ?? 0,
        caseId: (json['caseId'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '').toString(),
        eventType: json['eventType']?.toString(),
        description: json['description']?.toString(),
        eventDate: _dateOrNow(json['eventDate']),
        createdAt: _dateOrNow(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'caseId': caseId,
        'title': title,
        'eventType': eventType,
        'description': description,
        'eventDate': eventDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}

class CaseTimelineEventsCompanion {
  const CaseTimelineEventsCompanion.insert({
    required this.caseId,
    required this.title,
    this.eventType,
    this.description,
    this.eventDate,
  });

  final int caseId;
  final String title;
  final Value<String?>? eventType;
  final Value<String?>? description;
  final Value<DateTime>? eventDate;
}

class Deadline {
  const Deadline({
    required this.id,
    this.caseId,
    required this.title,
    this.deadlineType,
    required this.dueDate,
    required this.priority,
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
  });

  final int id;
  final int? caseId;
  final String type;
  final String title;
  final double amount;
  final String? category;
  final DateTime date;
  final String? notes;

  factory FinanceItem.fromCompanion(FinanceItemsCompanion c, int id) => FinanceItem(
        id: id,
        caseId: _nullableValueOr(c.caseId, null),
        type: c.type,
        title: c.title,
        amount: c.amount,
        category: _blankToNull(_nullableValueOr(c.category, null)),
        date: _valueOr(c.date, DateTime.now()),
        notes: _blankToNull(_nullableValueOr(c.notes, null)),
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
  });

  final Value<int?>? caseId;
  final String type;
  final String title;
  final double amount;
  final Value<String?>? category;
  final Value<DateTime>? date;
  final Value<String?>? notes;
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
    required this.updatedAt,
  });

  final int id;
  final bool appLockEnabled;
  final String? pinCode;
  final bool biometricEnabled;
  final DateTime updatedAt;

  factory SecuritySetting.fromCompanion(SecuritySettingsCompanion c, int id) => SecuritySetting(
        id: id,
        appLockEnabled: _valueOr(c.appLockEnabled, false),
        pinCode: _blankToNull(_nullableValueOr(c.pinCode, null)),
        biometricEnabled: _valueOr(c.biometricEnabled, false),
        updatedAt: DateTime.now(),
      );

  factory SecuritySetting.fromJson(Map<String, dynamic> json) => SecuritySetting(
        id: (json['id'] as num?)?.toInt() ?? 0,
        appLockEnabled: json['appLockEnabled'] == true,
        pinCode: json['pinCode']?.toString(),
        biometricEnabled: json['biometricEnabled'] == true,
        updatedAt: _dateOrNow(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'appLockEnabled': appLockEnabled,
        'pinCode': pinCode,
        'biometricEnabled': biometricEnabled,
        'updatedAt': updatedAt.toIso8601String(),
      };

  SecuritySetting copyWith({
    bool? appLockEnabled,
    Value<String?>? pinCode,
    bool? biometricEnabled,
    DateTime? updatedAt,
  }) =>
      SecuritySetting(
        id: id,
        appLockEnabled: appLockEnabled ?? this.appLockEnabled,
        pinCode: _blankToNull(_nullableValueOr(pinCode, this.pinCode)),
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class SecuritySettingsCompanion {
  const SecuritySettingsCompanion.insert({this.appLockEnabled, this.pinCode, this.biometricEnabled});

  final Value<bool>? appLockEnabled;
  final Value<String?>? pinCode;
  final Value<bool>? biometricEnabled;
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
