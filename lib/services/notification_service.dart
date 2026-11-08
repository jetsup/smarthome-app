import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _initFailed = false;

  Future<void> init() async {
    if (_initialized || _initFailed) return;
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      _initFailed = true;
    }
  }

  Future<bool> requestPermission() async {
    await init();
    if (_initFailed) return false;
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin == null) return false;
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  Future<void> showOfflineNotification(String title, String body) async {
    await init();
    if (_initFailed) return;
    const androidDetails = AndroidNotificationDetails(
      'offline_channel',
      'Offline Alerts',
      channelDescription: 'Notifications when gateways or nodes go offline',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (_) {}
  }

  /// A sign-in is waiting for the number shown here (two-step verification).
  Future<void> showSignInRequest(
    String code,
    String where, {
    bool enabling = false,
  }) async {
    await init();
    if (_initFailed) return;
    final spaced = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    final androidDetails = AndroidNotificationDetails(
      'mfa_channel',
      'Sign-in approvals',
      channelDescription:
          'The number to enter when you sign in to SmartHome with two-step verification',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      ticker: 'SmartHome sign-in request',
    );
    try {
      await _plugin.show(
        7000,
        enabling
            ? 'Turn on two-step verification'
            : 'Sign-in request from $where',
        enabling
            ? 'Enter $spaced on the website to continue. Do not share this number.'
            : 'Open SmartHomes and type the number shown on the sign-in screen to approve. Not you? Tap Deny.',
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelSignInRequest() async {
    try {
      await _plugin.cancel(7000);
    } catch (_) {}
  }

  Future<void> showOnlineNotification(String title, String body) async {
    await init();
    if (_initFailed) return;
    const androidDetails = AndroidNotificationDetails(
      'online_channel',
      'Connection Restored',
      channelDescription:
          'Notifications when gateways or nodes come back online',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (_) {}
  }
}
