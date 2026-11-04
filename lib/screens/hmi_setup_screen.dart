import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' show BleStatus;
import '../services/bluetooth_helpers.dart';
import '../services/hmi_provisioning_service.dart';
import '../widgets/bluetooth_off_card.dart';
import '../widgets/wifi_picker.dart';
import '../theme/app_colors.dart';

/// Walks the user through giving an HMI display its Wi-Fi credentials:
/// scan the QR on the HMI -> pick a network (scanned by the phone) -> the HMI
/// tests it and reports back. The phone stays on its own network throughout.
class HmiSetupScreen extends StatefulWidget {
  const HmiSetupScreen({super.key});

  @override
  State<HmiSetupScreen> createState() => _HmiSetupScreenState();
}

enum _Step { scan, connecting, pick, sending, done }

class _HmiSetupScreenState extends State<HmiSetupScreen> {

  final _svc = HmiProvisioningService();
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _ssidCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _codeCtl = TextEditingController();

  _Step _step = _Step.scan;
  HmiQr? _hmi;
  List<NearbyWifi> _networks = [];
  bool _scanningWifi = false;
  bool _manualEntry = false;
  bool _showPass = false;
  String? _error;
  String _sendingMsg = '';
  String _ip = '';
  StreamSubscription<HmiWifiStatus>? _statusSub;
  StreamSubscription<BleStatus>? _btSub;
  bool _btOff = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _btOff = bluetoothStatus == BleStatus.poweredOff;
    _btSub = bluetoothStatusStream.listen((st) {
      if (mounted) setState(() => _btOff = st == BleStatus.poweredOff);
    });
  }

  @override
  void dispose() {
    _btSub?.cancel();
    _statusSub?.cancel();
    _svc.dispose();
    _scanner.dispose();
    _ssidCtl.dispose();
    _passCtl.dispose();
    _nameCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  void _onQr(BarcodeCapture cap) {
    if (_handled) return;
    for (final b in cap.barcodes) {
      final qr = HmiQr.parse(b.rawValue ?? '');
      if (qr != null) {
        _handled = true;
        _begin(qr);
        return;
      }
    }
  }

  Future<void> _begin(HmiQr qr) async {
    setState(() {
      _hmi = qr;
      _step = _Step.connecting;
      _error = null;
    });
    try {
      if (!await _svc.ensurePermissions()) {
        throw 'Bluetooth and location permissions are needed to find the HMI and nearby Wi-Fi.';
      }
      await _svc.connect(qr.bleName);
      _statusSub?.cancel();
      _statusSub = _svc.status.listen(_onStatus);
      setState(() => _step = _Step.pick);
      _refreshWifi();
    } catch (e) {
      _handled = false;
      setState(() {
        _step = _Step.scan;
        _error = '$e';
      });
    }
  }

  Future<void> _refreshWifi() async {
    setState(() => _scanningWifi = true);
    try {
      final nets = await _svc.scanWifi();
      if (mounted) setState(() => _networks = nets);
    } catch (_) {
      // leave the list as is; the user can still type an SSID
    } finally {
      if (mounted) setState(() => _scanningWifi = false);
    }
  }

  void _onStatus(HmiWifiStatus s) {
    if (!mounted) return;
    switch (s.state) {
      case HmiWifiState.connecting:
        setState(() => _sendingMsg = 'The HMI is testing "${_ssidCtl.text}"…');
      case HmiWifiState.connected:
        setState(() {
          _ip = s.detail;
          _step = _Step.done;
        });
      case HmiWifiState.failed:
        setState(() {
          _step = _Step.pick;
          _error = 'The HMI could not connect: ${s.detail}. Nothing was saved — check the password and try again.';
        });
      case HmiWifiState.idle:
        break;
    }
  }

  Future<void> _send() async {
    final ssid = _ssidCtl.text.trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'Choose or type a network name.');
      return;
    }
    setState(() {
      _step = _Step.sending;
      _sendingMsg = 'Sending to the HMI…';
      _error = null;
    });
    try {
      await _svc.sendCredentials(ssid: ssid, password: _passCtl.text, code: _hmi!.code);
    } catch (e) {
      setState(() {
        _step = _Step.pick;
        _error = 'Could not send to the HMI: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.card,
        iconTheme: IconThemeData(color: context.c.text),
        title: Text('Set up HMI Wi-Fi',
            style: TextStyle(color: context.c.text, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.scan:
        return _scanBody();
      case _Step.connecting:
        return _busy('Connecting to ${_hmi?.bleName}…');
      case _Step.pick:
        return _pickBody();
      case _Step.sending:
        return _busy(_sendingMsg);
      case _Step.done:
        return _doneBody();
    }
  }

  Widget _busy(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: context.c.accent2),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: context.c.text)),
          ),
        ]),
      );

  Widget _errorBox() => _error == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.c.bad.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_error!, style: TextStyle(color: context.c.bad)),
        );

  Widget _scanBody() {
    if (_manualEntry) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (_btOff) const BluetoothOffCard(what: 'displays'),
        _errorBox(),
        Text('Type what the HMI shows under the QR code.',
            style: TextStyle(color: context.c.muted)),
        const SizedBox(height: 12),
        _field(_nameCtl, 'HMI name (SmartHome-HMI-XXXX)'),
        _field(_codeCtl, '6-digit code', keyboard: TextInputType.number),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () {
            final n = _nameCtl.text.trim(), k = _codeCtl.text.trim();
            if (n.isEmpty || k.isEmpty) {
              setState(() => _error = 'Enter both the name and the code.');
              return;
            }
            _begin(HmiQr(n, k));
          },
          child: const Text('Connect'),
        ),
        TextButton(
          onPressed: () => setState(() => _manualEntry = false),
          child: const Text('Scan the QR code instead'),
        ),
      ]);
    }
    return Column(children: [
      Expanded(
        child: Stack(children: [
          MobileScanner(controller: _scanner, onDetect: _onQr),
          Positioned(
            left: 16, right: 16, top: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'On the HMI choose “Scan with the SmartHome app”, then point the camera at the QR code.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          if (_btOff) const BluetoothOffCard(what: 'displays'),
          _errorBox(),
          TextButton(
            onPressed: () => setState(() {
              _manualEntry = true;
              _error = null;
            }),
            child: const Text('Camera not working? Enter the code manually'),
          ),
        ]),
      ),
    ]);
  }

  Widget _field(TextEditingController c, String hint,
      {bool obscure = false, TextInputType? keyboard, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        autocorrect: false,
        enableSuggestions: false,
        style: TextStyle(color: context.c.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: context.c.muted),
          filled: true,
          fillColor: context.c.card,
          suffixIcon: suffix,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.c.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.c.accent2)),
        ),
      ),
    );
  }

  Widget _pickBody() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _errorBox(),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('Connected to ${_hmi?.bleName}. Choose the Wi-Fi it should join.',
            style: TextStyle(color: context.c.muted)),
      ),
      WifiPicker(
        networks: _networks,
        scanning: _scanningWifi,
        onRefresh: _refreshWifi,
        ssidCtl: _ssidCtl,
        passCtl: _passCtl,
        showPass: _showPass,
        onTogglePass: () => setState(() => _showPass = !_showPass),
        onSelectionChanged: () => setState(() {}),
        onSubmit: _send,
        submitLabel: 'Send to HMI',
        helper: 'The HMI tests the network first and only saves it if it connects, so a typo will not lock it out.',
      ),
    ]);
  }

  Widget _doneBody() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, color: context.c.ok, size: 72),
            const SizedBox(height: 16),
            Text('HMI connected to Wi-Fi',
                style: TextStyle(color: context.c.text, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Network “${_ssidCtl.text}” · $_ip',
                style: TextStyle(color: context.c.muted)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ]),
        ),
      );
}
