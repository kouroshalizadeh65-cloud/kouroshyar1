import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  String _hashPin(String pin) => 'sha256:${sha256.convert(utf8.encode(pin)).toString()}';

  final pinController = TextEditingController();
  final confirmPinController = TextEditingController();
  final auth = LocalAuthentication();

  bool lockEnabled = false;
  bool biometricEnabled = false;
  bool loaded = false;
  bool biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    pinController.dispose();
    confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    try {
      final available = (await auth.canCheckBiometrics) || (await auth.isDeviceSupported());
      if (mounted) setState(() => biometricsAvailable = available);
    } catch (_) {
      if (mounted) setState(() => biometricsAvailable = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('امنیت برنامه')),
      body: FutureBuilder<List<SecuritySetting>>(
        future: db.select(db.securitySettings).get(),
        builder: (context, snapshot) {
          final current = (snapshot.data ?? const <SecuritySetting>[]).isNotEmpty ? (snapshot.data ?? const <SecuritySetting>[]).first : null;

          if (!loaded && current != null) {
            loaded = true;
            lockEnabled = current.appLockEnabled;
            biometricEnabled = current.biometricEnabled;
            // رمز ذخیره‌شده هرگز دوباره داخل کادر نمایش داده نمی‌شود.
            pinController.clear();
            confirmPinController.clear();
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                value: lockEnabled,
                title: const Text('فعال‌سازی قفل برنامه'),
                subtitle: const Text('ورود به برنامه با رمز یا بیومتریک انجام می‌شود.'),
                onChanged: (v) => setState(() => lockEnabled = v),
              ),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'رمز عددی جدید',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'تکرار رمز عددی',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('برای تغییر رمز، هر دو کادر را پر کن. رمز بعد از ذخیره در کادر باقی نمی‌ماند.'),
              const SizedBox(height: 12),
              SwitchListTile(
                value: biometricEnabled && biometricsAvailable,
                title: const Text('اثر انگشت / بیومتریک'),
                subtitle: Text(biometricsAvailable ? 'از سیستم امنیتی خود گوشی استفاده می‌شود.' : 'گوشی یا تنظیمات فعلی بیومتریک را در دسترس قرار نداده است.'),
                onChanged: biometricsAvailable ? (v) => setState(() => biometricEnabled = v) : null,
              ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.security),
                  title: Text('قفل خودکار'),
                  subtitle: Text('بعد از بازگشت از پس‌زمینه، فقط اگر چند دقیقه گذشته باشد دوباره قفل می‌شود.'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final pin = pinController.text.trim();
                  final confirm = confirmPinController.text.trim();

                  if (lockEnabled) {
                    if ((current == null || (current.pinCode ?? '').isEmpty) && pin.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای فعال کردن قفل، رمز عددی وارد کن.')));
                      return;
                    }
                    if (pin.isNotEmpty && pin.length < 4) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز باید حداقل ۴ رقم باشد.')));
                      return;
                    }
                    if (pin.isNotEmpty && pin != confirm) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز و تکرار رمز یکی نیستند.')));
                      return;
                    }
                  }

                  final existing = await db.select(db.securitySettings).get();
                  final hashedPin = pin.isNotEmpty ? Value<String?>(_hashPin(pin)) : const Value<String?>.absent();

                  if (existing.isEmpty) {
                    await db.into(db.securitySettings).insert(
                          SecuritySettingsCompanion.insert(
                            appLockEnabled: Value(lockEnabled),
                            biometricEnabled: Value(biometricEnabled && biometricsAvailable),
                            pinCode: lockEnabled ? Value<String?>(_hashPin(pin)) : const Value<String?>.absent(),
                          ),
                        );
                  } else {
                    await db.update(db.securitySettings).replace(
                          existing.first.copyWith(
                            appLockEnabled: lockEnabled,
                            biometricEnabled: biometricEnabled && biometricsAvailable,
                            pinCode: hashedPin,
                            updatedAt: DateTime.now(),
                          ),
                        );
                  }

                  pinController.clear();
                  confirmPinController.clear();

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات امنیت ذخیره شد')));
                },
                icon: const Icon(Icons.save),
                label: const Text('ذخیره'),
              ),
            ],
          );
        },
      ),
    );
  }
}
