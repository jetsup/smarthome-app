import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';

/// Nodes left behind by a deleted gateway. They were not reset; each can be
/// given to any gateway, which sends the node its saved setup again.
class UnassignedNodesScreen extends ConsumerStatefulWidget {
  const UnassignedNodesScreen({super.key});

  @override
  ConsumerState<UnassignedNodesScreen> createState() => _UnassignedNodesScreenState();
}

class _UnassignedNodesScreenState extends ConsumerState<UnassignedNodesScreen> {
  List<Map<String, dynamic>> _nodes = [];
  bool _loading = true;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
    ref.read(gatewaysProvider.notifier).fetchAll();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/api/nodes/unassigned');
      if (mounted) setState(() => _nodes = ((r.data as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: error ? context.c.badStrong : null),
    );
  }

  Future<void> _assign(Map<String, dynamic> n) async {
    final gateways = ref.read(gatewaysProvider);
    if (gateways.isEmpty) {
      _toast('Add a gateway first.', error: true);
      return;
    }
    final gwId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SimpleDialog(
        backgroundColor: ctx.c.card,
        title: Text('Give to which gateway?', style: TextStyle(color: ctx.c.text, fontSize: 16)),
        children: [
          for (final g in gateways)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.id),
              child: Row(children: [
                Icon(Icons.router_outlined, size: 18, color: g.online ? ctx.c.ok : ctx.c.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(g.name, style: TextStyle(color: ctx.c.text))),
                Text(g.online ? 'Online' : 'Offline', style: TextStyle(color: ctx.c.muted, fontSize: 12)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ),
        ],
      ),
    );
    if (gwId == null) return;
    setState(() => _busy = n['id'] as int);
    try {
      final r = await ref.read(apiServiceProvider).post('/api/nodes/unassigned/${n['id']}/assign', data: {'gatewayId': gwId});
      _toast((r.data is Map ? (r.data as Map)['message'] : null) as String? ?? 'Sent.');
      Future.delayed(const Duration(seconds: 4), _load);
    } catch (e) {
      _toast(apiError(e, 'Could not assign the node'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _forget(Map<String, dynamic> n) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.c.card,
        title: Text('Forget this node?', style: TextStyle(color: ctx.c.text)),
        content: Text(
          'The saved settings are removed from the hub. The node keeps its own and can still be paired again with its pairing code.',
          style: TextStyle(color: ctx.c.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.c.badStrong),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete('/api/nodes/unassigned/${n['id']}');
      _load();
    } catch (e) {
      _toast(apiError(e, 'Could not remove it'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.card,
        iconTheme: IconThemeData(color: c.text),
        title: Text('Unassigned nodes', style: TextStyle(color: c.text, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'These nodes belonged to a deleted gateway. They were not reset and still hold their settings. Give each one to a gateway that is in range.',
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ),
                if (_nodes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text('No unassigned nodes.', style: TextStyle(color: c.muted))),
                  ),
                for (final n in _nodes)
                  Card(
                    color: c.card,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          (n['name'] as String?)?.isNotEmpty == true ? n['name'] as String : 'Node ${n['deviceId']}',
                          style: TextStyle(color: c.text, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Device ${n['deviceId']}'
                          '${(n['mac'] as String?)?.isNotEmpty == true ? ' · ${n['mac']}' : ''}'
                          ' · ${n['modules']} module${n['modules'] == 1 ? '' : 's'}'
                          '${(n['fromGateway'] as String?)?.isNotEmpty == true ? ' · from ${n['fromGateway']}' : ''}',
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          FilledButton.icon(
                            onPressed: _busy == n['id'] ? null : () => _assign(n),
                            icon: _busy == n['id']
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.router_outlined, size: 18),
                            label: const Text('Give to a gateway'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(onPressed: _busy == n['id'] ? null : () => _forget(n), child: const Text('Forget')),
                        ]),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}
