import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'features/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  ErrorWidget.builder = (details) {
    FlutterError.presentError(details);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('این قسمت موقتاً آماده نمایش نیست.'),
            subtitle: const Text('کمی بعد دوباره همین بخش را باز کن یا به صفحه قبل برگرد.'),
          ),
        ),
      ),
    );
  };

  try {
    await NotificationService.init();
  } catch (_) {
    // Notifications are non-critical for first run.
  }
  runApp(const ProviderScope(child: KouroshYarApp()));
}
