import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class AppLockScreen extends ConsumerStatefulWidget {
  final Widget child;

  const AppLockScreen({super.key, required this.child});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> with WidgetsBindingObserver {
  final pinController = TextEditingController();
  final auth = LocalAuthentication();
  bool unlocked = false;
  String error = '';
  DateTime? _backgroundedAt;
  static const Duration _lockAfterBackground = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive can happen when the speech recognizer, permission dialog, or biometric
    // prompt opens. It must not lock the app on every microphone tap.
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    }

    if (state == AppLifecycleState.resumed && unlocked && _backgroundedAt != null) {
      final awayFor = DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (awayFor >= _lockAfterBackground) {
        setState(() {
          unlocked = false;
          pinController.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return FutureBuilder<List<SecuritySetting>>(
      future: db.select(db.securitySettings).get(),
      builder: (context, snapshot) {
        final settings = snapshot.data ?? const <SecuritySetting>[];
        final s = settings.isNotEmpty ? settings.first : null;

        if (s == null || !s.appLockEnabled || unlocked) {
          return widget.child;
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('ورود به کوروش‌یار')),
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.lock, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'برنامه قفل است',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'رمز برنامه',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _checkPin(s.pinCode ?? ''),
                ),
                const SizedBox(height: 12),
                if (error.isNotEmpty)
                  Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _checkPin(s.pinCode ?? ''),
                  icon: const Icon(Icons.login),
                  label: const Text('ورود با رمز'),
                ),
                if (s.biometricEnabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _authenticateWithBiometrics,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('ورود با اثر انگشت / بیومتریک'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matchesPin(String typed, String expected) {
    if (expected.isEmpty) return false;
    if (expected.startsWith('sha256:')) {
      final hashed = 'sha256:${sha256.convert(utf8.encode(typed)).toString()}';
      return hashed == expected;
    }
    return typed == expected;
  }

  void _checkPin(String expected) {
    if (_matchesPin(pinController.text.trim(), expected)) {
      pinController.clear();
      setState(() {
        unlocked = true;
        error = '';
      });
    } else {
      setState(() => error = 'رمز اشتباه است.');
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final ok = await auth.authenticate(
        localizedReason: 'برای ورود به کوروش‌یار احراز هویت کنید.',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok) {
        setState(() {
          unlocked = true;
          error = '';
        });
      }
    } catch (_) {
      setState(() => error = 'احراز هویت بیومتریک در دسترس نیست.');
    }
  }
}
