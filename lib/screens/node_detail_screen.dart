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
  final _valueCtrl = TextEditingController();
  bool _sending = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _valueCtrl.text = '0';
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.read(nodesProvider(widget.gatewayId).notifier).fetchNodes();
    });
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  SmartNode? get _node {
    final nodes = ref.read(nodesProvider(widget.gatewayId));
    return nodes.where((n) => n.deviceId == widget.node.deviceId).firstOrNull;
  }

  Future<void> _sendCommand(int value) async {
    setState(() => _sending = true);
    final nid = widget.node.nodeId;
    if (nid.isNotEmpty) {
      final ok = await ref.read(nodesProvider(widget.gatewayId).notifier).sendCommand(nid, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Command sent' : 'Failed to send'),
            backgroundColor: ok ? const Color(0xFF238636) : const Color(0xFFf85149),
          ),
        );
      }
    }
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final node = _node ?? widget.node;

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8b949e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(node.nodeId.isNotEmpty ? node.nodeId : 'Device ${node.deviceId}',
            style: const TextStyle(color: Color(0xFFc9d1d9))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                      Text(node.typeLabel, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _statBox('Value', '${node.value ?? '—'}'),
                      const SizedBox(width: 12),
                      _statBox('Type', node.typeLabel),
                      const SizedBox(width: 12),
                      _statBox('Device ID', '${node.deviceId}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
                  const Text('Control', style: TextStyle(color: Color(0xFFc9d1d9), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _valueCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Color(0xFFc9d1d9)),
                    decoration: InputDecoration(
                      labelText: 'Value (0–65535)',
                      labelStyle: const TextStyle(color: Color(0xFF8b949e)),
                      filled: true,
                      fillColor: const Color(0xFF0d1117),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363d))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363d))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF58a6ff))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _sending ? null : () => _sendCommand(int.tryParse(_valueCtrl.text) ?? 0),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238636),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Send Command', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (node.deviceType == 3) ...[
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
                ],
              ),
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
