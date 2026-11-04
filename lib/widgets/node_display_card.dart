import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/display.dart';
import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';

/// "Shown on display": pick the ONE display this node appears on (or none).
/// Choosing a display moves the node there, since a node is never shared.
class NodeDisplayCard extends ConsumerStatefulWidget {
  final String nodeId;
  final String gatewayId;
  final int? initialHmiId;
  const NodeDisplayCard({super.key, required this.nodeId, required this.gatewayId, this.initialHmiId});

  @override
  ConsumerState<NodeDisplayCard> createState() => _NodeDisplayCardState();
}

class _NodeDisplayCardState extends ConsumerState<NodeDisplayCard> {
  List<Display> _displays = [];
  int? _current;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialHmiId;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/api/hmis');
      final all = (r.data as List).map((j) => Display.fromJson(j as Map<String, dynamic>)).toList();
      if (mounted) setState(() { _displays = all.where((d) => d.gatewayId == widget.gatewayId).toList(); _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _set(int? hmiId) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiServiceProvider).put('/api/nodes/${widget.nodeId}/hmi', data: {'hmiId': hmiId});
      if (mounted) setState(() => _current = hmiId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e, 'Could not change the display')),
          backgroundColor: context.c.badStrong,
        ));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Nothing to choose from until a display is paired to this gateway.
    if (_loaded && _displays.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.tv, size: 18, color: c.accent),
            const SizedBox(width: 8),
            Text('Shown on display', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text('A node appears on one display only.', style: TextStyle(color: c.muted, fontSize: 12)),
          const SizedBox(height: 10),
          if (!_loaded)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<int?>(
              initialValue: _displays.any((d) => d.id == _current) ? _current : null,
              isExpanded: true,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('None')),
                for (final d in _displays) DropdownMenuItem<int?>(value: d.id, child: Text(d.name)),
              ],
              onChanged: _busy ? null : _set,
            ),
        ]),
      ),
    );
  }
}
