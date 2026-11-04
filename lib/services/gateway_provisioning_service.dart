import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'phone_wifi.dart';

/// A gateway advertising itself for setup over Bluetooth LE.
class FoundGateway {
  final String deviceId; // BLE address
  final String name; // SmartHome-GW-XXXX
  final int rssi;
  const FoundGateway(this.deviceId, this.name, this.rssi);
}

/// What the gateway reports about itself (read characteristic).
class GatewayInfo {
  final String mac;
  final bool linked;
  final bool wifiSaved;
  final bool wifiUp;
  const GatewayInfo(this.mac, this.linked, this.wifiSaved, this.wifiUp);

  factory GatewayInfo.fromJson(Map<String, dynamic> j) => GatewayInfo(
        j['id'] as String? ?? '',
        j['linked'] as bool? ?? false,
        j['wifiSaved'] as bool? ?? false,
        j['wifiUp'] as bool? ?? false,
      );
}

/// Gateway status strings: idle, connecting, wifi_ok (+ IP), linked, fail (+ reason).
enum GatewayStage { idle, connecting, wifiOk, linked, failed }

class GatewayStatus {
  final GatewayStage stage;
  final String detail;
  const GatewayStatus(this.stage, [this.detail = '']);

  static GatewayStatus parse(String s) {
    if (s.startsWith('wifi_ok:')) return GatewayStatus(GatewayStage.wifiOk, s.substring(8));
    if (s.startsWith('fail:')) return GatewayStatus(GatewayStage.failed, s.substring(5));
    if (s == 'connecting') return const GatewayStatus(GatewayStage.connecting);
    if (s == 'linked') return const GatewayStatus(GatewayStage.linked);
    return const GatewayStatus(GatewayStage.idle);
  }
}

/// Finds a screenless gateway over Bluetooth LE and onboards it: Wi-Fi first
/// (tested by the gateway before it is saved), then the hub-issued API key.
///
/// UUIDs must match smarthome-gateway/src/ble_setup.cpp.
class GatewayProvisioningService {
  static final _svc = Uuid.parse('4e5c0010-8d1f-4b6a-9c53-0a5b7a1e0001');
  static final _info = Uuid.parse('4e5c0011-8d1f-4b6a-9c53-0a5b7a1e0001');
  static final _wifi = Uuid.parse('4e5c0012-8d1f-4b6a-9c53-0a5b7a1e0001');
  static final _key = Uuid.parse('4e5c0013-8d1f-4b6a-9c53-0a5b7a1e0001');
  static final _ctl = Uuid.parse('4e5c0014-8d1f-4b6a-9c53-0a5b7a1e0001');
  static final _stat = Uuid.parse('4e5c0015-8d1f-4b6a-9c53-0a5b7a1e0001');

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _conn;
  StreamSubscription<List<int>>? _statSub;
  String? _deviceId;
  final _status = StreamController<GatewayStatus>.broadcast();

  Stream<GatewayStatus> get status => _status.stream;

  Future<bool> ensurePermissions() => ensureBlePermissions();
  Future<List<NearbyWifi>> scanWifi() => scanNearbyWifi();

  /// Gateways currently advertising for setup. Cancel the subscription to stop.
  Stream<FoundGateway> discover() => _ble
      .scanForDevices(withServices: [_svc], scanMode: ScanMode.lowLatency)
      .where((d) => d.name.isNotEmpty)
      .map((d) => FoundGateway(d.id, d.name, d.rssi));

  QualifiedCharacteristic _q(Uuid c) => QualifiedCharacteristic(
      serviceId: _svc, characteristicId: c, deviceId: _deviceId!);

  Future<GatewayInfo> connect(String deviceId) async {
    await disconnect();
    final connected = Completer<void>();
    _conn = _ble
        .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 12))
        .listen((u) {
      if (u.connectionState == DeviceConnectionState.connected && !connected.isCompleted) {
        connected.complete();
      } else if (u.connectionState == DeviceConnectionState.disconnected &&
          !connected.isCompleted) {
        connected.completeError('Bluetooth connection to the gateway failed.');
      }
    }, onError: (Object e) {
      if (!connected.isCompleted) connected.completeError('Bluetooth error: $e');
    });
    await connected.future;
    _deviceId = deviceId;
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: 185);
    } catch (_) {}

    _statSub = _ble.subscribeToCharacteristic(_q(_stat)).listen(
      (d) => _status.add(GatewayStatus.parse(utf8.decode(d, allowMalformed: true))),
      onError: (_) {},
    );
    final raw = await _ble.readCharacteristic(_q(_info));
    return GatewayInfo.fromJson(jsonDecode(utf8.decode(raw)) as Map<String, dynamic>);
  }

  /// Blink the gateway's LED so the user can tell which board this is.
  Future<void> identify() =>
      _ble.writeCharacteristicWithResponse(_q(_ctl), value: utf8.encode('identify'));

  Future<void> sendWifi(String ssid, String password) => _ble.writeCharacteristicWithResponse(
      _q(_wifi), value: utf8.encode(jsonEncode({'s': ssid, 'p': password})));

  /// Hand over the hub-issued API key (and the hub's address). The gateway
  /// saves it, restarts and joins the hub.
  Future<void> sendKey(String apiKey, String hubHost, String name) =>
      _ble.writeCharacteristicWithResponse(_q(_key),
          value: utf8.encode(jsonEncode({'k': apiKey, 'h': hubHost, 'n': name})));

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
