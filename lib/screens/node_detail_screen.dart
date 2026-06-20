import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/node.dart';
import '../providers/providers.dart';

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
      );
    }
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
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8b949e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(node.displayName,
            style: const TextStyle(color: Color(0xFFc9d1d9))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            color: const Color(0xFF161b22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFF30363d)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: node.isOnline ? const Color(0xFF3fb950) : const Color(0xFF484f58),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(node.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                              color: node.isOnline ? const Color(0xFF3fb950) : const Color(0xFFf85149),
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(_inferTypeLabel(node), style: const TextStyle(color: Color(0xFF8b949e), fontSize: 13)),
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

          // Per-capability controls
          if (node.capabilitiesConfig.isNotEmpty) ...[
            Card(
              color: const Color(0xFF161b22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFF30363d)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Capabilities', style: TextStyle(color: Color(0xFFc9d1d9), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
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
              color: const Color(0xFF161b22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFF30363d)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Relay Control', style: TextStyle(color: Color(0xFFc9d1d9), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _sending ? null : () => _sendCommand(1),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF238636),
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
                              backgroundColor: const Color(0xFFda3633),
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
                      style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                      style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _sending ? null : () => _sendCommand((cap.value ?? 0) > 0 ? 0 : 1, pin: cap.pin),
              style: ElevatedButton.styleFrom(
                backgroundColor: (cap.value ?? 0) > 0 ? const Color(0xFF238636) : const Color(0xFF21262d),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: Text((cap.value ?? 0) > 0 ? 'ON' : 'OFF',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
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
                          style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                          style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
                    ],
                  ),
                ),
                Text('${sliderVal.toInt()}',
                    style: const TextStyle(color: Color(0xFFc9d1d9), fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: const Color(0xFF58a6ff),
                inactiveTrackColor: const Color(0xFF30363d),
                thumbColor: const Color(0xFF58a6ff),
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
                      style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                      style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
                ],
              ),
            ),
            Text('${node.value ?? '—'}',
                style: const TextStyle(color: Color(0xFF8b949e), fontSize: 14)),
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
                      style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                      style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
                ],
              ),
            ),
            Text((node.value ?? 0) > 0 ? 'HIGH' : 'LOW',
                style: const TextStyle(color: Color(0xFF8b949e), fontSize: 14)),
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
                    style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 14, fontWeight: FontWeight.w600)),
                Text('${_capTypeLabel(cap.type)} (pin ${cap.pin})',
                    style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
              ],
            ),
          ),
          Text(cap.value?.toString() ?? '—',
              style: const TextStyle(color: Color(0xFF8b949e), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0d1117),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363d)),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
