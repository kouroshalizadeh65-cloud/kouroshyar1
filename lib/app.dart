import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/home/home_screen.dart';
import 'features/cases/cases_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/personal/personal_screen.dart';
import 'features/quick_action/quick_action_sheet.dart';
import 'features/lock/app_lock_screen.dart';
import 'features/lock/app_lock_controller.dart';
import 'features/settings/settings_screen.dart';
import 'core/theme/app_theme_controller.dart';
import 'database/database_provider.dart';
import 'features/notifications/notification_service.dart';

class KouroshYarApp extends StatelessWidget {
  const KouroshYarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'کوروش‌یار',
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: appThemeController.themeMode,
          home: const AppLockScreen(child: MainShell()),
          routes: {
            '/settings': (_) => const SettingsScreen(),
          },
        );
      },
    );
  }
}

ThemeData _baseTheme({required Brightness brightness, required Color seed}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'sans',
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F7FB),
    cardTheme: CardThemeData(
      elevation: isDark ? 0 : 1,
      color: isDark ? const Color(0xFF111827) : Colors.white,
      shadowColor: Colors.black.withOpacity(isDark ? 0 : 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F7FB),
      foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
      elevation: 0,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dividerTheme: DividerThemeData(color: isDark ? const Color(0xFF243044) : const Color(0xFFE2E8F0), thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      indicatorColor: isDark ? const Color(0xFF3730A3) : const Color(0xFFE0E7FF),
    ),
  );
}

ThemeData _buildLightTheme() => _baseTheme(brightness: Brightness.light, seed: const Color(0xFF1E3A8A));

ThemeData _buildDarkTheme() => _baseTheme(brightness: Brightness.dark, seed: Colors.indigo);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WidgetsBindingObserver {
  int index = 0;
  final CalendarBackController _calendarBackController = CalendarBackController();

  late final List<Widget> pages = [
    const HomeScreen(),
    const CasesScreen(),
    CalendarScreen(backController: _calendarBackController),
    const PersonalScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    Future.microtask(() async {
      try {
        await NotificationService.init();
        await ref.read(databaseProvider).syncNotifications();
      } catch (_) {
        // Returning to the app must never fail because a vendor blocks alarms.
      }
    });
  }

  Future<void> _handleBack() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    // در تقویم، ابتدا history داخلی تقویم مصرف می‌شود.
    // اگر چیزی برای برگشت نبود، کاربر به خانه برمی‌گردد.
    if (index == 2 && _calendarBackController.handleBack()) {
      return;
    }

    // دکمه برگشت در همه تب‌های اصلی نهایتاً به خانه می‌رسد؛
    // فقط در خانه پیام خروج نمایش داده می‌شود.
    if (index != 0) {
      setState(() => index = 0);
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('خروج از کوروش‌یار'),
        content: const Text('آیا می‌خواهید از کوروش‌یار خارج شوید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
        ],
      ),
    );
    if (shouldExit == true && context.mounted) {
      // خروج اختیاری کاربر باید فوراً قفل برنامه را فعال کند؛
      // حتی اگر Android برنامه را در حافظه فعال نگه دارد.
      appLockController.lockNow();
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            top: false,
            bottom: false,
            child: pages[index],
          ),
          floatingActionButton: FloatingActionButton.small(
            tooltip: 'ثبت',
            onPressed: () => QuickActionSheet.show(context),
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'خانه'),
              NavigationDestination(icon: Icon(Icons.gavel_outlined), selectedIcon: Icon(Icons.gavel), label: 'پرونده‌ها'),
              NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'تقویم'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'امور شخصی'),
            ],
          ),
        ),
      ),
    );
  }
}
