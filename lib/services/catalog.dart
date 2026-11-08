import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// The hub describes every kind of module (fields, readings, actions) in one catalog;
/// forms and controls are generated from it, so new hardware needs no app update.
class CapField {
  final String key, label;
  final int def, min, max;
  final List<int> options;
  CapField(Map<String, dynamic> j)
      : key = j['key'] as String? ?? '',
        label = j['label'] as String? ?? '',
        def = j['default'] as int? ?? 0,
        min = j['min'] as int? ?? 0,
        max = j['max'] as int? ?? 0,
        options = ((j['options'] as List?) ?? const []).cast<int>();
}

class CapChoice {
  final int value;
  final String label;
  final bool ring;
  CapChoice(Map<String, dynamic> j)
      : value = j['value'] as int? ?? 0,
        label = j['label'] as String? ?? '',
        ring = j['ring'] as bool? ?? false;
}

class ActionParam {
  final String key, label, kind;
  final int min, max;
  final dynamic def;
  final List<CapChoice> choices;
  // Colour params: a "random colour" choice exists, except for these patterns.
  final bool allowRandom;
  final List<int> noRandom;
  ActionParam(Map<String, dynamic> j)
      : key = j['key'] as String? ?? '',
        label = j['label'] as String? ?? '',
        kind = j['kind'] as String? ?? 'number',
        min = j['min'] as int? ?? 0,
        max = j['max'] as int? ?? 100,
        def = j['default'],
        allowRandom = j['allowRandom'] == true,
        noRandom = ((j['noRandom'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        choices = ((j['choices'] as List?) ?? const []).map((e) => CapChoice(e as Map<String, dynamic>)).toList();
}

class CapAction {
  final int id;
  final String key, label;
  final List<ActionParam> params;
  CapAction(Map<String, dynamic> j)
      : id = j['id'] as int? ?? 0,
        key = j['key'] as String? ?? '',
        label = j['label'] as String? ?? '',
        params = ((j['params'] as List?) ?? const []).map((e) => ActionParam(e as Map<String, dynamic>)).toList();
}

class CapChannel {
  final int id;
  final String key, label, unit;
  CapChannel(Map<String, dynamic> j)
      : id = j['id'] as int? ?? 0,
        key = j['key'] as String? ?? '',
        label = j['label'] as String? ?? '',
        unit = j['unit'] as String? ?? '';
}

class CapType {
  final String key, label, kind, hint;
  final int code;
  final List<CapField> fields;
  final List<CapChannel> channels;
  final List<CapAction> actions;
  CapType(Map<String, dynamic> j)
      : key = j['key'] as String? ?? '',
        label = j['label'] as String? ?? '',
        kind = j['kind'] as String? ?? 'io',
        hint = j['hint'] as String? ?? '',
        code = j['code'] as int? ?? 0,
        fields = ((j['fields'] as List?) ?? const []).map((e) => CapField(e as Map<String, dynamic>)).toList(),
        channels = ((j['channels'] as List?) ?? const []).map((e) => CapChannel(e as Map<String, dynamic>)).toList(),
        actions = ((j['actions'] as List?) ?? const []).map((e) => CapAction(e as Map<String, dynamic>)).toList();

  bool hasField(String k) => fields.any((f) => f.key == k);
}

class CapCatalog {
  final List<CapType> types;
  const CapCatalog(this.types);
  CapType? of(String key) => types.where((t) => t.key == key).firstOrNull;
}

final capCatalogProvider = FutureProvider<CapCatalog>((ref) async {
  final r = await ref.read(apiServiceProvider).get('/api/capabilities/catalog');
  final list = ((r.data as Map)['types'] as List).map((e) => CapType(e as Map<String, dynamic>)).toList();
  return CapCatalog(list);
});
