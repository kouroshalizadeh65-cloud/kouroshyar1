import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'features/notifications/notification_service.dart';
import 'core/theme/app_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // جزئیات فنی در لاگ ثبت می‌شود، اما رابط کاربر به‌جای فضای خالی
  // یک پیام امن و قابل‌پیگیری نشان می‌دهد.
  ErrorWidget.builder = (details) {
    FlutterError.presentError(details);
    return const Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('نمایش این بخش با خطا روبه‌رو شد. برنامه را دوباره باز کنید.'),
          ),
        ),
      ),
    );
  };

  await appThemeController.load();

  try {
    await NotificationService.init();
  } catch (_) {
    // Notifications are non-critical for first run.
  }
  runApp(const ProviderScope(child: KouroshYarApp()));
}
