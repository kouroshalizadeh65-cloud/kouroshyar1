import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/home/home_screen.dart';
import 'features/cases/cases_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/more/more_screen.dart';
import 'features/quick_action/quick_action_sheet.dart';
import 'features/lock/app_lock_screen.dart';

class KouroshYarApp extends StatelessWidget {
  const KouroshYarApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'sans',
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          margin: const EdgeInsets.symmetric(vertical: 6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0B1220),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFF243044), thickness: 1),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF111827),
          indicatorColor: Color(0xFF3730A3),
        ),
      ),
      home: const AppLockScreen(child: MainShell()),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  final pages = const [
    HomeScreen(),
    CasesScreen(),
    CalendarScreen(),
    MoreScreen(),
  ];

  Future<bool> _handleBack() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return false;
    }

    if (index != 0) {
      setState(() => index = 0);
      return false;
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
    return shouldExit == true;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: WillPopScope(
        onWillPop: _handleBack,
        child: Scaffold(
          body: pages[index],
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => QuickActionSheet.show(context),
            icon: const Icon(Icons.add),
            label: const Text('ثبت سریع'),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'خانه'),
              NavigationDestination(icon: Icon(Icons.gavel_outlined), selectedIcon: Icon(Icons.gavel), label: 'پرونده‌ها'),
              NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'تقویم'),
              NavigationDestination(icon: Icon(Icons.more_horiz), label: 'بیشتر'),
            ],
          ),
        ),
      ),
    );
  }
}
