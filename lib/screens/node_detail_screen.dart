import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/node.dart';
import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';
import '../widgets/capability_editor.dart';
import '../widgets/module_controls.dart';
import '../widgets/node_display_card.dart';
import 'node_settings_screen.dart';

class NodeDetailScreen extends ConsumerStatefulWidget {
  final SmartNode node;
  final String gatewayId;
  const NodeDetailScreen({
    super.key,
    required this.node,
    required this.gatewayId,
  });

  @override
  ConsumerState<NodeDetailScreen> createState() => _NodeDetailScreenState();
}

class _NodeDetailScreenState extends ConsumerState<NodeDetailScreen> {
  bool _sending = false;
  Timer? _pollTimer;
  int? _dragIndex;
  double _dragValue = 0;
  SmartNode? _detailNode;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchDetail(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    final api = ref.read(apiServiceProvider);
    try {
      final response = await api.get('/api/nodes/${widget.node.nodeId}');
      if (mounted) {
        setState(() {
          _detailNode = SmartNode.fromJson(
            response.data as Map<String, dynamic>,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _sendCommand(int value, {int? pin}) async {
    setState(() => _sending = true);

    // Optimistic update: immediately reflect the change locally
    _applyOptimistic(value, pin: pin);

    final nid = widget.node.nodeId;
    if (nid.isNotEmpty) {
      await ref
          .read(nodesProvider(widget.gatewayId).notifier)
          .sendCommand(nid, value, pin: pin);
      // Fetch actual state from hub to confirm
      _fetchDetail();
    }
    if (mounted) setState(() => _sending = false);
  }

  void _applyOptimistic(int value, {int? pin}) {
    final node = _detailNode ?? widget.node;
    final caps = node.capabilitiesConfig;
    if (caps.isEmpty) return;
    if (pin != null) {
      // Find the capability with this pin and update its value
      final updated = caps.map((c) {
        if (c.pin == pin) {
          return CapabilityConfig(
            type: c.type,
            pin: c.pin,
            extra: c.extra,
            label: c.label,
            value: value,
          );
        }
        return c;
      }).toList();
      _detailNode = SmartNode(
        nodeId: node.nodeId,
        deviceId: node.deviceId,
        gatewayId: node.gatewayId,
        apiKey: node.apiKey,
        deviceType: node.deviceType,
        capabilities: node.capabilities,
        value: value,
        isOnline: node.isOnline,
        lastSeen: node.lastSeen,
        name: node.name,
        capabilitiesConfig: updated,
        hmiId: node.hmiId,
        readings: node.readings,
        effects: node.effects,
      );
    }
  }

  Future<void> _editPins(SmartNode node) async {
    List<Map<String, dynamic>>? result;
    try {
      result = await showCapabilityDialog(
        context,
        ref,
        title: 'Edit modules',
        confirmText: 'Save & apply',
        initial: node.capabilitiesConfig,
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load the module list. Try again.'),
          ),
        );
      return;
    }
    if (result == null || !mounted) return;
    String msg;
    try {
      final r = await ref
          .read(apiServiceProvider)
          .put(
            '/api/nodes/${node.nodeId}/capabilities',
            data: {'capabilitiesConfig': result},
          );
      final d = r.data is Map ? r.data as Map : {};
      msg = d['status'] == 'updated_but_offline'
          ? (d['message'] as String? ??
                'Saved. The node gets the new pins when the gateway is back online.')
          : 'Pins updated. The node restarts with the new assignment.';
      await _fetchDetail();
    } catch (e) {
      msg = apiError(e, 'Could not change the pins');
    }
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _capTypeLabel(String type) {
    const labels = {
      'analogInput': 'Analog In',
      'analogOutput': 'Analog Out',
      'digitalInput': 'Digital In',
      'digitalOutput': 'Digital Out',
      'relay': 'Relay',
      'irTx': 'IR TX',
      'irRx': 'IR RX',
      'neopixel': 'NeoPixel LEDs',
      'buzzer': 'Buzzer',
      'dht': 'DHT sensor',
      'ld2410': 'LD2410 radar',
      'ds3231': 'DS3231 clock',
      'i2c': 'I2C',
      'uart': 'UART',
    };
    return labels[type] ?? type;
  }

  String _inferTypeLabel(SmartNode node) {
    if (node.deviceType != 0) {
      const labels = {
        1: 'Analog Sensor',
        2: 'Digital Sensor',
        3: 'Relay',
        4: 'IR Transceiver',
        5: 'Hybrid',
      };
      return labels[node.deviceType] ?? 'Unknown';
    }
    if (node.capabilitiesConfig.isEmpty) return 'Unknown';
    final types = node.capabilitiesConfig.map((c) => c.type).toSet();
    if (types.contains('analogInput')) return 'Analog Sensor';
    if (types.contains('digitalInput')) return 'Digital Sensor';
    if (types.contains('relay')) return 'Relay';
    if (types.contains('analogOutput')) return 'Analog Output';
    if (types.contains('digitalOutput')) return 'Digital Output';
    if (types.contains('irTx') || types.contains('irRx'))
      return 'IR Transceiver';
    return 'Hybrid';
  }

  @override
  Widget build(BuildContext context) {
    final node = _detailNode ?? widget.node;

    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.card,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.c.muted),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(node.displayName, style: TextStyle(color: context.c.text)),
        actions: [
          IconButton(
            tooltip: 'Node settings',
            icon: Icon(Icons.settings, color: context.c.muted),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NodeSettingsScreen(node: node)));
              if (mounted) _fetchDetail();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            color: context.c.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: context.c.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: node.isOnline
                              ? context.c.ok
                              : context.c.subtle,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        node.isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: node.isOnline ? context.c.ok : context.c.bad,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _inferTypeLabel(node),
                        style: TextStyle(color: context.c.muted, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _statBox('Type', _inferTypeLabel(node)),
                      const SizedBox(width: 12),
                      _statBox('Device ID', '${node.deviceId}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Which display shows this node (a node is on one display only)
          NodeDisplayCard(
            nodeId: node.nodeId,
            gatewayId: node.gatewayId,
            initialHmiId: node.hmiId,
          ),

          // Per-capability controls
          ...[
            Card(
              color: context.c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: context.c.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Capabilities',
                            style: TextStyle(
                              color: context.c.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _editPins(node),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit modules'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (node.capabilitiesConfig.isEmpty)
                      Text(
                        'No modules are set for this node yet. Tap “Edit modules” to say what is wired to it (for example a potentiometer on GPIO 34, an LED on GPIO 25, or a NeoPixel ring).',
                        style: TextStyle(
                          color: context.c.muted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ...node.capabilitiesConfig.asMap().entries.map((entry) {
                      final i = entry.key;
                      final cap = entry.value;
                      return _capabilityTile(context, node, i, cap);
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          ModuleControls(node: node, onChanged: _fetchDetail),

          // Fallback for old relay nodes without capabilities
          if (node.capabilitiesConfig.isEmpty && node.deviceType == 3) ...[
            Card(
              color: context.c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: context.c.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relay Control',
                      style: TextStyle(
                        color: context.c.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _sending ? null : () => _sendCommand(1),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.c.okStrong,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Turn ON',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _sending ? null : () => _sendCommand(0),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.c.badStrong,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Turn OFF',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _capabilityTile(
    BuildContext context,
    SmartNode node,
    int index,
    CapabilityConfig cap,
  ) {
    if (cap.type == 'digitalOutput' || cap.type == 'relay') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                    style: TextStyle(
                      color: context.c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                    style: TextStyle(color: context.c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _sending
                  ? null
                  : () => _sendCommand(
                      (cap.value ?? 0) > 0 ? 0 : 1,
                      pin: cap.pin,
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: (cap.value ?? 0) > 0
                    ? context.c.okStrong
                    : context.c.divider,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                (cap.value ?? 0) > 0 ? 'ON' : 'OFF',
                style: TextStyle(
                  color: (cap.value ?? 0) > 0 ? Colors.white : context.c.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (cap.type == 'analogOutput') {
      final sliderVal = _dragIndex == index
          ? _dragValue
          : (cap.value?.toDouble() ?? 0);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cap.label.isNotEmpty
                            ? cap.label
                            : _capTypeLabel(cap.type),
                        style: TextStyle(
                          color: context.c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                        style: TextStyle(color: context.c.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${sliderVal.toInt()}',
                  style: TextStyle(
                    color: context.c.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: context.c.accent,
                inactiveTrackColor: context.c.border,
                thumbColor: context.c.accent,
                overlayColor: const Color(0x2058a6ff),
              ),
              child: Slider(
                min: 0,
                max: 255,
                divisions: 255,
                value: sliderVal,
                onChanged: (v) => setState(() {
                  _dragIndex = index;
                  _dragValue = v;
                }),
                onChangeEnd: (v) {
                  setState(() => _dragIndex = null);
                  _sendCommand(v.toInt(), pin: cap.pin);
                },
              ),
            ),
          ],
        ),
      );
    }

    // Input capability types — show telemetry value like Vue does
    if (cap.type == 'analogInput') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                    style: TextStyle(
                      color: context.c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                    style: TextStyle(color: context.c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '${cap.value ?? node.value ?? '—'}',
              style: TextStyle(color: context.c.muted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (cap.type == 'digitalInput') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                    style: TextStyle(
                      color: context.c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                    style: TextStyle(color: context.c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              ((cap.value ?? node.value) ?? 0) > 0 ? 'HIGH' : 'LOW',
              style: TextStyle(color: context.c.muted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Other capability types (display only)
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                  style: TextStyle(
                    color: context.c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_capTypeLabel(cap.type)}${cap.pin > 0 ? ' (pin ${cap.pin})' : ''}${cap.type == 'neopixel' ? ' · ${cap.count} LEDs${cap.ring ? ' · ring' : ''}' : ''}',
                  style: TextStyle(color: context.c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            cap.display.isNotEmpty
                ? cap.display
                : (cap.value?.toString() ?? '—'),
            style: TextStyle(
              color: cap.display.isNotEmpty
                  ? context.c.accent
                  : context.c.muted,
              fontSize: 14,
              fontWeight: cap.display.isNotEmpty
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.c.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.c.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: context.c.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label, style: TextStyle(color: context.c.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
