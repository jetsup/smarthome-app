import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';
import '../widgets/lock_background_card.dart';

/// Theme, background, accent colour, brightness and RGB light of one touch display.
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
  // Page colours: '' = the theme's own. Panels and text are derived from it.
  static const _backgrounds = <String, String>{
    '': 'Default', '000000': 'Black', '121214': 'Graphite', '0B1F33': 'Navy',
    '10261C': 'Forest', '2A1538': 'Plum', 'F2F4F7': 'Paper', 'FFF4E0': 'Cream', 'E6F0FF': 'Sky',
  };
  static const _patterns = <String, (String, IconData)>{
    'solid': ('Solid', Icons.circle),
    'blink': ('Blink', Icons.flash_on),
    'breathe': ('Breathe', Icons.air),
    'fade': ('Fade', Icons.gradient),
    'rainbow': ('Rainbow cycle', Icons.looks),
    'random': ('Random', Icons.shuffle),
    'strobe': ('Strobe', Icons.bolt),
    'twinkle': ('Twinkle', Icons.auto_awesome),
    'flicker': ('Flame', Icons.local_fire_department_outlined),
    'sparkle': ('Sparkle', Icons.star_outline),
  };
  static const _ledColors = <String, Color>{
    '': Color(0x00000000), // follow the accent
    'FF2D2D': Color(0xFFFF2D2D), 'FF8A00': Color(0xFFFF8A00), 'FFD400': Color(0xFFFFD400),
    '3FB950': Color(0xFF3FB950), '00A8E8': Color(0xFF00A8E8), '3B5BFF': Color(0xFF3B5BFF),
    'A371F7': Color(0xFFA371F7), 'FF4FA3': Color(0xFFFF4FA3), 'FFFFFF': Color(0xFFFFFFFF),
  };
  bool _loading = true;
  String _background = '';
  String _ledMode = 'solid';
  String _ledColor = '';
  double _ledBrightness = 40;
  double _ledSpeed = 50;
  String _theme = 'dark';
  String _accent = '00A8E8';
  double _brightness = 100;
  bool _led = true;
  int _sleepAfter = 0;
  bool _ledSleepOff = true;
  static const _sleepOptions = {0: 'Never', 15: '15 seconds', 30: '30 seconds', 60: '1 minute', 120: '2 minutes', 300: '5 minutes', 600: '10 minutes', 1800: '30 minutes'};
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
        final sa = ((m['sleepAfter'] as num?) ?? 0).toInt();
        _sleepAfter = _sleepOptions.containsKey(sa) ? sa : 0;
        _ledSleepOff = m['ledSleepOff'] != false;
        _background = (m['background'] as String? ?? '').toUpperCase();
        _ledMode = _patterns.containsKey(m['ledMode']) ? m['ledMode'] as String : 'solid';
        _ledColor = (m['ledColor'] as String? ?? '').toUpperCase();
        _ledBrightness = ((m['ledBrightness'] as num?) ?? 40).toDouble().clamp(1, 100);
        _ledSpeed = ((m['ledSpeed'] as num?) ?? 50).toDouble().clamp(1, 100);
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

  static Color _effectiveAccent(Color a, bool lightPage) {
    if (lightPage && a.toARGB32() == 0xFFFFFFFF) return const Color(0xFF111418);
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final customBg = _background.isEmpty ? null : Color(int.parse('FF$_background', radix: 16));
    final light = customBg != null ? customBg.computeLuminance() > 0.27 : _theme == 'light';
    final pageColor = customBg ?? (light ? const Color(0xFFF2F4F7) : const Color(0xFF121214));
    final panelColor = customBg != null
        ? Color.alphaBlend(Colors.white.withValues(alpha: light ? 0.7 : 0.07), customBg)
        : (light ? Colors.white : const Color(0xFF1E1E24));
    final surfaceColor = customBg != null
        ? Color.alphaBlend((light ? Colors.black : Colors.white).withValues(alpha: light ? 0.08 : 0.14), customBg)
        : (light ? const Color(0xFFE4E7EC) : const Color(0xFF2D2D35));
    // A white accent is unreadable on a light page, so it turns near-black
    // there (and a black one turns white on a dark page).
    final accent = _effectiveAccent(_accents[_accent] ?? c.accent, light);
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
                      color: pageColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 70,
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: panelColor, borderRadius: BorderRadius.circular(8)),
                        child: Column(children: [
                          Container(height: 26, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(5))),
                          const SizedBox(height: 6),
                          Container(height: 26, decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(5))),
                        ]),
                      ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: panelColor, borderRadius: BorderRadius.circular(8)),
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
                  const SizedBox(height: 2),
                  Text('White switches to black on a light screen automatically.', style: TextStyle(color: c.muted, fontSize: 12)),
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
                            color: _effectiveAccent(e.value, light),
                            shape: BoxShape.circle,
                            border: Border.all(color: _accent == e.key ? c.text : c.border, width: _accent == e.key ? 3 : 1),
                          ),
                          child: _accent == e.key
                              ? Icon(Icons.check, size: 18, color: _effectiveAccent(e.value, light).computeLuminance() > 0.6 ? Colors.black : Colors.white)
                              : null,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 22),
                  Text('Background colour', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Panels and text adjust to stay readable.', style: TextStyle(color: c.muted, fontSize: 12)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final e in _backgrounds.entries)
                      Tooltip(
                        message: e.value,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _background = e.key);
                            _save({'background': e.key});
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: e.key.isEmpty ? c.card : Color(int.parse('FF${e.key}', radix: 16)),
                              shape: BoxShape.circle,
                              border: Border.all(color: _background == e.key ? c.accent : c.border, width: _background == e.key ? 3 : 1),
                            ),
                            child: e.key.isEmpty
                                ? Icon(Icons.auto_mode, size: 18, color: c.muted)
                                : (_background == e.key
                                    ? Icon(Icons.check, size: 18, color: Color(int.parse('FF${e.key}', radix: 16)).computeLuminance() > 0.5 ? Colors.black : Colors.white)
                                    : null),
                          ),
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
                  Row(children: [
                    Expanded(
                      child: Text('Turn the screen off after', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                    ),
                    DropdownButton<int>(
                      value: _sleepAfter,
                      dropdownColor: c.card,
                      underline: const SizedBox.shrink(),
                      style: TextStyle(color: c.text),
                      items: [for (final e in _sleepOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _sleepAfter = v);
                        _save({'sleepAfter': v});
                      },
                    ),
                  ]),
                  Text('Saves power: the display goes dark after this long without a touch. Touch it to wake.',
                      style: TextStyle(color: c.muted, fontSize: 12)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Turn the RGB light off with the screen', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                    value: _ledSleepOff,
                    onChanged: (v) {
                      setState(() => _ledSleepOff = v);
                      _save({'ledSleepOff': v});
                    },
                  ),
                  const SizedBox(height: 10),
                  Divider(color: c.border),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('RGB light', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                    subtitle: Text('The onboard RGB LED on the display', style: TextStyle(color: c.muted, fontSize: 12)),
                    value: _led,
                    onChanged: (v) {
                      setState(() => _led = v);
                      _save({'statusLed': v});
                    },
                  ),
                  if (_led) ...[
                    const SizedBox(height: 6),
                    Text('Pattern', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final e in _patterns.entries)
                        ChoiceChip(
                          avatar: Icon(e.value.$2, size: 16, color: _ledMode == e.key ? c.accent : c.muted),
                          label: Text(e.value.$1),
                          selected: _ledMode == e.key,
                          onSelected: (_) {
                            setState(() => _ledMode = e.key);
                            _save({'ledMode': e.key});
                          },
                        ),
                    ]),
                    const SizedBox(height: 16),
                    Text('Colour', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                    if (_ledMode == 'rainbow' || _ledMode == 'random')
                      Text('This pattern picks its own colours.', style: TextStyle(color: c.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final e in _ledColors.entries)
                        GestureDetector(
                          onTap: () {
                            setState(() => _ledColor = e.key);
                            _save({'ledColor': e.key});
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: e.key.isEmpty ? c.card : e.value,
                              shape: BoxShape.circle,
                              border: Border.all(color: _ledColor == e.key ? c.text : c.border, width: _ledColor == e.key ? 3 : 1),
                            ),
                            child: e.key.isEmpty
                                ? Icon(Icons.palette_outlined, size: 18, color: c.muted)
                                : (_ledColor == e.key ? Icon(Icons.check, size: 16, color: e.key == 'FFFFFF' || e.key == 'FFD400' ? Colors.black : Colors.white) : null),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    Text(_ledColor.isEmpty ? 'Following the accent colour' : '#$_ledColor', style: TextStyle(color: c.muted, fontSize: 12)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Text('LED brightness', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${_ledBrightness.round()}%', style: TextStyle(color: c.muted)),
                    ]),
                    Slider(
                      value: _ledBrightness,
                      min: 1,
                      max: 100,
                      onChanged: (v) {
                        setState(() => _ledBrightness = v);
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 400), () => _save({'ledBrightness': v.round()}));
                      },
                    ),
                    if (_ledMode != 'solid') ...[
                      Row(children: [
                        Text('Pattern speed', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(_ledSpeed < 34 ? 'Slow' : (_ledSpeed < 67 ? 'Medium' : 'Fast'), style: TextStyle(color: c.muted)),
                      ]),
                      Slider(
                        value: _ledSpeed,
                        min: 1,
                        max: 100,
                        onChanged: (v) {
                          setState(() => _ledSpeed = v);
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 400), () => _save({'ledSpeed': v.round()}));
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 18),
                  Text('Lock-screen picture', style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Shown behind the clock when the display locks.', style: TextStyle(color: c.muted, fontSize: 12)),
                  const SizedBox(height: 10),
                  LockBackgroundCard(displaySlug: widget.displaySlug),
                  const SizedBox(height: 14),
                  Text('The display applies changes within a few seconds.', style: TextStyle(color: c.muted, fontSize: 12)),
                ]),
    );
  }
}
