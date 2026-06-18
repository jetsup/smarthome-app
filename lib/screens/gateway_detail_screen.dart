import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/node.dart';
import 'node_detail_screen.dart';

class GatewayDetailScreen extends ConsumerStatefulWidget {
  final String gatewayId;
  const GatewayDetailScreen({super.key, required this.gatewayId});

  @override
  ConsumerState<GatewayDetailScreen> createState() => _GatewayDetailScreenState();
}

class _GatewayDetailScreenState extends ConsumerState<GatewayDetailScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  Future<void> _load() async {
    await ref.read(gatewaysProvider.notifier).fetchOne(widget.gatewayId);
    await ref.read(nodesProvider(widget.gatewayId).notifier).fetchNodes();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gateways = ref.watch(gatewaysProvider);
    final gw = gateways.where((g) => g.id == widget.gatewayId).firstOrNull;
    final nodes = ref.watch(nodesProvider(widget.gatewayId));

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8b949e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(gw?.name ?? 'Gateway', style: const TextStyle(color: Color(0xFFc9d1d9))),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusDot(gw?.online ?? false),
                        const SizedBox(width: 8),
                        Text(gw?.online == true ? 'Online' : 'Offline',
                            style: TextStyle(
                                color: gw?.online == true ? const Color(0xFF3fb950) : const Color(0xFFf85149),
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('ID: ${gw?.id ?? ''}', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statBox('Nodes', '${nodes.length}'),
                        const SizedBox(width: 12),
                        _statBox('Online', '${nodes.where((n) => n.isOnline).length}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Nodes', style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (nodes.isEmpty)
              const Card(
                color: Color(0xFF161b22),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No nodes linked', style: TextStyle(color: Color(0xFF8b949e)))),
                ),
              )
            else
              ...nodes.map((n) => _NodeCard(n, widget.gatewayId)),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(bool online) {
    return Container(width: 10, height: 10,
      decoration: BoxDecoration(
        color: online ? const Color(0xFF3fb950) : const Color(0xFF484f58),
        shape: BoxShape.circle,
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
            Text(value, style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  final SmartNode node;
  final String gatewayId;
  const _NodeCard(this.node, this.gatewayId);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF161b22),
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF30363d)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(node.nodeId.isNotEmpty ? node.nodeId : 'Device ${node.deviceId}',
            style: const TextStyle(color: Color(0xFFc9d1d9), fontSize: 14)),
        subtitle: Row(
          children: [
            _badge(node.isOnline ? 'Online' : 'Offline', node.isOnline),
            const SizedBox(width: 8),
            Text(node.typeLabel, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
            if (node.value != null) ...[
              const SizedBox(width: 8),
              Text('Value: ${node.value}', style: const TextStyle(color: Color(0xFF58a6ff), fontSize: 11)),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF484f58)),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NodeDetailScreen(node: node, gatewayId: gatewayId)),
          );
        },
      ),
    );
  }

  Widget _badge(String label, bool online) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: online
            ? const Color(0xFF238636).withValues(alpha: 0.2)
            : const Color(0xFF484f58).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10,
              color: online ? const Color(0xFF3fb950) : const Color(0xFF8b949e),
              fontWeight: FontWeight.w600)),
    );
  }
}
