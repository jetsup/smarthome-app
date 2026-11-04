import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';

/// Theme, accent colour, brightness and status LED of one touch display.
/// The display picks the change up within a few seconds.
class DisplayAppearanceScreen extends ConsumerStatefulWidget {
  final String displaySlug;
  final String displayName;
  const DisplayAppearanceScreen({super.key, required this.displaySlug, required this.displayName});

  @override
  ConsumerState<DisplayAppearanceScreen> createState() => _DisplayAppearanceScreenState();
}

class _DisplayAppearanceScreenState extends ConsumerState<DisplayAppearanceScreen> {
  static const _accents = <String, Color>{
    '00A8E8': Color(0xFF00A8E8), '3FB950': Color(0xFF3FB950), 'F0A030': Color(0xFFF0A030),
    'A371F7': Color(0xFFA371F7), 'F85149': Color(0xFFF85149), 'E85D9A': Color(0xFFE85D9A),
    '14B8A6': Color(0xFF14B8A6), 'FFFFFF': Color(0xFFFFFFFF),
  };
  bool _loading = true;
  String _theme = 'dark';
  String _accent = '00A8E8';
  double _brightness = 100;
  bool _led = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/api/hmis/${widget.displaySlug}');
      final m = (r.data as Map)['hmi'] as Map;
      setState(() {
        _theme = m['theme'] == 'light' ? 'light' : 'dark';
        _accent = (m['accent'] as String? ?? '00A8E8').toUpperCase();
        _brightness = ((m['brightness'] as num?) ?? 100).toDouble().clamp(10, 100);
        _led = m['statusLed'] != false;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = apiError(e, 'Could not load the display'); _loading = false; });
    }
  }

  Future<void> _save(Map<String, dynamic> body) async {
    try {
      await ref.read(apiServiceProvider).put('/api/hmis/${widget.displaySlug}/appearance', data: body);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e, 'Could not save'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final light = _theme == 'light';
    final accent = _accents[_accent] ?? c.accent;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.displayName} · Appearance')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: c.bad)))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  // live preview of the screen
                  Container(
                    height: 130,
                    decoration: BoxDecoration(
                      color: light ? const Color(0xFFF2F4F7) : const Color(0xFF121214),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 70,
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: light ? Colors.white : const Color(0xFF1E1E24), borderRadius: BorderRadius.circular(8)),
                        child: Column(children: [
                          Container(height: 26, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(5))),
                          const SizedBox(height: 6),
                          Container(height: 26, decoration: BoxDecoration(color: light ? const Color(0xFFE4E7EC) : const Color(0xFF2D2D35), borderRadius: BorderRadius.circular(5))),
                        ]),
                      ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: light ? Colors.white : const Color(0xFF1E1E24), borderRadius: BorderRadius.circular(8)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Living room light', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                            const Spacer(),
                            Row(children: [
                              Text('Power', style: TextStyle(color: light ? const Color(0xFF111418) : Colors.white, fontSize: 12)),
                              const Spacer(),
                              Container(width: 34, height: 18, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(9))),
                            ]),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Text('Theme', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                      ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                    ],
                    selected: {_theme},
                    onSelectionChanged: (s) {
                      setState(() => _theme = s.first);
                      _save({'theme': _theme});
                    },
                  ),
                  const SizedBox(height: 22),
                  Text('Accent colour', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final e in _accents.entries)
                      GestureDetector(
                        onTap: () {
                          setState(() => _accent = e.key);
                          _save({'accent': e.key});
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(color: _accent == e.key ? c.text : c.border, width: _accent == e.key ? 3 : 1),
                          ),
                          child: _accent == e.key ? Icon(Icons.check, size: 18, color: e.key == 'FFFFFF' ? Colors.black : Colors.white) : null,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 22),
                  Row(children: [
                    Text('Brightness', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${_brightness.round()}%', style: TextStyle(color: c.muted)),
                  ]),
                  Slider(
                    value: _brightness,
                    min: 10,
                    max: 100,
                    divisions: 18,
                    onChanged: (v) {
                      setState(() => _brightness = v);
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () => _save({'brightness': v.round()}));
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Status light', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                    subtitle: Text('The small LED on the display', style: TextStyle(color: c.muted, fontSize: 12)),
                    value: _led,
                    onChanged: (v) {
                      setState(() => _led = v);
                      _save({'statusLed': v});
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('The display applies changes within a few seconds.', style: TextStyle(color: c.muted, fontSize: 12)),
                ]),
    );
  }
}
