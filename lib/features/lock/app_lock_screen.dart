import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/pin_security.dart';
import '../../core/security/screen_capture_service.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import 'app_lock_controller.dart';

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
  bool checkingPin = false;
  String error = '';
  int failedAttempts = 0;
  DateTime? blockedUntil;
  Timer? _countdownTimer;
  DateTime? _backgroundedAt;
  static const Duration _lockAfterBackground = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appLockController.addListener(_handleManualLockRequest);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    appLockController.removeListener(_handleManualLockRequest);
    pinController.dispose();
    super.dispose();
  }

  void _handleManualLockRequest() {
    if (!appLockController.manualLockRequested) return;
    appLockController.consumeManualLockRequest();
    _backgroundedAt = null;
    _closeTransientUi();
    if (!mounted) return;
    setState(() {
      unlocked = false;
      error = '';
      failedAttempts = 0;
      blockedUntil = null;
      pinController.clear();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed && unlocked && _backgroundedAt != null) {
      final awayFor = DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (awayFor >= _lockAfterBackground) {
        _closeTransientUi();
        setState(() {
          unlocked = false;
          pinController.clear();
        });
      }
    }
  }

  void _closeTransientUi() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      final navigator = Navigator.of(context, rootNavigator: true);
      while (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<SecuritySetting>>(
      stream: db.select(db.securitySettings).watch(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _secureErrorScaffold();
        }
        if (!snapshot.hasData) {
          return _secureLoadingScaffold();
        }
        final settings = snapshot.data ?? const <SecuritySetting>[];
        final s = settings.isNotEmpty ? settings.first : null;
        unawaited(ScreenCaptureService.setAllowed(s?.screenCaptureAllowed ?? false));
        if (s == null || !s.appLockEnabled || unlocked) return widget.child;

        final remaining = _remainingBlockSeconds();
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('ورود به کوروش‌یار')),
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.lock, size: 64),
                const SizedBox(height: 24),
                const Text('برنامه قفل است', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  enabled: remaining == 0 && !checkingPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 12,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'رمز برنامه', border: OutlineInputBorder()),
                  onSubmitted: (_) => _checkPin(db, s),
                ),
                const SizedBox(height: 12),
                if (error.isNotEmpty) Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                if (remaining > 0)
                  Text('به‌دلیل چند تلاش ناموفق، ورود تا $remaining ثانیه موقتاً قفل است.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: remaining == 0 && !checkingPin ? () => _checkPin(db, s) : null,
                  icon: checkingPin ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                  label: const Text('ورود با رمز'),
                ),
                if (s.biometricEnabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: remaining == 0 ? _authenticateWithBiometrics : null,
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

  Widget _secureLoadingScaffold() => const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );

  Widget _secureErrorScaffold() => const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('وضعیت امنیتی برنامه خوانده نشد. برای حفاظت از اطلاعات، دسترسی بسته ماند. برنامه را دوباره باز کنید.', textAlign: TextAlign.center)))),
      );

  int _remainingBlockSeconds() {
    final until = blockedUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inSeconds + 1;
    return remaining > 0 ? remaining : 0;
  }

  Future<void> _checkPin(AppDatabase db, SecuritySetting setting) async {
    if (checkingPin || _remainingBlockSeconds() > 0) return;
    final typed = pinController.text.trim();
    setState(() => checkingPin = true);
    final ok = verifyPinSecure(typed, setting.pinCode ?? '');
    if (!mounted) return;
    if (ok) {
      if (pinHashNeedsUpgrade(setting.pinCode ?? '')) {
        try {
          await db.update(db.securitySettings).replace(
                setting.copyWith(
                  pinCode: Value<String?>(hashPinSecure(typed)),
                  updatedAt: DateTime.now(),
                ),
              );
        } catch (_) {
          // ورود معتبر مسدود نمی‌شود؛ ارتقای هش در ورود بعدی دوباره تلاش خواهد شد.
        }
      }
      if (!mounted) return;
      pinController.clear();
      setState(() {
        unlocked = true;
        checkingPin = false;
        failedAttempts = 0;
        blockedUntil = null;
        error = '';
      });
      return;
    }

    failedAttempts++;
    pinController.clear();
    if (failedAttempts >= 5) {
      final exponent = (failedAttempts - 5).clamp(0, 4).toInt();
      final seconds = 30 * (1 << exponent);
      blockedUntil = DateTime.now().add(Duration(seconds: seconds));
      _startCountdown();
      error = 'رمز اشتباه است. ورود موقتاً محدود شد.';
    } else {
      error = 'رمز اشتباه است. ${5 - failedAttempts} تلاش تا محدودیت موقت باقی مانده است.';
    }
    setState(() => checkingPin = false);
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _remainingBlockSeconds() <= 0) {
        timer.cancel();
        if (mounted) setState(() => blockedUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final ok = await auth.authenticate(
        localizedReason: 'برای ورود به کوروش‌یار احراز هویت کنید.',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok && mounted) {
        setState(() {
          unlocked = true;
          failedAttempts = 0;
          blockedUntil = null;
          error = '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'احراز هویت بیومتریک در دسترس نیست.');
    }
  }
}
