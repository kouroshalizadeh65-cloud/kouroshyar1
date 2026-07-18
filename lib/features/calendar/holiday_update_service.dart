import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String kouroshyarHolidayFeedFormat = 'kouroshyar-holiday-feed-v1';
const String kouroshyarWorkScheduleFeedFormat = 'kouroshyar-work-schedule-feed-v1';
const String configuredHolidayFeedUrl = String.fromEnvironment('KOUROSHYAR_HOLIDAY_FEED_URL');
const String configuredHolidayFeedPublicKey = String.fromEnvironment('KOUROSHYAR_HOLIDAY_PUBLIC_KEY');
const String configuredWorkingHoursFeedUrl = String.fromEnvironment('KOUROSHYAR_WORKING_HOURS_FEED_URL');

class HolidayUpdateException implements Exception {
  const HolidayUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

String workingHoursFeedUrlFromHolidayFeedUrl(String holidayFeedUrl) {
  final source = holidayFeedUrl.trim();
  if (source.isEmpty) return '';
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return '';
  final segments = List<String>.of(uri.pathSegments);
  if (segments.isEmpty) {
    segments.add('working_hours.json');
  } else if (segments.last.toLowerCase().endsWith('.json')) {
    segments[segments.length - 1] = 'working_hours.json';
  } else {
    segments.add('working_hours.json');
  }
  return uri.replace(pathSegments: segments).toString();
}

String _requiredText(Map<String, dynamic> json, String key, {int maxLength = 500}) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty || value.length > maxLength) {
    throw HolidayUpdateException('فیلد $key معتبر نیست.');
  }
  return value;
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw == null) return const <String>[];
  if (raw is! List) throw HolidayUpdateException('فیلد $key باید فهرست باشد.');
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .take(50)
      .toList(growable: false);
}

void _validateJalaliDate(String value, {required String fieldLabel}) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw HolidayUpdateException('$fieldLabel معتبر نیست.');
  }
  final parts = value.split('-').map(int.parse).toList(growable: false);
  if (parts[1] < 1 || parts[1] > 12 || parts[2] < 1 || parts[2] > 31) {
    throw HolidayUpdateException('مقدار ماه یا روز $fieldLabel معتبر نیست.');
  }
}

String? _httpsUrlOrNull(Map<String, dynamic> json, String key) {
  final text = json[key]?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw HolidayUpdateException('نشانی $key باید HTTPS معتبر باشد.');
  }
  return text;
}

DateTime _publishedAt(Map<String, dynamic> json) {
  final parsed = DateTime.tryParse(_requiredText(json, 'publishedAt', maxLength: 64));
  if (parsed == null) throw const HolidayUpdateException('زمان انتشار اطلاعیه معتبر نیست.');
  return parsed;
}

String? _timeOrNull(Map<String, dynamic> json, String key) {
  final text = json[key]?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text);
  if (match == null) throw HolidayUpdateException('فیلد $key باید به صورت HH:mm باشد.');
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) throw HolidayUpdateException('مقدار $key معتبر نیست.');
  return text;
}

class OfficialHolidayUpdate {
  const OfficialHolidayUpdate({
    required this.id,
    required this.jalaliDate,
    required this.title,
    required this.type,
    required this.scope,
    required this.authority,
    required this.publishedAt,
    required this.status,
    this.province,
    this.sourceUrl,
    this.includedOrganizations = const <String>[],
    this.excludedOrganizations = const <String>[],
    this.note,
  });

  final String id;
  final String jalaliDate;
  final String title;
  final String type;
  final String scope;
  final String? province;
  final String authority;
  final String? sourceUrl;
  final DateTime publishedAt;
  final String status;
  final List<String> includedOrganizations;
  final List<String> excludedOrganizations;
  final String? note;

  bool get isActive => status == 'active' || status == 'updated';

  String get typeLabel => switch (type) {
        'official' => 'تعطیل رسمی',
        'national_emergency' => 'تعطیلی فوق‌العاده سراسری',
        'provincial' => 'تعطیلی استانی',
        'administrative' => 'تعطیلی ادارات',
        'judiciary' => 'تعطیلی واحدهای قضایی',
        _ => 'اطلاعیه تعطیلی',
      };

