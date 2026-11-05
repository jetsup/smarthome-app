import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/node.dart';
import '../services/catalog.dart';
import '../theme/app_colors.dart';

/// One editable module (pin, NeoPixel count, ring…).
class CapEntry {
  String type;
  final Map<String, TextEditingController> nums = {};
  bool ring = false;
  final TextEditingController label;

  CapEntry(CapType t, {CapabilityConfig? from})
      : type = t.key,
        label = TextEditingController(text: from?.label ?? '') {
    for (final f in t.fields) {
      if (f.key == 'ring') {
        ring = from?.ring ?? f.def == 1;
      } else {
        final cur = from == null ? f.def : _read(from, f.key);
        nums[f.key] = TextEditingController(text: '${cur == 0 && f.def != 0 ? f.def : cur}');
      }
    }
  }

  static int _read(CapabilityConfig c, String key) {
    switch (key) {
      case 'pin': return c.pin;
      case 'pin2': return c.pin2;
      case 'count': return c.count;
      case 'extra': return c.extra;
    }
    return 0;
  }

  Map<String, dynamic> toMap() {
    int n(String k) => int.tryParse(nums[k]?.text.trim() ?? '') ?? 0;
    return {
      'type': type,
      'label': label.text.trim(),
      if (nums.containsKey('pin')) 'pin': n('pin'),
      if (nums.containsKey('pin2')) 'pin2': n('pin2'),
      if (nums.containsKey('count')) 'count': n('count'),
      if (nums.containsKey('extra')) 'extra': n('extra'),
      'ring': ring,
    };
  }
}

/// Editable list of modules, generated from the hub's catalog.
class CapabilityEditor extends StatefulWidget {
  final CapCatalog catalog;
  final List<CapEntry> entries;
  final VoidCallback? onChanged;
  const CapabilityEditor({super.key, required this.catalog, required this.entries, this.onChanged});

  @override
  State<CapabilityEditor> createState() => _CapabilityEditorState();
}

class _CapabilityEditorState extends State<CapabilityEditor> {
  List<CapType> _group(bool Function(CapType) f) => widget.catalog.types.where(f).toList();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final adv = {'i2c', 'uart', 'irTx', 'irRx'};
    final items = <DropdownMenuItem<String>>[
      for (final t in _group((t) => t.kind == 'io' && !adv.contains(t.key))) DropdownMenuItem(value: t.key, child: Text(t.label)),
      for (final t in _group((t) => t.kind == 'sensor')) DropdownMenuItem(value: t.key, child: Text(t.label)),
      for (final t in _group((t) => t.kind == 'actuator')) DropdownMenuItem(value: t.key, child: Text(t.label)),
      for (final t in _group((t) => adv.contains(t.key))) DropdownMenuItem(value: t.key, child: Text(t.label)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < widget.entries.length; i++) _row(c, i, items),
      if (widget.entries.length < 8)
        TextButton.icon(
          onPressed: () => setState(() {
            widget.entries.add(CapEntry(widget.catalog.of('digitalOutput') ?? widget.catalog.types.first));
            widget.onChanged?.call();
          }),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add a module'),
        ),
    ]);
  }

  Widget _row(AppColors c, int i, List<DropdownMenuItem<String>> items) {
    final e = widget.entries[i];
    final t = widget.catalog.of(e.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: e.type,
              dropdownColor: c.card,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              style: TextStyle(color: c.text, fontSize: 13),
              items: items,
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  final next = CapEntry(widget.catalog.of(v)!);
                  next.label.text = e.label.text;
                  widget.entries[i] = next;
                  widget.onChanged?.call();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: e.label,
              maxLength: 10,
              style: TextStyle(color: c.text, fontSize: 13),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Label', counterText: ''),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close, color: c.bad, size: 18),
            onPressed: widget.entries.length > 1 ? () => setState(() { widget.entries.removeAt(i); widget.onChanged?.call(); }) : null,
          ),
        ]),
        if (t != null && t.hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.hint, style: TextStyle(color: c.muted, fontSize: 11))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in t?.fields ?? <CapField>[])
            if (f.key == 'ring')
              FilterChip(
                label: Text(f.label),
                selected: e.ring,
                onSelected: (v) => setState(() { e.ring = v; widget.onChanged?.call(); }),
              )
            else if (f.options.isNotEmpty)
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  initialValue: f.options.contains(int.tryParse(e.nums[f.key]!.text)) ? int.parse(e.nums[f.key]!.text) : f.options.first,
                  dropdownColor: c.card,
                  decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: f.label),
                  style: TextStyle(color: c.text, fontSize: 13),
                  items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text('$o'))],
                  onChanged: (v) => e.nums[f.key]!.text = '${v ?? f.options.first}',
                ),
              )
            else
              SizedBox(
                width: f.key == 'count' ? 140 : 120,
                child: TextField(
                  controller: e.nums[f.key],
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: c.text, fontSize: 13),
                  decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: f.label),
                ),
              ),
        ]),
      ]),
    );
  }
}

/// Dialog wrapper: edit/add modules. Returns the list the hub accepts, or null.
Future<List<Map<String, dynamic>>?> showCapabilityDialog(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String confirmText,
  List<CapabilityConfig> initial = const [],
}) async {
  final catalog = await ref.read(capCatalogProvider.future);
  final entries = <CapEntry>[
    for (final c in initial) CapEntry(catalog.of(c.type) ?? catalog.types.first, from: c),
    if (initial.isEmpty) CapEntry(catalog.of('digitalOutput') ?? catalog.types.first),
  ];
  if (!context.mounted) return null;
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.c.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: Text(title, style: TextStyle(color: ctx.c.text, fontSize: 17)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(child: CapabilityEditor(catalog: catalog, entries: entries)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, entries.map((e) => e.toMap()).toList()), child: Text(confirmText)),
      ],
    ),
  );
}
