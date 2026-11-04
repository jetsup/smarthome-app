import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/node.dart';
import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';
import '../widgets/node_display_card.dart';

class NodeDetailScreen extends ConsumerStatefulWidget {
  final SmartNode node;
  final String gatewayId;
  const NodeDetailScreen({super.key, required this.node, required this.gatewayId});

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
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchDetail());
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
          _detailNode = SmartNode.fromJson(response.data as Map<String, dynamic>);
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
      await ref.read(nodesProvider(widget.gatewayId).notifier).sendCommand(nid, value, pin: pin);
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
      );
    }
  }

  Future<void> _editPins(SmartNode node) async {
    final result = await showDialog<List<CapabilityConfig>>(
      context: context,
      builder: (_) => _EditPinsDialog(initial: node.capabilitiesConfig),
    );
    if (result == null || !mounted) return;
    String msg;
    try {
      final r = await ref.read(apiServiceProvider).put('/api/nodes/${node.nodeId}/capabilities',
          data: {'capabilitiesConfig': result.map((c) => c.toJson()).toList()});
      final d = r.data is Map ? r.data as Map : {};
      msg = d['status'] == 'updated_but_offline'
          ? (d['message'] as String? ?? 'Saved. The node gets the new pins when the gateway is back online.')
          : 'Pins updated. The node restarts with the new assignment.';
      await _fetchDetail();
    } catch (e) {
      msg = apiError(e, 'Could not change the pins');
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    if (types.contains('irTx') || types.contains('irRx')) return 'IR Transceiver';
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
        title: Text(node.displayName,
            style: TextStyle(color: context.c.text)),
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
                      Container(width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: node.isOnline ? context.c.ok : context.c.subtle,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(node.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                              color: node.isOnline ? context.c.ok : context.c.bad,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(_inferTypeLabel(node), style: TextStyle(color: context.c.muted, fontSize: 13)),
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
          NodeDisplayCard(nodeId: node.nodeId, gatewayId: node.gatewayId, initialHmiId: node.hmiId),

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
                    Row(children: [
                      Expanded(child: Text('Capabilities', style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600))),
                      TextButton.icon(
                        onPressed: () => _editPins(node),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit pins'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    if (node.capabilitiesConfig.isEmpty)
                      Text('No pins are set for this node yet. Tap “Edit pins” to say what is wired to it (for example a potentiometer on GPIO 34 and an LED on GPIO 25).',
                          style: TextStyle(color: context.c.muted, fontSize: 13, height: 1.4)),
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
                    Text('Relay Control', style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _sending ? null : () => _sendCommand(1),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.c.okStrong,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Turn ON', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _sending ? null : () => _sendCommand(0),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.c.badStrong,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Turn OFF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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

  Widget _capabilityTile(BuildContext context, SmartNode node, int index, CapabilityConfig cap) {
    if (cap.type == 'digitalOutput' || cap.type == 'relay') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                      style: TextStyle(color: context.c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                      style: TextStyle(color: context.c.muted, fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _sending ? null : () => _sendCommand((cap.value ?? 0) > 0 ? 0 : 1, pin: cap.pin),
              style: ElevatedButton.styleFrom(
                backgroundColor: (cap.value ?? 0) > 0 ? context.c.okStrong : context.c.divider,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: Text((cap.value ?? 0) > 0 ? 'ON' : 'OFF',
                  style: TextStyle(color: (cap.value ?? 0) > 0 ? Colors.white : context.c.text, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    if (cap.type == 'analogOutput') {
      final sliderVal = _dragIndex == index ? _dragValue : (cap.value?.toDouble() ?? 0);
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
                      Text(cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                          style: TextStyle(color: context.c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                          style: TextStyle(color: context.c.muted, fontSize: 12)),
                    ],
                  ),
                ),
                Text('${sliderVal.toInt()}',
                    style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600, fontSize: 14)),
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
                onChanged: (v) => setState(() { _dragIndex = index; _dragValue = v; }),
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
                  Text(cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                      style: TextStyle(color: context.c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                      style: TextStyle(color: context.c.muted, fontSize: 12)),
                ],
              ),
            ),
            Text('${node.value ?? '—'}',
                style: TextStyle(color: context.c.muted, fontSize: 14)),
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
                  Text(cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                      style: TextStyle(color: context.c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                      style: TextStyle(color: context.c.muted, fontSize: 12)),
                ],
              ),
            ),
            Text((node.value ?? 0) > 0 ? 'HIGH' : 'LOW',
                style: TextStyle(color: context.c.muted, fontSize: 14)),
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
                Text(cap.label.isNotEmpty ? cap.label : _capTypeLabel(cap.type),
                    style: TextStyle(color: context.c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                    style: TextStyle(color: context.c.muted, fontSize: 12)),
              ],
            ),
          ),
          Text(cap.value?.toString() ?? '—',
              style: TextStyle(color: context.c.muted, fontSize: 14)),
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
            Text(value, style: TextStyle(color: context.c.text, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: context.c.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

const _pinTypes = <String, String>{
  'digitalOutput': 'Digital out',
  'analogOutput': 'Analog out (PWM)',
  'analogInput': 'Analog in',
  'digitalInput': 'Digital in',
  'relay': 'Relay',
  'i2c': 'I2C',
  'uart': 'UART',
};

class _PinRow {
  String type;
  final TextEditingController pin;
  final TextEditingController label;
  _PinRow(CapabilityConfig c)
      : type = _pinTypes.containsKey(c.type) ? c.type : 'digitalOutput',
        pin = TextEditingController(text: '${(c.type == 'i2c' || c.type == 'uart') ? c.extra : c.pin}'),
        label = TextEditingController(text: c.label);
}

/// Change which GPIO each capability uses, add or remove capabilities.
class _EditPinsDialog extends StatefulWidget {
  final List<CapabilityConfig> initial;
  const _EditPinsDialog({required this.initial});

  @override
  State<_EditPinsDialog> createState() => _EditPinsDialogState();
}

class _EditPinsDialogState extends State<_EditPinsDialog> {
  late final List<_PinRow> _rows = widget.initial.map(_PinRow.new).toList();
  String? _error;

  void _save() {
    final out = <CapabilityConfig>[];
    final used = <int>{};
    for (final r in _rows) {
      final n = int.tryParse(r.pin.text.trim());
      final io = r.type != 'i2c' && r.type != 'uart';
      if (n == null || n < 0 || n > (io ? 39 : 127)) {
        setState(() => _error = 'Enter a valid number for every pin.');
        return;
      }
      if (io && !used.add(n)) {
        setState(() => _error = 'GPIO $n is used twice.');
        return;
      }
      out.add(CapabilityConfig(type: r.type, pin: io ? n : 0, extra: io ? 0 : n, label: r.label.text.trim()));
    }
    if (out.isEmpty) {
      setState(() => _error = 'Add at least one pin.');
      return;
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: Text('Edit pins', style: TextStyle(color: c.text, fontSize: 17)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Change which GPIO each part is wired to. The node restarts with the new assignment.',
                style: TextStyle(color: c.muted, fontSize: 12)),
            const SizedBox(height: 12),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _rows[i].type,
                      dropdownColor: c.card,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      style: TextStyle(color: c.text, fontSize: 13),
                      items: [for (final e in _pinTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _rows[i].type = v ?? _rows[i].type),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _rows[i].pin,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: c.text, fontSize: 13),
                      decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: (_rows[i].type == 'i2c' || _rows[i].type == 'uart') ? 'Addr/No.' : 'GPIO'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _rows[i].label,
                      maxLength: 10,
                      style: TextStyle(color: c.text, fontSize: 13),
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Label', counterText: ''),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: Icon(Icons.close, color: c.bad, size: 18),
                    onPressed: _rows.length > 1 ? () => setState(() => _rows.removeAt(i)) : null,
                  ),
                ]),
              ),
            if (_rows.length < 8)
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_PinRow(CapabilityConfig(type: 'digitalOutput', pin: 0)))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add another'),
              ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: c.bad, fontSize: 12))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save & apply')),
      ],
    );
  }
}
