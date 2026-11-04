import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_colors.dart';

class _Entry {
  final int id;
  final String action, details, actor, device, ip, category, outcome;
  final DateTime at;
  _Entry(Map<String, dynamic> j)
      : id = j['id'] as int,
        action = j['action'] as String? ?? '',
        details = j['details'] as String? ?? '',
        actor = j['actor'] as String? ?? '',
        device = j['device'] as String? ?? '',
        ip = j['ipAddress'] as String? ?? '',
        category = j['category'] as String? ?? 'system',
        outcome = j['outcome'] as String? ?? 'ok',
        at = DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now();
  bool get failed => outcome == 'failed';
}

/// Audit trail: who did what, from which device, and when.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  static const _cats = {
    '': 'All', 'security': 'Security', 'account': 'Account', 'gateway': 'Gateways',
    'node': 'Nodes', 'display': 'Displays', 'wifi': 'Wi-Fi',
  };
  final _items = <_Entry>[];
  String _cat = '';
  bool _failedOnly = false;
  bool _loading = true, _more = false, _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _loading = true; _error = null; });
    } else {
      setState(() => _more = true);
    }
    try {
      final r = await ref.read(apiServiceProvider).get('/api/audit', params: {
        'limit': 40,
        if (_cat.isNotEmpty) 'category': _cat,
        if (_failedOnly) 'outcome': 'failed',
        if (!reset && _items.isNotEmpty) 'before': _items.last.id,
      });
      final list = ((r.data as Map)['items'] as List).map((j) => _Entry(j as Map<String, dynamic>)).toList();
      if (reset) _items.clear();
      _items.addAll(list);
      _hasMore = list.length == 40;
    } catch (_) {
      _error = 'Could not load the activity log';
    }
    if (mounted) setState(() { _loading = false; _more = false; });
  }

  String _ago(DateTime d) {
    final s = DateTime.now().difference(d);
    if (s.inSeconds < 60) return 'just now';
    if (s.inMinutes < 60) return '${s.inMinutes} min ago';
    if (s.inHours < 24) return '${s.inHours} h ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  String _title(String a) => a.isEmpty ? a : a[0].toUpperCase() + a.substring(1).replaceAll('_', ' ');

  Color _dot(_Entry e) {
    final c = context.c;
    if (e.failed) return c.bad;
    return switch (e.category) { 'security' => const Color(0xFFA371F7), 'node' => c.ok, 'display' => const Color(0xFFF0A030), _ => c.accent };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Activity log')),
      body: Column(children: [
        SizedBox(
          height: 54,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final e in _cats.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(e.value), selected: _cat == e.key, onSelected: (_) { _cat = e.key; _load(reset: true); }),
              ),
            FilterChip(label: const Text('Failed only'), selected: _failedOnly, onSelected: (v) { _failedOnly = v; _load(reset: true); }),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: c.bad)))
                  : _items.isEmpty
                      ? Center(child: Text('No activity yet', style: TextStyle(color: c.muted)))
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _items.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (_, __) => Divider(color: c.divider, height: 1),
                            itemBuilder: (_, i) {
                              if (i == _items.length) {
                                return TextButton(onPressed: _more ? null : () => _load(), child: Text(_more ? 'Loading…' : 'Load older'));
                              }
                              final e = _items[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Container(margin: const EdgeInsets.only(top: 6, right: 12), width: 9, height: 9,
                                      decoration: BoxDecoration(color: _dot(e), shape: BoxShape.circle)),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        Flexible(child: Text(_title(e.action), style: TextStyle(color: c.text, fontWeight: FontWeight.w600))),
                                        if (e.failed) ...[
                                          const SizedBox(width: 8),
                                          Text('failed', style: TextStyle(color: c.bad, fontSize: 11, fontWeight: FontWeight.w700)),
                                        ],
                                      ]),
                                      if (e.details.isNotEmpty) Text(e.details, style: TextStyle(color: c.text, fontSize: 13)),
                                      Text(
                                        [if (e.actor.isNotEmpty) e.actor, if (e.device.isNotEmpty) e.device, if (e.ip.isNotEmpty) e.ip].join(' · '),
                                        style: TextStyle(color: c.muted, fontSize: 12),
                                      ),
                                    ]),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_ago(e.at), style: TextStyle(color: c.muted, fontSize: 11)),
                                ]),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
