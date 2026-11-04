import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

class NearbyWifi {
  final String ssid;
  final int level; // dBm
  final bool secured;
  const NearbyWifi(this.ssid, this.level, this.secured);
}

/// Ask for the runtime permissions Bluetooth LE and Wi-Fi scanning need.
Future<bool> ensureBlePermissions() async {
  final res = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
  return res.values.every((s) => s.isGranted || s.isLimited);
}

/// Phone-side Wi-Fi scan (does not touch the phone's current connection).
Future<List<NearbyWifi>> scanNearbyWifi() async {
  final can = await WiFiScan.instance.canStartScan(askPermissions: true);
  if (can == CanStartScan.yes) {
    await WiFiScan.instance.startScan();
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  final canGet = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
  if (canGet != CanGetScannedResults.yes) return [];
  final raw = await WiFiScan.instance.getScannedResults();
  final best = <String, NearbyWifi>{};
  for (final ap in raw) {
    if (ap.ssid.isEmpty) continue;
    final secured = ap.capabilities.contains('WPA') ||
        ap.capabilities.contains('WEP') ||
        ap.capabilities.contains('SAE');
    final prev = best[ap.ssid];
    if (prev == null || ap.level > prev.level) {
      best[ap.ssid] = NearbyWifi(ap.ssid, ap.level, secured);
    }
  }
  final list = best.values.toList()..sort((a, b) => b.level.compareTo(a.level));
  // Hide SmartHome devices' own hotspots from the list.
  return list.where((w) => !w.ssid.startsWith('SmartHome-')).toList();
}
