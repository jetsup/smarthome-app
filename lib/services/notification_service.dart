import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _initFailed = false;

  // Last online/offline state we already told the user about, per thing
  // (e.g. "gw:abc", "node:abc:3"). Kept across screens and app restarts so
  // the same change is never announced twice.
  final Map<String, bool> _notified = {};
  bool _loadedState = false;

  Future<void> _loadState() async {
    if (_loadedState) return;
    _loadedState = true;
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith('notified:'))) {
        final v = p.getBool(k);
        if (v != null) _notified[k.substring(9)] = v;
      }
    } catch (_) {}
  }

  /// Announce an online/offline change once. Returns without notifying when
  /// [online] equals what the user was last told. A thing first seen online
  /// is just remembered; first seen offline is announced.
  Future<void> reportOnline(
    String key,
    bool online,
    String name, {
    required String kind,
    bool notifyOffline = true,
    bool notifyOnline = true,
  }) async {
    await _loadState();
    final last = _notified[key];
    if (last == online) return;
    _notified[key] = online;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('notified:$key', online);
    } catch (_) {}
    if (last == null && online) return;
    if (!online && notifyOffline) {
      await showOfflineNotification('$kind Offline', '$name is no longer connected.');
    } else if (online && notifyOnline) {
      await showOnlineNotification('$kind Online', '$name is back online.');
    }
  }

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
        title.hashCode ^ body.hashCode,
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
        title.hashCode ^ body.hashCode,
        title,
        body,
        details,
      );
    } catch (_) {}
  }
}
