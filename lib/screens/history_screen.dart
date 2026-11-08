import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/symbols.dart';
import '../theme/app_colors.dart';

class _Pt {
  final int t;
  final double v;
  final double? lo, hi;
  final bool estimated;
  _Pt(this.t, this.v, this.lo, this.hi, this.estimated);
}

/// History of one sensor channel, drawn from what the gateways logged (also while the hub was away).
class HistoryScreen extends ConsumerStatefulWidget {
  final String nodeId;
  final int cap;
  final int channel;
  final String label;
  final String subtitle;
  final String unit;
  final String symbol;
  final Color tint;
  final bool
  binary; // an on/off signal: shown as the share of time it was active
  const HistoryScreen({
    super.key,
    required this.nodeId,
    required this.cap,
    required this.channel,
    required this.label,
    required this.subtitle,
    required this.unit,
    required this.symbol,
    required this.tint,
    this.binary = false,
  });

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const _ranges = {1: '1 h', 6: '6 h', 24: '24 h', 168: '7 d'};
  int _hours = 24;
  List<_Pt> _pts = [];
  int _from = 0, _to = 1;
  bool _loading = true;
  String? _error;
  bool _table = false;
  int? _hover;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(quiet: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await ref
          .read(apiServiceProvider)
          .get(
            '/api/nodes/${widget.nodeId}/history',
            params: {
              'cap': widget.cap,
              'channel': widget.channel,
              'hours': _hours,
              'buckets': 160,
            },
          );
      final d = Map<String, dynamic>.from(r.data as Map);
      final list = [
        for (final p in (d['points'] as List? ?? []))
          _Pt(
            (p['t'] as num).toInt(),
            (p['v'] as num).toDouble(),
            (p['lo'] as num?)?.toDouble(),
            (p['hi'] as num?)?.toDouble(),
            p['estimated'] == true,
          ),
      ];
      if (!mounted) return;
      setState(() {
        _pts = list;
        _from = (d['from'] as num).toInt();
        _to = (d['to'] as num).toInt();
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the history';
          _loading = false;
        });
      }
    }
  }

  String _fmt(double v) {
    if (widget.binary) return '${(v * 100).round()}%';
    final n = v.abs() >= 100
        ? v.round().toString()
        : (v == v.roundToDouble()
              ? v.round().toString()
              : v.toStringAsFixed(1));
    return widget.unit.isEmpty ? n : '$n ${widget.unit}';
  }

  String _stamp(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    String two(int x) => x.toString().padLeft(2, '0');
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final time = '${two(d.hour)}:${two(d.minute)}';
    return _hours > 24 ? '${wd[d.weekday - 1]} ${d.day}, $time' : time;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    double lo = double.infinity, hi = -double.infinity, sum = 0;
    for (final p in _pts) {
      lo = math.min(lo, p.lo ?? p.v);
      hi = math.max(hi, p.hi ?? p.v);
      sum += p.v;
    }
    final has = _pts.isNotEmpty;
    final hp = _hover != null && _hover! < _pts.length ? _pts[_hover!] : null;

    Widget stat(String l, String v) => Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l, style: TextStyle(color: c.muted, fontSize: 10)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                v,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.card,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.tint.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                symbolIcon(widget.symbol),
                size: 18,
                color: widget.tint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _table ? 'Chart' : 'Table',
            icon: Icon(_table ? Icons.show_chart : Icons.table_rows_outlined),
            onPressed: () => setState(() => _table = !_table),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // filters: one row above the chart
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final e in _ranges.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {_hours},
              onSelectionChanged: (s) {
                setState(() {
                  _hours = s.first;
                  _hover = null;
                });
                _load();
              },
            ),
          ),
          const SizedBox(height: 12),
          if (has)
            Row(
              children: [
                stat('Latest', _fmt(_pts.last.v)),
                stat('Lowest', _fmt(lo)),
                stat('Highest', _fmt(hi)),
                stat('Average', _fmt(sum / _pts.length)),
              ],
            ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(_error!, style: TextStyle(color: c.bad)),
              ),
            )
          else if (!has)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  Icon(Icons.schedule, size: 36, color: c.muted),
                  const SizedBox(height: 8),
                  Text(
                    'No history for this time range yet.',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The gateway records readings as they change and sends them to the hub.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            )
          else if (_table)
            Container(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  for (final p in _pts.reversed.take(120))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.divider)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_stamp(p.t)}${p.estimated ? ' ~' : ''}',
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ),
                          Text(
                            _fmt(p.v),
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else ...[
            // the reading under the finger (or the latest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Text(
                    _fmt((hp ?? _pts.last).v),
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (hp?.lo != null && hp!.lo != hp.hi)
                    Text(
                      '${_fmt(hp.lo!)} – ${_fmt(hp.hi!)}',
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  const Spacer(),
                  Text(
                    '${_stamp((hp ?? _pts.last).t)}${(hp ?? _pts.last).estimated ? ' · time estimated' : ''}',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 260,
              padding: const EdgeInsets.fromLTRB(4, 12, 8, 4),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: LayoutBuilder(
                builder: (ctx, box) {
                  final painter = _ChartPainter(
                    pts: _pts,
                    from: _from,
                    to: _to,
                    tint: widget.tint,
                    binary: widget.binary,
                    hover: _hover,
                    grid: c.border.withValues(alpha: 0.55),
                    label: c.muted,
                    surface: c.card,
                    hours: _hours,
                  );
                  void pick(Offset o) => setState(
                    () => _hover = painter.nearest(o.dx, box.maxWidth),
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => pick(d.localPosition),
                    onHorizontalDragStart: (d) => pick(d.localPosition),
                    onHorizontalDragUpdate: (d) => pick(d.localPosition),
                    onTapUp: (_) {},
                    child: CustomPaint(
                      size: Size(box.maxWidth, box.maxHeight),
                      painter: painter,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Touch and drag along the chart to read a value.',
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<_Pt> pts;
  final int from, to, hours;
  final Color tint, grid, label, surface;
  final bool binary;
  final int? hover;
  _ChartPainter({
    required this.pts,
    required this.from,
    required this.to,
    required this.tint,
    required this.binary,
    required this.hover,
    required this.grid,
    required this.label,
    required this.surface,
    required this.hours,
  });

  static const padL = 40.0, padR = 6.0, padT = 6.0, padB = 22.0;

  late final double _lo, _hi, _step;
  bool _init = false;
  void _domain() {
    if (_init) return;
    _init = true;
    if (binary) {
      _lo = 0;
      _hi = 1;
      _step = 0.25;
      return;
    }
    double lo = double.infinity, hi = -double.infinity;
    for (final p in pts) {
      lo = math.min(lo, p.lo ?? p.v);
      hi = math.max(hi, p.hi ?? p.v);
    }
    if (hi == lo) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    final raw = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [
      1.0,
      2.0,
      2.5,
      5.0,
      10.0,
    ].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    _step = step;
    _lo = (lo / step).floor() * step;
    _hi = (hi / step).ceil() * step;
  }

  double _x(int t, double w) =>
      padL + (t - from) / math.max(1, to - from) * (w - padL - padR);
  double _y(double v, double h) =>
      padT + (1 - (v - _lo) / (_hi - _lo)) * (h - padT - padB);

  int? nearest(double dx, double width) {
    if (pts.isEmpty) return null;
    int best = 0;
    double bd = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (_x(pts[i].t, width) - dx).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _domain();
    final w = size.width, h = size.height;

    // recessive grid and axis labels
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    void text(
      String s,
      double x,
      double y, {
      TextAlign align = TextAlign.left,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: label, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.right
          ? x - tp.width
          : (align == TextAlign.center ? x - tp.width / 2 : x);
      tp.paint(canvas, Offset(dx, y - tp.height / 2));
    }

    for (double v = _lo; v <= _hi + _step / 1000; v += _step) {
      final y = _y(v, h);
      canvas.drawLine(Offset(padL, y), Offset(w - padR, y), gridPaint);
      final l = binary
          ? '${(v * 100).round()}%'
          : (v.abs() >= 100
                ? v.round().toString()
                : double.parse(v.toStringAsFixed(2)).toString());
      text(l, padL - 6, y, align: TextAlign.right);
    }
    for (var i = 0; i <= 4; i++) {
      final t = from + ((to - from) * i / 4).round();
      final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      String two(int x) => x.toString().padLeft(2, '0');
      const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final s = hours > 24
          ? '${wd[d.weekday - 1]} ${d.day}'
          : '${two(d.hour)}:${two(d.minute)}';
      text(
        s,
        _x(t, w).clamp(padL + 12, w - padR - 12),
        h - 8,
        align: TextAlign.center,
      );
    }

    final gap = math.max((to - from) / 160 * 4, 300);
    final xy = [for (final p in pts) Offset(_x(p.t, w), _y(p.v, h))];

    // min-max band
    if (pts.any((p) => p.lo != null && p.lo != p.hi) && pts.length > 1) {
      final up = [for (final p in pts) Offset(_x(p.t, w), _y(p.hi ?? p.v, h))];
      final dn = [
        for (final p in pts.reversed) Offset(_x(p.t, w), _y(p.lo ?? p.v, h)),
      ];
      final path = Path()..moveTo(up.first.dx, up.first.dy);
      for (final o in up.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      for (final o in dn) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, Paint()..color = tint.withValues(alpha: 0.14));
    }

    // area + line, broken where the data has a gap
    final baseY = _y(_lo, h);
    final linePaint = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [tint.withValues(alpha: 0.22), tint.withValues(alpha: 0.02)],
      ).createShader(Rect.fromLTWH(0, padT, w, h - padT - padB));
    var run = <int>[];
    void flush() {
      if (run.isEmpty) return;
      if (run.length == 1) {
        canvas.drawCircle(xy[run.first], 1.6, Paint()..color = tint);
      } else {
        final line = Path()..moveTo(xy[run.first].dx, xy[run.first].dy);
        for (final i in run.skip(1)) {
          line.lineTo(xy[i].dx, xy[i].dy);
        }
        final area = Path.from(line)
          ..lineTo(xy[run.last].dx, baseY)
          ..lineTo(xy[run.first].dx, baseY)
          ..close();
        canvas.drawPath(area, areaPaint);
        canvas.drawPath(line, linePaint);
      }
      run = [];
    }

    for (var i = 0; i < pts.length; i++) {
      if (i > 0 && pts[i].t - pts[i - 1].t > gap) flush();
      run.add(i);
    }
    flush();

    // latest value marker, and the one under the finger
    void marker(Offset o) {
      canvas.drawCircle(o, 6, Paint()..color = surface);
      canvas.drawCircle(o, 4.5, Paint()..color = tint);
    }

    if (xy.isNotEmpty) marker(xy.last);
    if (hover != null && hover! < xy.length) {
      final o = xy[hover!];
      canvas.drawLine(
        Offset(o.dx, padT),
        Offset(o.dx, h - padB),
        Paint()
          ..color = label
          ..strokeWidth = 1,
      );
      marker(o);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.pts != pts ||
      old.hover != hover ||
      old.tint != tint ||
      old.from != from ||
      old.to != to;
}
