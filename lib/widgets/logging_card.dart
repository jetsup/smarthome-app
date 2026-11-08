import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_colors.dart';

/// Data logging of one gateway: where it keeps readings while the hub is unreachable, how much
/// space it may use, and the RTC / SD-card pins. Shows what the gateway reports about itself.
class LoggingCard extends ConsumerStatefulWidget {
  final String gatewayId;
  const LoggingCard({super.key, required this.gatewayId});

  @override
  ConsumerState<LoggingCard> createState() => _LoggingCardState();
}

class _LoggingCardState extends ConsumerState<LoggingCard> {
  int _store = 0;
  final _kb = TextEditingController(text: '256');
  final _sdCs = TextEditingController(text: '5');
  final _sda = TextEditingController(text: '21');
  final _scl = TextEditingController(text: '22');
  Map<String, dynamic>? _status;
  int _storedOnHub = 0;
  bool _dirty = false;
  bool _saving = false;
  bool _loaded = false;
  Timer? _timer;

  String get _path => '/api/gateways/${widget.gatewayId}/logging';

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _kb.dispose();
    _sdCs.dispose();
    _sda.dispose();
    _scl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final r = await ref.read(apiServiceProvider).get(_path);
      final d = Map<String, dynamic>.from(r.data as Map);
      if (!mounted) return;
      setState(() {
        if (!_dirty) {
          _store = (d['store'] as num?)?.toInt() ?? 0;
          _kb.text = '${d['maxKb'] ?? 256}';
          _sdCs.text = '${d['sdCs'] ?? 5}';
          _sda.text = '${d['rtcSda'] ?? 21}';
          _scl.text = '${d['rtcScl'] ?? 22}';
        }
        _storedOnHub = (d['storedOnHub'] as num?)?.toInt() ?? 0;
        _status = d['status'] == null
            ? null
            : Map<String, dynamic>.from(d['status'] as Map);
        _loaded = true;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(apiServiceProvider)
          .put(
            _path,
            data: {
              'store': _store,
              'maxKb': int.tryParse(_kb.text) ?? 256,
              'sdCs': int.tryParse(_sdCs.text) ?? 5,
              'rtcSda': int.tryParse(_sda.text) ?? 21,
              'rtcScl': int.tryParse(_scl.text) ?? 22,
            },
          );
      _dirty = false;
      final applied = (r.data as Map)['applied'] == true;
      _toast(
        applied
            ? 'Logging settings sent to the gateway.'
            : 'Saved. The gateway gets them when it connects.',
      );
    } catch (e) {
      String msg = 'Could not save the settings';
      try {
        final d = (e as dynamic).response?.data;
        if (d is Map && d['error'] != null) msg = '${d['error']}';
      } catch (_) {}
      _toast(msg, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? context.c.badStrong : null,
      ),
    );
  }

  Widget _chip(IconData i, String t) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              t,
              style: TextStyle(
                color: c.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController ctl, String label, {String? helper}) =>
      TextField(
        controller: ctl,
        keyboardType: TextInputType.number,
        style: TextStyle(color: context.c.text),
        onChanged: (_) => setState(() => _dirty = true),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = _status;
    const timeSources = [
      'No real time yet (uptime)',
      'Time from the RTC module',
      'Time from the hub',
      'Time from the internet',
    ];
    const rtc = ['not found', 'found, not set', 'working'];
    final kb = int.tryParse(_kb.text) ?? 256;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The gateway keeps every sensor reading with its time, so nothing is lost while the hub is unreachable. It sends them when the hub is back and then clears them. Time comes from the RTC module, else the internet, else the hub; with none of those it counts uptime and fixes the times once it knows the real one.',
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (st != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  Icons.schedule,
                  timeSources[((st['timeSource'] as num?)?.toInt() ?? 0).clamp(
                    0,
                    3,
                  )],
                ),
                _chip(
                  Icons.memory,
                  'RTC ${rtc[((st['rtc'] as num?)?.toInt() ?? 0).clamp(0, 2)]}',
                ),
                _chip(
                  Icons.layers_outlined,
                  '${st['pending'] ?? 0} waiting on the gateway',
                ),
                _chip(
                  Icons.sd_storage_outlined,
                  'storing on ${st['sdCard'] == true ? 'the SD card' : 'flash'}',
                ),
              ],
            )
          else
            Text(
              _loaded
                  ? 'The gateway is offline: settings are saved and sent when it connects.'
                  : 'Loading…',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          const SizedBox(height: 14),
          Text(
            'Store the data on',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Flash (default)'),
                  icon: Icon(Icons.memory),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('SD card'),
                  icon: Icon(Icons.sd_card_outlined),
                ),
              ],
              selected: {_store},
              onSelectionChanged: (s) => setState(() {
                _store = s.first;
                _dirty = true;
              }),
            ),
          ),
          const SizedBox(height: 12),
          _num(
            _kb,
            'Space limit (KB)',
            helper:
                'When it is full the oldest data is overwritten. About ${(kb * 1024 / 16).round()} readings.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _num(_sda, 'RTC SDA pin')),
              const SizedBox(width: 10),
              Expanded(child: _num(_scl, 'RTC SCL pin')),
            ],
          ),
          if (_store == 1) ...[
            const SizedBox(height: 12),
            _num(
              _sdCs,
              'SD card chip-select (CS) pin',
              helper:
                  "SPI pins: SCK 18, MISO 19, MOSI 23. Changing where data is stored restarts the gateway.",
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_storedOnHub readings stored on the hub.',
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