  bool appliesToProvince(String selectedProvince) {
    if (!isActive) return false;
    if (scope == 'national') return true;
    if (scope != 'province') return false;
    final eventProvince = province?.trim() ?? '';
    if (eventProvince.isEmpty) return false;
    return eventProvince == selectedProvince.trim();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'date': jalaliDate,
        'title': title,
        'type': type,
        'scope': scope,
        if (province != null) 'province': province,
        'authority': authority,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'publishedAt': publishedAt.toIso8601String(),
        'status': status,
        if (includedOrganizations.isNotEmpty) 'includedOrganizations': includedOrganizations,
        if (excludedOrganizations.isNotEmpty) 'excludedOrganizations': excludedOrganizations,
        if (note != null) 'note': note,
      };

  factory OfficialHolidayUpdate.fromJson(Map<String, dynamic> json) {
    final date = _requiredText(json, 'date', maxLength: 10);
    _validateJalaliDate(date, fieldLabel: 'تاریخ شمسی تعطیلی');

    const allowedTypes = <String>{
      'official',
      'national_emergency',
      'provincial',
      'administrative',
      'judiciary',
    };
    const allowedScopes = <String>{'national', 'province', 'organization'};
    const allowedStatuses = <String>{'active', 'updated', 'cancelled'};

    final type = _requiredText(json, 'type', maxLength: 40);
    final scope = _requiredText(json, 'scope', maxLength: 40);
    final status = _requiredText(json, 'status', maxLength: 40);
    if (!allowedTypes.contains(type)) throw HolidayUpdateException('نوع تعطیلی ناشناخته است: $type');
    if (!allowedScopes.contains(scope)) throw HolidayUpdateException('محدوده تعطیلی ناشناخته است: $scope');
    if (!allowedStatuses.contains(status)) throw HolidayUpdateException('وضعیت تعطیلی ناشناخته است: $status');

    return OfficialHolidayUpdate(
      id: _requiredText(json, 'id', maxLength: 120),
      jalaliDate: date,
      title: _requiredText(json, 'title'),
      type: type,
      scope: scope,
      province: json['province']?.toString().trim(),
      authority: _requiredText(json, 'authority'),
      sourceUrl: _httpsUrlOrNull(json, 'sourceUrl'),
      publishedAt: _publishedAt(json),
      status: status,
      includedOrganizations: _stringList(json, 'includedOrganizations'),
      excludedOrganizations: _stringList(json, 'excludedOrganizations'),
      note: json['note']?.toString().trim(),
    );
  }
}

class WorkScheduleUpdate {
  const WorkScheduleUpdate({
    required this.id,
    required this.jalaliDate,
    required this.title,
    required this.scheduleType,
    required this.scope,
    required this.authority,
    required this.publishedAt,
    required this.status,
    this.province,
    this.endJalaliDate,
    this.startTime,
    this.endTime,
    this.sourceUrl,
    this.includedOrganizations = const <String>[],
    this.excludedOrganizations = const <String>[],
    this.note,
  });

  final String id;
  final String jalaliDate;
  final String? endJalaliDate;
  final String title;
  final String scheduleType;
  final String scope;
  final String? province;
  final String authority;
  final String? sourceUrl;
  final DateTime publishedAt;
  final String status;
  final String? startTime;
  final String? endTime;
  final List<String> includedOrganizations;
  final List<String> excludedOrganizations;
  final String? note;

  bool get isActive => status == 'active' || status == 'updated';

  bool get isPeriodicSchedule =>
      scheduleType == 'changed_hours' && endJalaliDate != null && endJalaliDate != jalaliDate;

  String get typeLabel {
    if (isPeriodicSchedule) return 'ساعت کاری دوره‌ای';
    return switch (scheduleType) {
        'changed_hours' => 'تغییر ساعات کاری',
        'remote_work' => 'دورکاری',
        'delayed_start' => 'شروع کار با تأخیر',
        'early_close' => 'پایان کار زودتر از موعد',
        _ => 'تغییر برنامه کاری',
      };
  }

  String get scopeLabel => switch (scope) {
        'national' => 'سراسری',
        'province' => province == null || province!.trim().isEmpty ? 'استانی' : 'استان ${province!.trim()}',
        _ => 'محدود به دستگاه‌های اعلام‌شده',
      };

