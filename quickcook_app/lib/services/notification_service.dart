import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  /// Rate-limited local alert for trending content (once per calendar day).
  static Future<void> maybeShowTrendingReminder(String recipeName) async {
    if (!_ready) await init();

    final p = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    final last = p.getString('notif_trending_day');
    if (last == today) return;
    await p.setString('notif_trending_day', today);

    const android = AndroidNotificationDetails(
      'quickcook_trending',
      'Trending & updates',
      channelDescription: 'Recipe highlights and app updates',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: android, iOS: DarwinNotificationDetails());

    try {
      await _plugin.show(
        1,
        'Trending on QuickCook',
        'See what\'s popular: $recipeName',
        details,
      );
    } catch (e) {
      debugPrint('NotificationService: $e');
    }
  }
}
