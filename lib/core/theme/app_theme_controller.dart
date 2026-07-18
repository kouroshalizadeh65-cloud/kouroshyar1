import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _appearanceFileName = 'kouroshyar_appearance_settings.json';

class AppThemeController extends ChangeNotifier {
  String _mode = 'light';

  String get mode => _mode;

  ThemeMode get themeMode {
    switch (_mode) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, _appearanceFileName));
  }

  Future<void> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['mode'] is String) {
        final value = decoded['mode'] as String;
        if (value == 'light' || value == 'dark' || value == 'system') {
          _mode = value;
        }
      }
    } catch (_) {
      _mode = 'light';
    }
  }

  Future<void> setMode(String value) async {
    final next = (value == 'dark' || value == 'system') ? value : 'light';
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
    try {
      final file = await _settingsFile();
      await file.writeAsString(jsonEncode({'mode': _mode, 'updatedAt': DateTime.now().toIso8601String()}));
    } catch (_) {
      // Appearance persistence is non-critical; the UI has already updated.
    }
  }
}

final appThemeController = AppThemeController();
