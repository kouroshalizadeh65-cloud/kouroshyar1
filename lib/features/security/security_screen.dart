import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/pin_security.dart';
import '../../core/widgets/global_settings_button.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final currentPinController = TextEditingController();
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
    currentPinController.dispose();
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

  bool _matchesPin(String typed, String expected) => verifyPinSecure(typed, expected);

  bool _securitySensitiveChange(SecuritySetting? current, String newPin) {
    final currentPin = current?.pinCode ?? '';
    if (currentPin.isEmpty) return false;
    if (newPin.isNotEmpty) return true;
    if (current != null && current.appLockEnabled != lockEnabled) return true;
    if (current != null && current.biometricEnabled != (biometricEnabled && biometricsAvailable)) return true;
    return false;
  }

  Future<bool> _confirmFullWipe(BuildContext context, SecuritySetting? current) async {
    final verifyController = TextEditingController();
    final phraseController = TextEditingController();
    final hasPin = (current?.pinCode ?? '').trim().isNotEmpty;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('تأیید پاکسازی کامل'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('این عملیات همه پرونده‌ها، مدارک، پشتیبان‌های داخلی و تنظیمات را حذف می‌کند و قابل بازگشت نیست.'),
                  const SizedBox(height: 12),
                  if (hasPin)
                    TextField(
                      controller: verifyController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 12,
                      decoration: const InputDecoration(labelText: 'رمز فعلی', border: OutlineInputBorder()),
                    )
                  else
                    TextField(
                      controller: phraseController,
                      decoration: const InputDecoration(labelText: 'عبارت «حذف کامل» را وارد کنید', border: OutlineInputBorder()),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لغو')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () {
                    final authorized = hasPin
                        ? verifyPinSecure(verifyController.text.trim(), current?.pinCode ?? '')
                        : phraseController.text.trim() == 'حذف کامل';
                    if (!authorized) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('تأیید امنیتی صحیح نیست.')));
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('حذف کامل'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      verifyController.dispose();
      phraseController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('امنیت و حریم خصوصی برنامه'), actions: const [GlobalSettingsButton()]),
      body: StreamBuilder<List<SecuritySetting>>(
        stream: db.select(db.securitySettings).watch(),
        builder: (context, snapshot) {
          final current = (snapshot.data ?? const <SecuritySetting>[]).isNotEmpty ? (snapshot.data ?? const <SecuritySetting>[]).first : null;
          final hasCurrentPin = (current?.pinCode ?? '').trim().isNotEmpty;

          if (!loaded && current != null) {
            loaded = true;
            lockEnabled = current.appLockEnabled;
            biometricEnabled = current.biometricEnabled;
            currentPinController.clear();
            pinController.clear();
            confirmPinController.clear();
          }

          final bottom = MediaQuery.of(context).padding.bottom;
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 24),
            children: [
              SwitchListTile(
                value: lockEnabled,
                title: const Text('فعال‌سازی قفل برنامه'),
                subtitle: const Text('ورود به برنامه با رمز یا بیومتریک انجام می‌شود.'),
                onChanged: (v) => setState(() => lockEnabled = v),
              ),
              if (hasCurrentPin) ...[
                TextField(
                  controller: currentPinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: 'رمز فعلی',
                    helperText: 'برای تغییر رمز، غیرفعال‌کردن قفل یا تغییر تنظیمات امنیتی لازم است.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: hasCurrentPin ? 'رمز عددی جدید' : 'رمز عددی',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: 'تکرار رمز عددی جدید',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasCurrentPin
                    ? 'برای تغییر رمز، اول رمز فعلی را وارد کن. اگر نمی‌خواهی رمز را تغییر بدهی، کادرهای رمز جدید را خالی بگذار.'
                    : 'برای فعال کردن قفل، رمز عددی حداقل ۴ رقم وارد کن.',
              ),
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
                  title: Text('قفل خودکار و خروج امن'),
                  subtitle: Text('با زدن خروج از داخل برنامه، ورود بعدی فوراً رمز می‌خواهد. در پس‌زمینه هم بعد از چند دقیقه قفل فعال می‌شود.'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'پاکسازی کامل اطلاعات',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('همه اطلاعات محلی کوروش‌یار حذف می‌شود. این گزینه فقط برای شروع کامل از صفر است و قابل بازگشت نیست.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                        onPressed: () async {
                          final confirmed = await _confirmFullWipe(context, current);
                          if (confirmed != true) return;
                          await db.wipeAllLocalData();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اطلاعات محلی برنامه پاک شد.')));
                        },
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('پاکسازی کامل اطلاعات برنامه'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final currentPin = currentPinController.text.trim();
                  final pin = pinController.text.trim();
                  final confirm = confirmPinController.text.trim();
                  final savedPin = current?.pinCode ?? '';
                  final sensitiveChange = _securitySensitiveChange(current, pin);

                  if (sensitiveChange && !_matchesPin(currentPin, savedPin)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز فعلی اشتباه است.')));
                    return;
                  }

                  if (lockEnabled && (current == null || savedPin.isEmpty) && pin.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای فعال کردن قفل، رمز عددی وارد کن.')));
                    return;
                  }
                  if (pin.isNotEmpty && (pin.length < 4 || !RegExp(r'^\d+$').hasMatch(pin))) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز باید عددی و حداقل ۴ رقم باشد.')));
                    return;
                  }
                  if (pin.isNotEmpty && pin != confirm) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز و تکرار رمز یکی نیستند.')));
                    return;
                  }

                  if (!lockEnabled && hasCurrentPin && !_matchesPin(currentPin, savedPin)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای غیرفعال کردن قفل، رمز فعلی را وارد کن.')));
                    return;
                  }

                  final existing = await db.select(db.securitySettings).get();
                  final hashedPin = pin.isNotEmpty ? Value<String?>(hashPinSecure(pin)) : const Value<String?>.absent();

                  if (existing.isEmpty) {
                    await db.into(db.securitySettings).insert(
                          SecuritySettingsCompanion.insert(
                            appLockEnabled: Value(lockEnabled),
                            biometricEnabled: Value(biometricEnabled && biometricsAvailable),
                            pinCode: lockEnabled ? Value<String?>(hashPinSecure(pin)) : const Value<String?>.absent(),
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

                  currentPinController.clear();
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