  String get timeLabel {
    if (startTime != null && endTime != null) return 'ساعت $startTime تا $endTime';
    if (startTime != null) return 'شروع فعالیت از ساعت $startTime';
    if (endTime != null) return 'پایان فعالیت در ساعت $endTime';
    return 'ساعت دقیق در اطلاعیه درج نشده است';
  }

  bool appliesToProvince(String selectedProvince) {
    if (!isActive) return false;
    if (scope == 'national') return true;
    if (scope != 'province') return false;
    final eventProvince = province?.trim() ?? '';
    if (eventProvince.isEmpty) return false;
    return eventProvince == selectedProvince.trim();
  }

  bool appliesToJalaliDate(String jalaliDateKey) {
    final last = endJalaliDate ?? jalaliDate;
    return jalaliDateKey.compareTo(jalaliDate) >= 0 && jalaliDateKey.compareTo(last) <= 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'date': jalaliDate,
        if (endJalaliDate != null) 'endDate': endJalaliDate,
        'title': title,
        'scheduleType': scheduleType,
        'scope': scope,
        if (province != null) 'province': province,
        'authority': authority,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'publishedAt': publishedAt.toIso8601String(),
        'status': status,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (includedOrganizations.isNotEmpty) 'includedOrganizations': includedOrganizations,
        if (excludedOrganizations.isNotEmpty) 'excludedOrganizations': excludedOrganizations,
        if (note != null) 'note': note,
      };

  factory WorkScheduleUpdate.fromJson(Map<String, dynamic> json) {
    final date = _requiredText(json, 'date', maxLength: 10);
    _validateJalaliDate(date, fieldLabel: 'تاریخ شروع تغییر ساعت');
    final endDateText = json['endDate']?.toString().trim();
    if (endDateText != null && endDateText.isNotEmpty) {
      _validateJalaliDate(endDateText, fieldLabel: 'تاریخ پایان تغییر ساعت');
      if (endDateText.compareTo(date) < 0) {
        throw const HolidayUpdateException('تاریخ پایان تغییر ساعت قبل از تاریخ شروع است.');
      }
    }

    const allowedTypes = <String>{'changed_hours', 'remote_work', 'delayed_start', 'early_close'};
    const allowedScopes = <String>{'national', 'province', 'organization'};
    const allowedStatuses = <String>{'active', 'updated', 'cancelled'};
    final scheduleType = _requiredText(json, 'scheduleType', maxLength: 40);
    final scope = _requiredText(json, 'scope', maxLength: 40);
    final status = _requiredText(json, 'status', maxLength: 40);
    if (!allowedTypes.contains(scheduleType)) {
      throw HolidayUpdateException('نوع تغییر ساعات کاری ناشناخته است: $scheduleType');
    }
    if (!allowedScopes.contains(scope)) throw HolidayUpdateException('محدوده تغییر ساعات کاری ناشناخته است: $scope');
    if (!allowedStatuses.contains(status)) throw HolidayUpdateException('وضعیت تغییر ساعات کاری ناشناخته است: $status');

    return WorkScheduleUpdate(
      id: _requiredText(json, 'id', maxLength: 120),
      jalaliDate: date,
      endJalaliDate: endDateText == null || endDateText.isEmpty ? null : endDateText,
      title: _requiredText(json, 'title'),
      scheduleType: scheduleType,
      scope: scope,
      province: json['province']?.toString().trim(),
      authority: _requiredText(json, 'authority'),
      sourceUrl: _httpsUrlOrNull(json, 'sourceUrl'),
      publishedAt: _publishedAt(json),
      status: status,
      startTime: _timeOrNull(json, 'startTime'),
      endTime: _timeOrNull(json, 'endTime'),
      includedOrganizations: _stringList(json, 'includedOrganizations'),
      excludedOrganizations: _stringList(json, 'excludedOrganizations'),
      note: json['note']?.toString().trim(),
    );
  }
}

class HolidayFeedSnapshot {
  const HolidayFeedSnapshot({
    required this.revision,
    required this.generatedAt,
    required this.holidays,
  });

  final int revision;
  final DateTime generatedAt;
  final List<OfficialHolidayUpdate> holidays;

  Map<String, dynamic> toPayloadJson() => <String, dynamic>{
        'format': kouroshyarHolidayFeedFormat,
        'revision': revision,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'holidays': holidays.map((item) => item.toJson()).toList(growable: false),
      };

