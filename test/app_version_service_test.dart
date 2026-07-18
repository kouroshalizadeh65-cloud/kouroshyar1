import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/core/app_info/app_version_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kouroshyar/app_info');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    AppVersionService.resetCacheForTesting();
  });

  test('نسخه برنامه از اطلاعات واقعی بسته نصب‌شده خوانده می‌شود', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAppVersion');
      return <String, Object>{
        'versionName': '9.8.7',
        'versionCode': 654,
        'packageName': 'com.example.kouroshyar',
      };
    });

    final info = await AppVersionService.getInfo();

    expect(info.available, isTrue);
    expect(info.compactDisplay, '9.8.7+654');
    expect(info.settingsDisplay, 'کوروش‌یار v9.8.7+654');
    expect(info.packageName, 'com.example.kouroshyar');
  });

  test('نبود کانال بومی باعث نمایش امن نسخه نامشخص می‌شود', () async {
    final info = await AppVersionService.getInfo();

    expect(info.available, isFalse);
    expect(info.compactDisplay, 'نامشخص');
    expect(info.settingsDisplay, 'کوروش‌یار — نسخه نامشخص');
  });

  test('نسخه ثابت در محل‌های اجرایی برنامه تعریف نشده است', () {
    final settingsSource = File('lib/features/settings/settings_screen.dart').readAsStringSync();
    final appInfoSource = File('lib/features/app_info/app_info_screen.dart').readAsStringSync();
    final databaseSource = File('lib/database/app_database.dart').readAsStringSync();

    final latinVersionLiteral = RegExp(r'''['"](?:v)?\d+\.\d+\.\d+(?:\+\d+)?['"]''');
    final persianVersionLiteral = RegExp(r'''['"](?:v)?[۰-۹]+\.[۰-۹]+\.[۰-۹]+(?:\+[۰-۹]+)?['"]''');

    expect(latinVersionLiteral.hasMatch(settingsSource), isFalse);
    expect(persianVersionLiteral.hasMatch(settingsSource), isFalse);
    expect(latinVersionLiteral.hasMatch(appInfoSource), isFalse);
    expect(persianVersionLiteral.hasMatch(appInfoSource), isFalse);
    expect(RegExp(r'''['"]appVersion['"]\s*:\s*['"]''').hasMatch(databaseSource), isFalse);
  });
}
