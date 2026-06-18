import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> showOfflineNotification(String title, String body) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'offline_channel',
      'Offline Alerts',
      channelDescription: 'Notifications when gateways or nodes go offline',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  Future<void> showOnlineNotification(String title, String body) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'online_channel',
      'Connection Restored',
      channelDescription: 'Notifications when gateways or nodes come back online',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: 'ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