  String encodeForStorage() => jsonEncode(toPayloadJson());

  Set<String> activeIdsForProvince(String province) => holidays
      .where((item) => item.appliesToProvince(province))
      .map((item) => item.id)
      .toSet();

  factory HolidayFeedSnapshot.fromPayloadJson(Map<String, dynamic> json) {
    if (json['format'] != kouroshyarHolidayFeedFormat) {
      throw const HolidayUpdateException('قالب فایل تعطیلات برای کوروش‌یار معتبر نیست.');
    }
    final revision = (json['revision'] as num?)?.toInt();
    if (revision == null || revision < 1) {
      throw const HolidayUpdateException('شماره بازبینی فایل تعطیلات معتبر نیست.');
    }
    final generatedAt = DateTime.tryParse(json['generatedAt']?.toString() ?? '');
    if (generatedAt == null) throw const HolidayUpdateException('زمان تولید فایل تعطیلات معتبر نیست.');
    if (generatedAt.isAfter(DateTime.now().toUtc().add(const Duration(hours: 24)))) {
      throw const HolidayUpdateException('زمان تولید فایل تعطیلات در آینده است.');
    }
    final rawHolidays = json['holidays'];
    if (rawHolidays is! List || rawHolidays.length > 1000) {
      throw const HolidayUpdateException('فهرست تعطیلات معتبر نیست یا بیش از حد بزرگ است.');
    }
    final holidays = rawHolidays
        .map((item) {
          if (item is! Map) throw const HolidayUpdateException('یکی از رکوردهای تعطیلات معتبر نیست.');
          return OfficialHolidayUpdate.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
    final ids = <String>{};
    for (final item in holidays) {
      if (!ids.add(item.id)) throw HolidayUpdateException('شناسه تکراری در فایل تعطیلات وجود دارد: ${item.id}');
    }
    return HolidayFeedSnapshot(revision: revision, generatedAt: generatedAt.toUtc(), holidays: holidays);
  }

  static HolidayFeedSnapshot? tryDecodeStored(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return HolidayFeedSnapshot.fromPayloadJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

class WorkScheduleFeedSnapshot {
  const WorkScheduleFeedSnapshot({
    required this.revision,
    required this.generatedAt,
    required this.schedules,
  });

  final int revision;
  final DateTime generatedAt;
  final List<WorkScheduleUpdate> schedules;

  Map<String, dynamic> toPayloadJson() => <String, dynamic>{
        'format': kouroshyarWorkScheduleFeedFormat,
        'revision': revision,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'schedules': schedules.map((item) => item.toJson()).toList(growable: false),
      };

  String encodeForStorage() => jsonEncode(toPayloadJson());

  Set<String> activeIdsForProvince(String province) => schedules
      .where((item) => item.appliesToProvince(province))
      .map((item) => item.id)
      .toSet();

  List<WorkScheduleUpdate> schedulesForProvinceAndDate(String province, String jalaliDate) => schedules
      .where((item) => item.appliesToProvince(province) && item.appliesToJalaliDate(jalaliDate))
      .toList(growable: false)
    ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

  factory WorkScheduleFeedSnapshot.fromPayloadJson(Map<String, dynamic> json) {
    if (json['format'] != kouroshyarWorkScheduleFeedFormat) {
      throw const HolidayUpdateException('قالب فایل تغییر ساعات کاری برای کوروش‌یار معتبر نیست.');
    }
    final revision = (json['revision'] as num?)?.toInt();
    if (revision == null || revision < 1) {
      throw const HolidayUpdateException('شماره بازبینی فایل تغییر ساعات کاری معتبر نیست.');
    }
    final generatedAt = DateTime.tryParse(json['generatedAt']?.toString() ?? '');
    if (generatedAt == null) throw const HolidayUpdateException('زمان تولید فایل تغییر ساعات کاری معتبر نیست.');
    if (generatedAt.isAfter(DateTime.now().toUtc().add(const Duration(hours: 24)))) {
      throw const HolidayUpdateException('زمان تولید فایل تغییر ساعات کاری در آینده است.');
    }
    final rawSchedules = json['schedules'];
    if (rawSchedules is! List || rawSchedules.length > 1500) {
      throw const HolidayUpdateException('فهرست تغییر ساعات کاری معتبر نیست یا بیش از حد بزرگ است.');
    }
    final schedules = rawSchedules
        .map((item) {
          if (item is! Map) throw const HolidayUpdateException('یکی از رکوردهای تغییر ساعات کاری معتبر نیست.');
          return WorkScheduleUpdate.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
    final ids = <String>{};
    for (final item in schedules) {
      if (!ids.add(item.id)) {
        throw HolidayUpdateException('شناسه تکراری در فایل تغییر ساعات کاری وجود دارد: ${item.id}');
      }
    }
    return WorkScheduleFeedSnapshot(revision: revision, generatedAt: generatedAt.toUtc(), schedules: schedules);
  }

  static WorkScheduleFeedSnapshot? tryDecodeStored(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WorkScheduleFeedSnapshot.fromPayloadJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

Future<Uint8List> _downloadEnvelope({
  required String feedUrl,
  required String userAgent,
  required HttpClient? suppliedClient,
}) async {
  final uri = Uri.tryParse(feedUrl);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw const HolidayUpdateException('نشانی منبع باید HTTPS معتبر باشد.');
  }
  final client = suppliedClient ?? HttpClient();
  if (suppliedClient == null) {
    client.connectionTimeout = const Duration(seconds: 12);
    client.idleTimeout = const Duration(seconds: 12);
    client.userAgent = userAgent;
  }
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.isRedirect) throw const HolidayUpdateException('تغییر مسیر منبع پذیرفته نشد.');
    if (response.statusCode != HttpStatus.ok) {
      throw HolidayUpdateException('دریافت منبع با خطای HTTP ${response.statusCode} متوقف شد.');
    }
    const maxBytes = 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      length += chunk.length;
      if (length > maxBytes) throw const HolidayUpdateException('فایل منبع بیش از حد مجاز بزرگ است.');
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } on HolidayUpdateException {
    rethrow;
  } on SocketException {
    throw const HolidayUpdateException('اتصال اینترنت یا دسترسی به منبع برقرار نشد.');
  } on HandshakeException {
    throw const HolidayUpdateException('اعتبار اتصال امن HTTPS منبع تأیید نشد.');
  } on FormatException {
    throw const HolidayUpdateException('ساختار پاسخ منبع معتبر نیست.');
  } catch (error) {
    throw HolidayUpdateException('به‌روزرسانی انجام نشد: $error');
  } finally {
    if (suppliedClient == null) client.close(force: true);
  }
}

Future<Map<String, dynamic>> _verifyEnvelopePayload(
  Uint8List envelopeBytes, {
  required String expectedFormat,
  required String publicKeyBase64,
}) async {
  dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(envelopeBytes));
  } catch (_) {
    throw const HolidayUpdateException('فایل دریافتی JSON معتبر نیست.');
  }
  if (decoded is! Map) throw const HolidayUpdateException('پاکت امضای منبع معتبر نیست.');
  final envelope = Map<String, dynamic>.from(decoded);
  if (envelope['format'] != expectedFormat) {
    throw const HolidayUpdateException('قالب پاکت امضاشده معتبر نیست.');
  }
  final payloadBase64 = envelope['payload']?.toString().trim() ?? '';
  final signatureBase64 = envelope['signature']?.toString().trim() ?? '';
  if (payloadBase64.isEmpty || signatureBase64.isEmpty) {
    throw const HolidayUpdateException('امضای دیجیتال یا محتوای فایل موجود نیست.');
  }

  Uint8List payloadBytes;
  Uint8List signatureBytes;
  Uint8List publicKeyBytes;
  try {
    payloadBytes = base64Decode(payloadBase64);
    signatureBytes = base64Decode(signatureBase64);
    publicKeyBytes = base64Decode(publicKeyBase64);
  } catch (_) {
    throw const HolidayUpdateException('کدگذاری امضا یا کلید عمومی معتبر نیست.');
  }
  if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
    throw const HolidayUpdateException('طول کلید عمومی یا امضای Ed25519 معتبر نیست.');
  }

  final verified = await Ed25519().verify(
    payloadBytes,
    signature: Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    ),
  );
  if (!verified) throw const HolidayUpdateException('امضای دیجیتال فایل معتبر نیست.');

  dynamic payloadDecoded;
  try {
    payloadDecoded = jsonDecode(utf8.decode(payloadBytes));
  } catch (_) {
    throw const HolidayUpdateException('محتوای امضاشده JSON معتبر نیست.');
  }
  if (payloadDecoded is! Map) throw const HolidayUpdateException('محتوای امضاشده معتبر نیست.');
  return Map<String, dynamic>.from(payloadDecoded);
}

class HolidayUpdateService {
  HolidayUpdateService({
    String? feedUrl,
    String? publicKeyBase64,
    HttpClient? httpClient,
  })  : feedUrl = (feedUrl ?? configuredHolidayFeedUrl).trim(),
        publicKeyBase64 = (publicKeyBase64 ?? configuredHolidayFeedPublicKey).trim(),
        _httpClient = httpClient;

