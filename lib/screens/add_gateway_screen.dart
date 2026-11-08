import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' show BleStatus;
import '../services/bluetooth_helpers.dart';
import '../services/gateway_provisioning_service.dart';
import '../widgets/bluetooth_off_card.dart';
import '../widgets/wifi_picker.dart';
import '../services/phone_wifi.dart';
import '../theme/app_colors.dart';

/// Adds a gateway without joining its hotspot: the gateway advertises over
/// Bluetooth LE, the phone gives it Wi-Fi (tested by the gateway) and then the
/// hub-issued API key. The phone stays on its own network throughout.
class AddGatewayScreen extends ConsumerStatefulWidget {
  const AddGatewayScreen({super.key});

  @override
  ConsumerState<AddGatewayScreen> createState() => _AddGatewayScreenState();
}

enum _Step { find, connecting, wifi, name, linking, done }

class _AddGatewayScreenState extends ConsumerState<AddGatewayScreen> {
  final _svc = GatewayProvisioningService();
  final _ssidCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _nameCtl = TextEditingController(text: 'My Gateway');

  _Step _step = _Step.find;
  final Map<String, FoundGateway> _found = {};
  StreamSubscription<FoundGateway>? _scanSub;
  StreamSubscription<GatewayStatus>? _statusSub;
  StreamSubscription<BleStatus>? _btSub;
  bool _btOff = false;
  FoundGateway? _selected;
  List<NearbyWifi> _networks = [];
  bool _scanningWifi = false;
  bool _scanningBle = false;
  bool _showPass = false;
  bool _wifiBusy = false;
  String? _error;
  String _busyMsg = '';
  String _target = 'new'; // 'new', or the id of an existing gateway to re-link

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gatewaysProvider.notifier).fetchAll();
      _watchBluetooth();
    });
  }

  // Start searching as soon as Bluetooth is on; tell the user when it is not.
  void _watchBluetooth() {
    void apply(BleStatus st) {
      if (!mounted) return;
      final off = st == BleStatus.poweredOff;
      final wasOff = _btOff;
      setState(() {
        _btOff = off;
        if (off || st == BleStatus.ready) _error = null;
      });
      if (st == BleStatus.ready &&
          wasOff &&
          _step == _Step.find &&
          !_scanningBle) {
        _startFind();
      }
    }

    _btOff = bluetoothStatus == BleStatus.poweredOff;
    _btSub = bluetoothStatusStream.listen(apply);
    if (!_btOff) _startFind();
  }

  @override
  void dispose() {
    _btSub?.cancel();
    _scanSub?.cancel();
    _statusSub?.cancel();
    _svc.dispose();
    _ssidCtl.dispose();
    _passCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  // ── Step 1: find gateways ──────────────────────────────────────────────────
  Future<void> _startFind() async {
    await _scanSub?.cancel();
    setState(() {
      _found.clear();
      _error = null;
      _scanningBle = true;
    });
    if (!await _svc.ensurePermissions()) {
      setState(() {
        _scanningBle = false;
        _error =
            'Bluetooth and location permissions are needed to find gateways.';
      });
      return;
    }
    _scanSub = _svc.discover().listen(
      (g) {
        if (mounted) setState(() => _found[g.deviceId] = g);
      },
      onError: (Object e) {
        if (!mounted) return;
        // "Bluetooth disabled" is already explained by the card above.
        final off = '$e'.toLowerCase().contains('disabled');
        setState(() {
          _scanningBle = false;
          if (off) {
            _btOff = true;
          } else {
            _error = 'Bluetooth scan failed: $e';
          }
        });
      },
    );
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (mounted && _scanningBle) {
        _scanSub?.cancel();
        setState(() => _scanningBle = false);
      }
    });
  }

  // ── Step 2: connect ────────────────────────────────────────────────────────
  Future<void> _select(FoundGateway g) async {
    await _scanSub?.cancel();
    setState(() {
      _selected = g;
      _scanningBle = false;
      _step = _Step.connecting;
      _busyMsg = 'Connecting to ${g.name}…';
      _error = null;
    });
    try {
      final info = await _svc.connect(g.deviceId);
      _statusSub?.cancel();
      _statusSub = _svc.status.listen(_onStatus);
      if (info.linked) {
        throw '${g.name} is already linked to a hub. Hold its reset button for 5 seconds to clear it, then try again.';
      }
      if (info.wifiUp || info.wifiSaved) {
        setState(() => _step = _Step.name); // Wi-Fi already done earlier
      } else {
        setState(() => _step = _Step.wifi);
        _refreshWifi();
      }
    } catch (e) {
      await _svc.disconnect();
      setState(() {
        _step = _Step.find;
        _error = '$e';
      });
      _startFind();
    }
  }

  // ── Step 3: Wi-Fi ──────────────────────────────────────────────────────────
  Future<void> _refreshWifi() async {
    setState(() => _scanningWifi = true);
    try {
      final nets = await _svc.scanWifi();
      if (mounted) setState(() => _networks = nets);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanningWifi = false);
    }
  }

  Future<void> _sendWifi() async {
    final ssid = _ssidCtl.text.trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'Choose or type a network name.');
      return;
    }
    setState(() {
      _wifiBusy = true;
      _error = null;
      _busyMsg = 'Sending to the gateway…';
    });
    try {
      await _svc.sendWifi(ssid, _passCtl.text);
    } catch (e) {
      setState(() {
        _wifiBusy = false;
        _error = 'Could not send to the gateway: $e';
      });
    }
  }

  void _onStatus(GatewayStatus s) {
    if (!mounted) return;
    switch (s.stage) {
      case GatewayStage.connecting:
        setState(() => _busyMsg = 'The gateway is testing "${_ssidCtl.text}"…');
      case GatewayStage.wifiOk:
        if (_step == _Step.wifi) {
          setState(() {
            _wifiBusy = false;
            _step = _Step.name;
          });
        }
      case GatewayStage.failed:
        setState(() {
          _wifiBusy = false;
          if (_step == _Step.linking) _step = _Step.name;
          _error = 'The gateway reported: ${s.detail}. Nothing was saved.';
        });
      case GatewayStage.linked:
      case GatewayStage.idle:
        break;
    }
  }

  // ── Step 4/5: link to the hub ──────────────────────────────────────────────
  Future<void> _link() async {
    final name = _nameCtl.text.trim();
    if (_target == 'new' && name.isEmpty) {
      setState(() => _error = 'Give the gateway a name.');
      return;
    }
    setState(() {
      _step = _Step.linking;
      _busyMsg = 'Registering with your hub…';
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      String gwId;
      String key;
      String gwName = name;
      if (_target != 'new') {
        gwId = _target;
        final existing = ref.read(gatewaysProvider).where((g) => g.id == gwId);
        if (existing.isNotEmpty) gwName = existing.first.name;
        final r = await api.get('/api/gateways/$gwId/api-key');
        key = (r.data as Map)['apiKey'] as String;
      } else {
        final r = await api.post('/api/gateways', data: {'name': name});
        gwId = (r.data as Map)['id'] as String;
        key = (r.data as Map)['apiKey'] as String;
      }
      final hubHost = Uri.parse(api.baseUrl ?? '').host;
      setState(() => _busyMsg = 'Giving the gateway its key…');
      await _svc.sendKey(key, hubHost, gwName);

      setState(
        () => _busyMsg = 'The gateway is restarting and joining the hub…',
      );
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 3));
        await ref.read(gatewaysProvider.notifier).fetchAll();
        final gw = ref.read(gatewaysProvider).where((g) => g.id == gwId);
        if (gw.isNotEmpty && gw.first.online) {
          if (mounted) setState(() => _step = _Step.done);
          return;
        }
      }
      // Key was delivered; it may just need longer (e.g. slow Wi-Fi).
      if (mounted) {
        setState(() {
          _step = _Step.done;
          _error =
              'The gateway has its key but has not reported in yet. It should appear online shortly.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _Step.name;
          _error = 'Linking failed: $e';
        });
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.card,
        iconTheme: IconThemeData(color: context.c.text),
        title: Text(
          'Add gateway',
          style: TextStyle(color: context.c.text, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.find:
        return _findBody();
      case _Step.connecting:
        return _busy(_busyMsg);
      case _Step.wifi:
        return _wifiBody();
      case _Step.name:
        return _nameBody();
      case _Step.linking:
        return _busy(_busyMsg);
      case _Step.done:
        return _doneBody();
    }
  }

  Widget _busy(String msg) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: context.c.accent2),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.text),
          ),
        ),
      ],
    ),
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

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.c.muted),
    filled: true,
    fillColor: context.c.card,
    suffixIcon: suffix,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.c.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.c.accent2),
    ),
  );

  Widget _findBody() {
    final list = _found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_btOff) const BluetoothOffCard(what: 'gateways'),
        _errorBox(),
        Row(
          children: [
            Expanded(
              child: Text(
                'Power on the gateway. A new or reset gateway shows up here automatically — no hotspot needed.',
                style: TextStyle(color: context.c.muted),
              ),
            ),
            IconButton(
              onPressed: _scanningBle ? null : _startFind,
              icon: _scanningBle
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.c.accent2,
                      ),
                    )
                  : Icon(Icons.refresh, color: context.c.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _btOff
                    ? ''
                    : _scanningBle
                    ? 'Looking for gateways…'
                    : 'No gateways found nearby.',
                style: TextStyle(color: context.c.muted),
              ),
            ),
          ),
        for (final g in list)
          Card(
            color: context.c.card,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: context.c.border),
            ),
            child: ListTile(
              leading: Icon(Icons.router, color: context.c.accent2),
              title: Text(
                g.name,
                style: TextStyle(
                  color: context.c.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Signal ${g.rssi} dBm',
                style: TextStyle(color: context.c.muted, fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right, color: context.c.muted),
              onTap: () => _select(g),
            ),
          ),
      ],
    );
  }

  Widget _wifiBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _errorBox(),
        Row(
          children: [
            Expanded(
              child: Text(
                'Connected to ${_selected?.name}. Choose the Wi-Fi it should join.',
                style: TextStyle(color: context.c.muted),
              ),
            ),
            IconButton(
              tooltip: 'Blink the gateway LED',
              onPressed: () => _svc.identify(),
              icon: Icon(Icons.lightbulb_outline, color: context.c.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        WifiPicker(
          networks: _networks,
          scanning: _scanningWifi,
          onRefresh: _refreshWifi,
          ssidCtl: _ssidCtl,
          passCtl: _passCtl,
          showPass: _showPass,
          onTogglePass: () => setState(() => _showPass = !_showPass),
          onSelectionChanged: () => setState(() {}),
          onSubmit: _wifiBusy ? null : _sendWifi,
          submitLabel: _wifiBusy ? _busyMsg : 'Send to gateway',
          helper:
              'The gateway tests the network and only saves it if it connects.',
        ),
      ],
    );
  }

  Widget _nameBody() {
    final gateways = ref.watch(gatewaysProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _errorBox(),
        Text(
          'Wi-Fi is set. Now link this gateway to your account:',
          style: TextStyle(color: context.c.muted),
        ),
        const SizedBox(height: 12),
        RadioGroup<String>(
          groupValue: _target,
          onChanged: (v) => setState(() => _target = v ?? 'new'),
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'new',
                activeColor: context.c.accent2,
                title: Text(
                  'New gateway',
                  style: TextStyle(color: context.c.text),
                ),
              ),
              if (_target == 'new')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _nameCtl,
                    style: TextStyle(color: context.c.text),
                    decoration: _dec('Gateway name'),
                  ),
                ),
              for (final g in gateways)
                RadioListTile<String>(
                  value: g.id,
                  activeColor: context.c.accent2,
                  title: Text(
                    'Re-link “${g.name}”',
                    style: TextStyle(color: context.c.text),
                  ),
                  subtitle: Text(
                    g.online ? 'Currently online' : 'Offline',
                    style: TextStyle(color: context.c.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _link, child: const Text('Link gateway')),
      ],
    );
  }

  Widget _doneBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _error == null ? Icons.check_circle : Icons.hourglass_top,
            color: _error == null ? context.c.ok : context.c.accent2,
            size: 72,
          ),
          const SizedBox(height: 16),
          Text(
            _error == null ? 'Gateway added and online' : 'Gateway linked',
            style: TextStyle(
              color: context.c.text,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.c.muted),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}
