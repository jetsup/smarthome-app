import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Shared Bluetooth adapter status (powered on/off, unauthorised, ...).
final FlutterReactiveBle _statusBle = FlutterReactiveBle();

BleStatus get bluetoothStatus => _statusBle.status;
Stream<BleStatus> get bluetoothStatusStream => _statusBle.statusStream;

/// Shows Android's "Allow SmartHomes to turn on Bluetooth?" prompt.
Future<void> requestEnableBluetooth() async {
  if (!Platform.isAndroid) return;
  await const AndroidIntent(action: 'android.bluetooth.adapter.action.REQUEST_ENABLE').launch();
}