  final String feedUrl;
  final String publicKeyBase64;
  final HttpClient? _httpClient;

  bool get isConfigured => feedUrl.isNotEmpty && publicKeyBase64.isNotEmpty;

  Future<HolidayFeedSnapshot> fetchAndVerify({int currentRevision = 0}) async {
    if (!isConfigured) {
      throw const HolidayUpdateException('منبع امضاشده تعطیلات هنوز در GitHub Variables تنظیم نشده است.');
    }
    final bytes = await _downloadEnvelope(
      feedUrl: feedUrl,
      userAgent: 'KouroshYar/3.6.55 holiday-updater',
      suppliedClient: _httpClient,
    );
    return verifyEnvelope(bytes, currentRevision: currentRevision);
  }

  Future<HolidayFeedSnapshot> verifyEnvelope(Uint8List envelopeBytes, {int currentRevision = 0}) async {
    final payload = await _verifyEnvelopePayload(
      envelopeBytes,
      expectedFormat: kouroshyarHolidayFeedFormat,
      publicKeyBase64: publicKeyBase64,
    );
    final snapshot = HolidayFeedSnapshot.fromPayloadJson(payload);
    if (snapshot.revision < currentRevision) {
      throw const HolidayUpdateException('فایل دریافتی از نسخه ذخیره‌شده قدیمی‌تر است.');
    }
    return snapshot;
  }
}

class WorkScheduleUpdateService {
  WorkScheduleUpdateService({
    String? feedUrl,
    String? holidayFeedUrl,
    String? publicKeyBase64,
    HttpClient? httpClient,
  })  : feedUrl = (feedUrl ??
                (configuredWorkingHoursFeedUrl.trim().isNotEmpty
                    ? configuredWorkingHoursFeedUrl
                    : workingHoursFeedUrlFromHolidayFeedUrl(holidayFeedUrl ?? configuredHolidayFeedUrl)))
            .trim(),
        publicKeyBase64 = (publicKeyBase64 ?? configuredHolidayFeedPublicKey).trim(),
        _httpClient = httpClient;

