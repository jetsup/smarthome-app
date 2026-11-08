import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/node.dart';
import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../services/catalog.dart';
import '../theme/app_colors.dart';

/// Sensors' live readings and every module's actions (NeoPixel patterns, buzzer sounds,
/// set the RTC clock…), generated from the hub's catalog.
class ModuleControls extends ConsumerStatefulWidget {
  final SmartNode node;
  final Future<void> Function()? onChanged;
  const ModuleControls({super.key, required this.node, this.onChanged});

  @override
  ConsumerState<ModuleControls> createState() => _ModuleControlsState();
}

class _ModuleControlsState extends ConsumerState<ModuleControls> {
  final _forms = <String, Map<String, dynamic>>{};
  bool _busy = false;
  bool _live = false;

  static const _swatches = [
    '#FF3B30',
    '#FF9500',
    '#FFD60A',
    '#34C759',
    '#00A8E8',
    '#5E5CE6',
    '#BF5AF2',
    '#FFFFFF',
  ];

  final _seen = <int, String>{};
  final _sentAt = <int, DateTime>{};

  /// The form follows the hub's remembered setting, so every screen shows the real current preset
  /// (changed from another phone, the website, the display or a rule).
  Map<String, dynamic> _form(int idx, CapAction a) {
    final eff = widget.node.effects['$idx'];
    final sig = eff == null ? '' : jsonEncode(eff);
    final key = '$idx:${a.key}';
    final recent =
        _sentAt[idx] != null &&
        DateTime.now().difference(_sentAt[idx]!) < const Duration(seconds: 6);
    if (_forms.containsKey(key) && (_seen[idx] == sig || recent))
      return _forms[key]!;
    final f = <String, dynamic>{for (final p in a.params) p.key: p.def};
    if (eff != null) f.addAll(eff);
    _seen[idx] = sig;
    return _forms[key] = f;
  }

