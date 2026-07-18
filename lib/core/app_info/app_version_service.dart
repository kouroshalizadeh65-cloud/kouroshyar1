import 'package:flutter/services.dart';

/// Runtime version metadata read from the installed Android package.
///
/// The source of truth is the APK itself, not a duplicated version string in
/// Dart. This prevents the settings, about page, and backup manifest from
/// drifting away from `pubspec.yaml` / the generated Android package.
class AppVersionInfo {
  const AppVersionInfo({
    required this.versionName,
    required this.versionCode,
    required this.packageName,
    this.available = true,
  });

  const AppVersionInfo.unavailable()
      : versionName = '',
        versionCode = 0,
        packageName = '',
        available = false;

  final String versionName;
  final int versionCode;
  final String packageName;
  final bool available;

  String get compactDisplay {
    if (!available || versionName.isEmpty) return 'نامشخص';
    if (versionCode <= 0) return versionName;
    return '$versionName+$versionCode';
  }

  String get settingsDisplay {
    if (!available || versionName.isEmpty) return 'کوروش‌یار — نسخه نامشخص';
    return 'کوروش‌یار v$compactDisplay';
  }
}

class AppVersionService {
  AppVersionService._();

  static const MethodChannel _channel = MethodChannel('kouroshyar/app_info');
  static AppVersionInfo? _cached;

  static Future<AppVersionInfo> getInfo({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached!;

    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAppVersion');
      if (raw == null) return _unavailable();

      final versionName = raw['versionName']?.toString().trim() ?? '';
      final versionCode = _parseVersionCode(raw['versionCode']);
      final packageName = raw['packageName']?.toString().trim() ?? '';
      if (versionName.isEmpty) return _unavailable();

      final info = AppVersionInfo(
        versionName: versionName,
        versionCode: versionCode,
        packageName: packageName,
      );
      _cached = info;
      return info;
    } on MissingPluginException {
      return _unavailable();
    } on PlatformException {
      return _unavailable();
    }
  }

  static int _parseVersionCode(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static AppVersionInfo _unavailable() => const AppVersionInfo.unavailable();

  /// Used only by tests so each case can install its own MethodChannel mock.
  static void resetCacheForTesting() {
    _cached = null;
  }
}