  final String feedUrl;
  final String publicKeyBase64;
  final HttpClient? _httpClient;

  bool get isConfigured => feedUrl.isNotEmpty && publicKeyBase64.isNotEmpty;

  Future<WorkScheduleFeedSnapshot> fetchAndVerify({int currentRevision = 0}) async {
    if (!isConfigured) {
      throw const HolidayUpdateException('منبع امضاشده تغییر ساعات کاری تنظیم نشده است.');
    }
    final bytes = await _downloadEnvelope(
      feedUrl: feedUrl,
      userAgent: 'KouroshYar/3.6.55 working-hours-updater',
      suppliedClient: _httpClient,
    );
    return verifyEnvelope(bytes, currentRevision: currentRevision);
  }

  Future<WorkScheduleFeedSnapshot> verifyEnvelope(Uint8List envelopeBytes, {int currentRevision = 0}) async {
    final payload = await _verifyEnvelopePayload(
      envelopeBytes,
      expectedFormat: kouroshyarWorkScheduleFeedFormat,
      publicKeyBase64: publicKeyBase64,
    );
    final snapshot = WorkScheduleFeedSnapshot.fromPayloadJson(payload);
    if (snapshot.revision < currentRevision) {
      throw const HolidayUpdateException('فایل تغییر ساعات کاری از نسخه ذخیره‌شده قدیمی‌تر است.');
    }
    return snapshot;
  }
}
