import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/node.dart';
import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';

/// Settings of one node. Editing happens in place - the node never has to be paired again.
/// More settings can be added here later.
class NodeSettingsScreen extends ConsumerStatefulWidget {
  final SmartNode node;
  const NodeSettingsScreen({super.key, required this.node});

  @override
  ConsumerState<NodeSettingsScreen> createState() => _NodeSettingsScreenState();
}

class _NodeSettingsScreenState extends ConsumerState<NodeSettingsScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.node.name);
  late String _savedName = widget.node.name;
  bool _saving = false, _restarting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _base => '/api/nodes/${widget.node.nodeId}';

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? context.c.badStrong : null),
    );
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Give the node a name', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).put(_base, data: {'name': name});
      _savedName = name;
      await ref.read(nodesProvider(widget.node.gatewayId).notifier).fetchNodes();
      _toast('Renamed to “$name”.');
    } catch (e) {
      _toast(apiError(e, 'Could not rename the node'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restart() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.c.card,
        title: Text('Restart this node?', style: TextStyle(color: ctx.c.text)),
        content: Text(
          'The node reboots for a few seconds. Its pairing and settings are kept.',
          style: TextStyle(color: ctx.c.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restart')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _restarting = true);
    try {
      await ref.read(apiServiceProvider).post('$_base/restart');
      _toast('Restarting the node…');
    } catch (e) {
      _toast(apiError(e, 'Could not restart the node'), error: true);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.c.border),
        ),
        child: child,
      );

  Widget _heading(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: TextStyle(color: context.c.text, fontSize: 16, fontWeight: FontWeight.w600)),
          if (sub != null) Text(sub, style: TextStyle(color: context.c.muted, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final changed = _name.text.trim() != _savedName;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.card,
        title: Text('${_savedName.isEmpty ? 'Node' : _savedName} settings', style: TextStyle(color: c.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _heading('Node name', 'Shown in the app, on the website and on the display.'),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              maxLength: 40,
              style: TextStyle(color: c.text),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: c.muted),
                filled: true,
                fillColor: c.bg,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.accent)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_saving || !changed) ? null : _saveName,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save name'),
              ),
            ),
          ])),
          _heading('Maintenance'),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Restart reboots the node. Its pairing and saved settings are kept.',
                style: TextStyle(color: c.muted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _restarting ? null : _restart,
                icon: _restarting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.restart_alt),
                label: const Text('Restart node'),
              ),
            ),
          ])),
        ],
      ),
    );
  }
}
