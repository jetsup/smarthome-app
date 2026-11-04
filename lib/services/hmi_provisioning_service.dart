import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'phone_wifi.dart';

export 'phone_wifi.dart' show NearbyWifi;

/// What the HMI shows in its QR code: `SHPROV1;n=<ble name>;k=<code>`.
class HmiQr {
  final String bleName;
  final String code;
  const HmiQr(this.bleName, this.code);

  static HmiQr? parse(String raw) {
    if (!raw.startsWith('SHPROV1;')) return null;
    String? n, k;
    for (final part in raw.split(';').skip(1)) {
      final i = part.indexOf('=');
      if (i < 0) continue;
      final key = part.substring(0, i);
      final val = part.substring(i + 1);
      if (key == 'n') n = val;
      if (key == 'k') k = val;
    }
    if (n == null || n.isEmpty || k == null || k.isEmpty) return null;
    return HmiQr(n, k);
  }
}

/// Status the HMI reports after it was handed Wi-Fi credentials.
enum HmiWifiState { idle, connecting, connected, failed }

class HmiWifiStatus {
  final HmiWifiState state;
  final String detail; // IP address when connected, reason when failed
  const HmiWifiStatus(this.state, [this.detail = '']);

  static HmiWifiStatus parse(String s) {
    if (s.startsWith('ok:')) return HmiWifiStatus(HmiWifiState.connected, s.substring(3));
    if (s.startsWith('fail:')) return HmiWifiStatus(HmiWifiState.failed, s.substring(5));
    if (s == 'connecting') return const HmiWifiStatus(HmiWifiState.connecting);
    return const HmiWifiStatus(HmiWifiState.idle);
  }
}

/// Talks to an HMI over Bluetooth LE to hand it Wi-Fi credentials.
///
/// The phone never leaves its own Wi-Fi network: the HMI itself tests the
/// credentials and only saves them if it manages to connect, reporting the
/// result back over a notify characteristic.
///
/// UUIDs must match smarthome-hmi/src/wifi_provisioner.cpp.
class HmiProvisioningService {
  static final _svc = Uuid.parse('4e5c0001-8d1f-4b6a-9c53-0a5b7a1e0001');
  static final _cred = Uuid.parse('4e5c0002-8d1f-4b6a-9c53-0a5b7a1e0001');
  static final _stat = Uuid.parse('4e5c0003-8d1f-4b6a-9c53-0a5b7a1e0001');

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _conn;
  StreamSubscription<List<int>>? _statSub;
  String? _deviceId;
  final _status = StreamController<HmiWifiStatus>.broadcast();

  Stream<HmiWifiStatus> get status => _status.stream;

  Future<bool> ensurePermissions() => ensureBlePermissions();

  Future<List<NearbyWifi>> scanWifi() => scanNearbyWifi();

  /// Find the HMI by the name in its QR code and connect to it.
  Future<void> connect(String bleName) async {
    await disconnect();
    final found = Completer<DiscoveredDevice>();
    final scan = _ble
        .scanForDevices(withServices: [_svc], scanMode: ScanMode.lowLatency)
        .listen((d) {
      if (d.name == bleName && !found.isCompleted) found.complete(d);
    });
    final DiscoveredDevice dev;
    try {
      dev = await found.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw 'Could not find "$bleName". Is the HMI on the "Scan with the app" screen and close by?';
    } finally {
      await scan.cancel();
    }

    final connected = Completer<void>();
    _conn = _ble
        .connectToDevice(
          id: dev.id,
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen((u) {
      if (u.connectionState == DeviceConnectionState.connected && !connected.isCompleted) {
        connected.complete();
      } else if (u.connectionState == DeviceConnectionState.disconnected &&
          !connected.isCompleted) {
        connected.completeError('Bluetooth connection to the HMI failed.');
      }
    }, onError: (Object e) {
      if (!connected.isCompleted) connected.completeError('Bluetooth error: $e');
    });
    await connected.future;
    _deviceId = dev.id;
    try {
      await _ble.requestMtu(deviceId: dev.id, mtu: 185);
    } catch (_) {/* default MTU still works for short credentials */}

    final q = QualifiedCharacteristic(
        serviceId: _svc, characteristicId: _stat, deviceId: dev.id);
    _statSub = _ble.subscribeToCharacteristic(q).listen(
      (data) => _status.add(HmiWifiStatus.parse(utf8.decode(data, allowMalformed: true))),
      onError: (_) {},
    );
  }

  /// Send the chosen network. The result arrives on [status].
  Future<void> sendCredentials({
    required String ssid,
    required String password,
    required String code,
  }) async {
    final id = _deviceId;
    if (id == null) throw 'Not connected to the HMI.';
    final q = QualifiedCharacteristic(
        serviceId: _svc, characteristicId: _cred, deviceId: id);
    final payload = utf8.encode(jsonEncode({'s': ssid, 'p': password, 'k': code}));
    await _ble.writeCharacteristicWithResponse(q, value: payload);
  }

  Future<void> disconnect() async {
    await _statSub?.cancel();
    await _conn?.cancel();
    _statSub = null;
    _conn = null;
    _deviceId = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _status.close();
  }
}