  Future<void> _send(int idx, CapAction a, Map<String, dynamic> params) async {
    setState(() => _busy = true);
    _sentAt[idx] = DateTime.now();
    String msg;
    try {
      final r = await ref
          .read(apiServiceProvider)
          .post(
            '/api/nodes/${widget.node.nodeId}/action',
            data: {'cap': idx, 'action': a.key, 'params': params},
          );
      final d = r.data is Map ? r.data as Map : {};
      msg = d['status'] == 'saved_offline'
          ? (d['message'] as String? ?? 'Saved.')
          : 'Sent.';
      await widget.onChanged?.call();
    } catch (e) {
      msg = apiError(e, 'Could not send');
    }
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    }
  }

  String _fmt(SensorReading r) {
    if (r.key == 'time') {
      final d = DateTime.fromMillisecondsSinceEpoch(
        r.value.round() * 1000,
        isUtc: true,
      );
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} UTC';
    }
    final v = r.value == r.value.roundToDouble()
        ? r.value.round().toString()
        : r.value.toStringAsFixed(1);
    return r.unit.isEmpty ? v : '$v ${r.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(capCatalogProvider);
    final catalog = catalogAsync.valueOrNull;
    if (catalog == null) return const SizedBox.shrink();
    final c = context.c;
    final cards = <Widget>[];
    final caps = widget.node.capabilitiesConfig;
    for (var i = 0; i < caps.length; i++) {
      final cap = caps[i];
      final t = catalog.of(cap.type);
      if (t == null || cap.type == 'analogInput' || cap.type == 'digitalInput')
        continue;
      final readings = widget.node.readings.where((r) => r.cap == i).toList()
        ..sort((a, b) => a.channel.compareTo(b.channel));
      if (t.actions.isEmpty && readings.isEmpty) continue;
      cards.add(
        Card(
          color: c.card,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: c.border),
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
                        cap.label.isEmpty ? t.label : cap.label,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (cap.display.isNotEmpty)
                      Text(
                        cap.display,
                        style: TextStyle(
                          color: c.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                Text(t.label, style: TextStyle(color: c.muted, fontSize: 12)),
                if (readings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final r in readings)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fmt(r),
                                style: TextStyle(
                                  color: c.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                r.label,
                                style: TextStyle(color: c.muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                for (final a in t.actions) ..._action(c, i, cap, t, a),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: cards);
  }

  List<Widget> _action(
    AppColors c,
    int idx,
    CapabilityConfig cap,
    CapType t,
    CapAction a,
  ) {
    final f = _form(idx, a);
    return [
      const SizedBox(height: 14),
      for (final p in a.params) _param(c, idx, cap, a, f, p),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(
            onPressed: _busy ? null : () => _send(idx, a, Map.of(f)),
            child: Text(switch (a.key) {
              'setEffect' => 'Apply pattern',
              'play' => 'Play',
              'syncTime' => 'Set clock from system time',
              _ => a.label,
            }),
          ),
          if (t.key == 'neopixel')
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _send(idx, a, {...f, 'pattern': 0}),
              child: const Text('Turn off'),
            ),
          if (t.key == 'buzzer')
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _send(idx, a, {'pattern': 0, 'repeat': 1}),
              child: const Text('Stop'),
            ),
        ],
      ),
      if (t.key == 'neopixel')
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Apply changes instantly',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
          value: _live,
          onChanged: (v) => setState(() => _live = v),
        ),
    ];
  }

  void _changed(
    int idx,
    CapAction a,
    Map<String, dynamic> f, {
    bool commit = true,
  }) {
    setState(() {});
    if (_live && commit && a.key == 'setEffect') _send(idx, a, Map.of(f));
  }

  Widget _param(
    AppColors c,
    int idx,
    CapabilityConfig cap,
    CapAction a,
    Map<String, dynamic> f,
    ActionParam p,
  ) {
    switch (p.kind) {
      case 'pattern':
        final cur =
            (f[p.key] as num?)?.toInt() ?? (p.def as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: p.choices.any((x) => x.value == cur)
                ? cur
                : p.choices.first.value,
            dropdownColor: c.card,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              labelText: p.label,
            ),
            style: TextStyle(color: c.text, fontSize: 14),
            items: [
              for (final ch in p.choices)
                DropdownMenuItem(
                  value: ch.value,
                  enabled: !ch.ring || cap.ring,
                  child: Text(
                    ch.ring
                        ? '${ch.label}${cap.ring ? '' : ' (ring only)'}'
                        : ch.label,
                    style: TextStyle(
                      color: (!ch.ring || cap.ring) ? c.text : c.subtle,
                    ),
                  ),
                ),
            ],
            onChanged: (v) {
              f[p.key] = v;
              _changed(idx, a, f);
            },
          ),
        );
      case 'color':
        final hex = (f[p.key] as String? ?? '#00A8E8').toUpperCase();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.label, style: TextStyle(color: c.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final s in _swatches)
                    GestureDetector(
                      onTap: () {
                        f[p.key] = s;
                        _changed(idx, a, f);
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(
                            int.parse('FF${s.substring(1)}', radix: 16),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: hex == s ? c.text : c.border,
                            width: hex == s ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      case 'range':
        final v = ((f[p.key] as num?) ?? 50).toDouble().clamp(
          p.min.toDouble(),
          p.max.toDouble(),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  p.label,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: v,
                  min: p.min.toDouble(),
                  max: p.max.toDouble(),
                  onChanged: (x) => setState(() => f[p.key] = x.round()),
                  onChangeEnd: (_) => _changed(idx, a, f),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${v.round()}',
                  textAlign: TextAlign.end,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      case 'bool':
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(p.label, style: TextStyle(color: c.muted, fontSize: 13)),
          value: f[p.key] == true,
          onChanged: (v) {
            f[p.key] = v;
            _changed(idx, a, f);
          },
        );
      default: // number
        final v = ((f[p.key] as num?) ?? 0).toDouble().clamp(
          p.min.toDouble(),
          p.max.toDouble(),
        );
        return Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                p.label,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
            Expanded(
              child: Slider(
                value: v,
                min: p.min.toDouble(),
                max: p.max.toDouble(),
                divisions: (p.max - p.min) > 0 ? p.max - p.min : null,
                label: '${v.round()}',
                onChanged: (x) => setState(() => f[p.key] = x.round()),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${v.round()}',
                textAlign: TextAlign.end,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
          ],
        );
    }
  }
}
