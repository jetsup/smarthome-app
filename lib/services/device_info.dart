import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What this phone is, so the account's device lists can say
/// "INFINIX X6855 · Android 14" instead of "Android phone".
class DeviceDetails {
  final String manufacturer;
  final String model;
  final String os;
  const DeviceDetails(this.manufacturer, this.model, this.os);

  String get name => [manufacturer, model].where((s) => s.isNotEmpty).join(' ');
  String get label => '$name · SmartHomes app';
}

String? _key;
DeviceDetails? _details;

/// Stable random id for this installation (links a session to this phone).
Future<String> deviceKey() async {
  if (_key != null) return _key!;
  final prefs = await SharedPreferences.getInstance();
  var k = prefs.getString('mfa_device_key');
  if (k == null || k.length < 16) {
    final r = Random.secure();
    k = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    await prefs.setString('mfa_device_key', k);
  }
  return _key = k;
}

Future<DeviceDetails> deviceDetails() async {
  if (_details != null) return _details!;
  try {
    if (Platform.isAndroid) {
      final a = await DeviceInfoPlugin().androidInfo;
      String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
      return _details = DeviceDetails(cap(a.manufacturer), a.model, 'Android ${a.version.release}');
    }
  } catch (_) {}
  return _details = DeviceDetails('', 'Phone', Platform.operatingSystem);
}
