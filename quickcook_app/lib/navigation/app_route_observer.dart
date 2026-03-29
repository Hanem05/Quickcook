import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../services/performance_reporter.dart';

class AppRouteObserver extends NavigatorObserver {
  final Map<Route<dynamic>, DateTime> _pushTimes = {};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _pushTimes[route] = DateTime.now();
    final name = route.settings.name ?? route.runtimeType.toString();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final start = _pushTimes.remove(route);
      if (start == null) return;
      final ms = DateTime.now().difference(start).inMilliseconds;
      PerformanceReporter.reportScreen(name, ms);
    });
  }
}
