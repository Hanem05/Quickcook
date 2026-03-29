import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'navigation/app_route_observer.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final themeNotifier = ThemeNotifier();
  await themeNotifier.load();
  runApp(
    // `.value` does not always subscribe to ChangeNotifier updates — `create`
    // ensures Provider listens so theme changes rebuild MaterialApp.
    ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => themeNotifier,
      child: const QuickCookApp(),
    ),
  );
}

class QuickCookApp extends StatefulWidget {
  const QuickCookApp({super.key});

  @override
  State<QuickCookApp> createState() => _QuickCookAppState();
}

class _QuickCookAppState extends State<QuickCookApp> {
  late final AppRouteObserver _routeObserver = AppRouteObserver();

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeNotifier>().mode;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'QuickCook',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      navigatorObservers: [_routeObserver],
      home: const LoginScreen(),
    );
  }
}
