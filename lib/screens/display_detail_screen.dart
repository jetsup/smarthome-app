import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/display.dart';
import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';
import 'display_appearance_screen.dart';

/// One display: rename it, choose which nodes it shows, or unpair it.
///
/// A node can be shown on only ONE display. Switching a node on here moves it
/// from whichever display had it; the hub enforces the same rule.
class DisplayDetailScreen extends ConsumerStatefulWidget {
  final String displaySlug;
  const DisplayDetailScreen({super.key, required this.displaySlug});

  @override
  ConsumerState<DisplayDetailScreen> createState() => _DisplayDetailScreenState();
}

class _DisplayDetailScreenState extends ConsumerState<DisplayDetailScreen> {
  Display? _display;
  List<DisplayNode> _nodes = [];
  int _siblings = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _path => '/api/hmis/${widget.displaySlug}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(dynamic data) {
    final m = data as Map<String, dynamic>;
    _display = Display.fromJson(m['hmi'] as Map<String, dynamic>);
    _nodes = ((m['nodes'] as List?) ?? []).map((j) => DisplayNode.fromJson(j as Map<String, dynamic>)).toList();
    _siblings = m['siblings'] as int? ?? 0;
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get(_path);
      if (mounted) setState(() { _apply(r.data); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e, 'Could not load this display'));
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? context.c.badStrong : null,
    ));
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: _display?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename display'),
        content: TextField(controller: ctl, maxLength: 40, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Kitchen')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _display?.name) return;
    try {
      await ref.read(apiServiceProvider).put(_path, data: {'name': name});
      await _load();
      _toast('Renamed');
    } catch (e) {
      _toast(apiError(e, 'Could not rename'), error: true);
    }
  }

  Future<void> _unpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair this display?'),
        content: const Text('It will stop showing your nodes and return to its pairing screen. Its nodes become unassigned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Unpair', style: TextStyle(color: ctx.c.bad))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete(_path);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast(apiError(e, 'Could not unpair'), error: true);
    }
  }

  /// Turn a node on/off for this display. Nodes on another display are moved here.
  Future<void> _toggle(DisplayNode n, bool on) async {
    final mine = _nodes.where((x) => x.hmiId == _display?.id).map((x) => x.deviceId).toSet();
    if (on) {
      if (n.hmiId != null && n.hmiId != _display?.id) {
        final move = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Move “${n.name.isEmpty ? 'Device ${n.deviceId}' : n.name}”?'),
            content: Text('A node can only be on one display. It is on “${n.hmiName}” now; moving it removes it from there.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move here')),
            ],
          ),
        );
        if (move != true) return;
      }
      mine.add(n.deviceId);
    } else {
      mine.remove(n.deviceId);
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiServiceProvider).put('$_path/nodes', data: {'deviceIds': mine.toList()});
      if (mounted) setState(() => _apply(r.data));
    } catch (e) {
      _toast(apiError(e, 'Could not change the assignment'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = _display;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.name ?? 'Display', style: TextStyle(color: c.text)),
        actions: [
          if (d != null) IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: _rename),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : d == null
              ? Center(child: Text(_error ?? 'Not found', style: TextStyle(color: c.muted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    _infoCard(d),
                    const SizedBox(height: 12),
                    ListTile(
                      tileColor: c.card,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border)),
                      leading: Icon(Icons.palette_outlined, color: c.accent),
                      title: Text('Appearance', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                      subtitle: Text('Theme, accent colour, brightness, LED', style: TextStyle(color: c.muted, fontSize: 12)),
                      trailing: Icon(Icons.chevron_right, color: c.muted),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DisplayAppearanceScreen(displaySlug: d.slug, displayName: d.name))),
                    ),
                    const SizedBox(height: 20),
                    Text('Nodes on this display',
                        style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('A node can be shown on only one display.',
                        style: TextStyle(color: c.muted, fontSize: 12)),
                    const SizedBox(height: 10),
                    _nodesCard(),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _unpair,
                      icon: Icon(Icons.link_off, color: c.bad),
                      label: Text('Unpair this display', style: TextStyle(color: c.bad)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: c.bad.withValues(alpha: 0.5))),
                    ),
                  ]),
                ),
    );
  }

  Widget _infoCard(Display d) {
    final c = context.c;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 90, child: Text(k, style: TextStyle(color: c.muted, fontSize: 13))),
            Expanded(child: Text(v, style: TextStyle(color: c.text, fontSize: 13))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Column(children: [
        row('Status', d.online ? 'Online' : 'Offline (not seen recently)'),
        row('Gateway', d.gatewayName),
        row('Display ID', d.shortId),
        if (_siblings > 0) row('Other displays', '$_siblings on this gateway'),
      ]),
    );
  }

  Widget _nodesCard() {
    final c = context.c;
    if (_nodes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Center(child: Text('This gateway has no nodes yet.', style: TextStyle(color: c.muted))),
      );
    }
    return Container(
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < _nodes.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.divider),
          _nodeRow(_nodes[i]),
        ],
      ]),
    );
  }

  Widget _nodeRow(DisplayNode n) {
    final c = context.c;
    final here = n.hmiId == _display?.id;
    final elsewhere = n.hmiId != null && !here;
    final title = n.name.isEmpty ? 'Device ${n.deviceId}' : n.name;
    final sub = here ? 'Shown on this display' : elsewhere ? 'On “${n.hmiName}”' : 'Not on any display';
    return SwitchListTile(
      value: here,
      onChanged: _busy ? null : (v) => _toggle(n, v),
      title: Text(title, style: TextStyle(color: c.text)),
      subtitle: Text(sub, style: TextStyle(color: elsewhere ? c.warnLike : c.muted, fontSize: 12)),
      secondary: Icon(Icons.circle, size: 12, color: n.isOnline ? c.ok : c.subtle),
    );
  }
}

extension on AppColors {
  /// Amber-ish text for "this node is on another display".
  Color get warnLike => const Color(0xFFd29922);
}
