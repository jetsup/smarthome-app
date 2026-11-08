import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../services/symbols.dart';
import '../theme/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/mfa_approval_host.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'walkthrough_screen.dart';

/// One tile of the monitoring dashboard (the hub decides what can be watched or controlled).
class MonWidget {
  final Map<String, dynamic> j;
  MonWidget(this.j);
  String get id => j['id'] as String;
  String get gatewayId => j['gatewayId'] as String? ?? '';
  String get gatewayName => j['gatewayName'] as String? ?? '';
  String get nodeId => j['nodeId'] as String? ?? '';
  String get nodeName => j['nodeName'] as String? ?? '';
  bool get online => j['online'] == true;
  int get cap => (j['cap'] as num?)?.toInt() ?? 0;
  int get channel => (j['channel'] as num?)?.toInt() ?? 0;
  bool get history => j['history'] == true;
  int get pin => (j['pin'] as num?)?.toInt() ?? 0;
  String get kind => j['kind'] as String? ?? '';
  String get label => j['label'] as String? ?? '';
  String get module => j['module'] as String? ?? '';
  String get symbol => j['symbol'] as String? ?? 'chip';
  String get unit => j['unit'] as String? ?? '';
  double get value => (j['value'] as num?)?.toDouble() ?? 0;
  bool get on => j['on'] == true;
  String get text => j['text'] as String? ?? '';
  double get min => (j['min'] as num?)?.toDouble() ?? 0;
  double get max => (j['max'] as num?)?.toDouble() ?? 0;
  bool get hasValue => j['hasValue'] == true;
  String get color => j['color'] as String? ?? '';
  String get pattern => j['pattern'] as String? ?? '';
  Map<String, dynamic> get params =>
      Map<String, dynamic>.from((j['params'] as Map?) ?? {});
  bool hidden = false;
}

class _Local {
  final bool? on;
  final double? value;
  final DateTime at;
  _Local({this.on, this.value}) : at = DateTime.now();
  bool get fresh => DateTime.now().difference(at) < const Duration(seconds: 5);
}

class _CardDrag {
  final String id;
  _CardDrag(this.id);
}

class _TileDrag {
  final String id;
  final String node;
  _TileDrag(this.id, this.node);
}

class _Card {
  final String id;
  final String name;
  final String gatewayName;
  final bool online;
  final List<MonWidget> widgets;
  _Card(this.id, this.name, this.gatewayName, this.online, this.widgets);
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _monTimer;
  Timer? _gwTimer;
  Timer? _saveTimer;
  DateTime? _lastBack;

  bool _loading = true;
  bool _customizing = false;
  List<Map<String, dynamic>> _gateways = [];
  List<MonWidget> _widgets = [];
  String _scope = 'all';
  final Set<String> _hidden = {};
  List<String> _order = [];
  final Map<String, List<String>> _tileOrder = {};
  final Map<String, _Local> _local = {};
  final Map<String, String> _errs = {};
  final Map<String, String> _lastPattern = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
      _checkConnectivity();
      _maybeShowWalkthrough();
    });
    _monTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _load();
    });
    _startGatewayPolling();
  }

  @override
  void dispose() {
    _monTimer?.cancel();
    _gwTimer?.cancel();
    _saveTimer?.cancel();
    try {
      ref.read(connectivityServiceProvider).stopMonitoring();
    } catch (_) {}
    super.dispose();
  }

  // ── root duties (this is the first screen after sign-in) ──
  Future<void> _maybeShowWalkthrough() async {
    if (await walkthroughSeen() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const WalkthroughScreen(),
      ),
    );
    await markWalkthroughSeen();
  }

  void _startGatewayPolling() {
    _gwTimer?.cancel();
    final secs = ref.read(settingsProvider).refreshSeconds;
    if (secs > 0)
      _gwTimer = Timer.periodic(
        Duration(seconds: secs),
        (_) => _pollGateways(),
      );
  }

  Future<void> _pollGateways() async {
    final notifier = ref.read(gatewaysProvider.notifier);
    await notifier.fetchAll();
    final notifications = ref.read(notificationServiceProvider);
    final prefs = ref.read(settingsProvider);
    for (final gw in ref.read(gatewaysProvider)) {
      notifications.reportOnline(
        'gw:${gw.id}',
        gw.online,
        gw.name,
        kind: 'Gateway',
        notifyOffline: prefs.notifyOffline,
        notifyOnline: prefs.notifyOnline,
      );
    }
  }

  void _checkConnectivity() {
    final api = ref.read(apiServiceProvider);
    final baseUrl = api.baseUrl;
    if (baseUrl != null) {
      ref
          .read(connectivityServiceProvider)
          .checkLocalConnectivity(Uri.parse(baseUrl).host);
    }
    final scaffold = ScaffoldMessenger.of(context);
    ref.read(connectivityServiceProvider).startMonitoring((isLocal) {
      ref.read(isLocalNetworkProvider.notifier).state = isLocal;
      if (!isLocal) {
        scaffold.showSnackBar(
          const SnackBar(
            content: Text('Left local network, using remote connection'),
          ),
        );
      }
    });
  }

  void _onBack() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    if (_customizing) {
      setState(() => _customizing = false);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      const SnackBar(
        content: Text('Press back again to exit the app'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _logout() async {
    _monTimer?.cancel();
    _gwTimer?.cancel();
    await ref.read(authServiceProvider).logout();
    ref.read(apiServiceProvider).clearToken();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  // ── data ──
  Future<void> _loadAll() async {
    ref.read(gatewaysProvider.notifier).fetchAll();
    await _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiServiceProvider).get('/api/monitor');
      final data = r.data as Map;
      final first = _loading;
      final list = [
        for (final w in (data['widgets'] as List))
          MonWidget(Map<String, dynamic>.from(w as Map)),
      ];
      if (first) {
        final p = Map<String, dynamic>.from(data['prefs'] as Map);
        _scope = p['gateway'] as String? ?? 'all';
        _hidden
          ..clear()
          ..addAll(((p['hidden'] as List?) ?? []).cast<String>());
        _order = ((p['order'] as List?) ?? []).cast<String>();
        _tileOrder.clear();
        ((p['tiles'] as Map?) ?? {}).forEach(
          (k, v) => _tileOrder[k as String] = (v as List).cast<String>(),
        );
      }
      for (final w in list) {
        w.hidden = _hidden.contains(w.id);
        final pat = w.params['pattern'];
        if (w.kind == 'light' && pat is num && pat != 0)
          _lastPattern[w.id] = '${pat.toInt()}';
      }
      if (!mounted) return;
      setState(() {
        _gateways = [
          for (final g in (data['gateways'] as List))
            Map<String, dynamic>.from(g as Map),
        ];
        _widgets = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        await ref
            .read(apiServiceProvider)
            .put(
              '/api/monitor/prefs',
              data: {
                'gateway': _scope,
                'hidden': _hidden.toList(),
                'order': _order,
                'tiles': _tileOrder,
              },
            );
      } catch (_) {}
    });
  }

  // ── derived ──
  List<MonWidget> get _inScope =>
      _widgets.where((w) => _scope == 'all' || w.gatewayId == _scope).toList();
  List<MonWidget> get _shown => _inScope.where((w) => !w.hidden).toList();

  List<_Card> get _cards {
    final list = _customizing ? _inScope : _shown;
    final map = <String, _Card>{};
    for (final w in list) {
      map.putIfAbsent(
        w.nodeId,
        () => _Card(w.nodeId, w.nodeName, w.gatewayName, w.online, []),
      );
      map[w.nodeId]!.widgets.add(w);
    }
    for (final c in map.values) {
      final pos = _tileOrder[c.id] ?? const [];
      int rank(MonWidget w) {
        final i = pos.indexOf(w.id);
        return i < 0 ? 1000000 : i;
      }

      c.widgets.sort((a, b) => rank(a) - rank(b));
    }
    int crank(_Card c) {
      final i = _order.indexOf(c.id);
      return i < 0 ? 1000000 : i;
    }

    return map.values.toList()..sort((a, b) => crank(a) - crank(b));
  }

  // ── arranging ──
  List<String> _moveBefore(List<String> list, String id, String target) {
    final from = list.indexOf(id), to = list.indexOf(target);
    if (from < 0 || to < 0 || from == to) return list;
    final next = [...list]..removeAt(from);
    next.insert(to, id);
    return next;
  }

  void _setCardOrder(List<String> ids) {
    _order = [...ids, ..._order.where((x) => !ids.contains(x))];
  }

  void _dropCard(String id, String onto) {
    setState(
      () => _setCardOrder(
        _moveBefore(_cards.map((c) => c.id).toList(), id, onto),
      ),
    );
    _save();
  }

  void _nudge(_Card c, int dir) {
    final ids = _cards.map((x) => x.id).toList();
    final i = ids.indexOf(c.id), j = i + dir;
    if (j < 0 || j >= ids.length) return;
    final t = ids[i];
    ids[i] = ids[j];
    ids[j] = t;
    setState(() => _setCardOrder(ids));
    _save();
  }

  void _dropTile(_Card c, String id, String onto) {
    setState(
      () => _tileOrder[c.id] = _moveBefore(
        c.widgets.map((w) => w.id).toList(),
        id,
        onto,
      ),
    );
    _save();
  }

  void _toggleHidden(MonWidget w) {
    setState(() {
      if (!_hidden.add(w.id)) _hidden.remove(w.id);
      w.hidden = _hidden.contains(w.id);
    });
    _save();
  }

  void _setScope(String id) {
    setState(() => _scope = id);
    _save();
  }

  // ── controls ──
  bool _isOn(MonWidget w) {
    final l = _local[w.id];
    return (l != null && l.fresh ? l.on : null) ?? w.on;
  }

  double _level(MonWidget w) {
    final l = _local[w.id];
    return (l != null && l.fresh ? l.value : null) ?? w.value;
  }

  void _fail(MonWidget w, Object e) {
    _local.remove(w.id);
    var msg = 'Could not send';
    try {
      final d = (e as dynamic).response?.data;
      if (d is Map && d['error'] != null) msg = '${d['error']}';
    } catch (_) {}
    setState(() => _errs[w.id] = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _errs.remove(w.id));
    });
  }

  Future<void> _toggle(MonWidget w) async {
    final on = !_isOn(w);
    setState(() => _local[w.id] = _Local(on: on, value: w.value));
    final api = ref.read(apiServiceProvider);
    try {
      if (w.kind == 'switch') {
        await api.post(
          '/api/nodes/${w.nodeId}/command',
          data: {'pin': w.pin, 'value': on ? 1 : 0},
        );
      } else {
        final params = w.params;
        params['pattern'] = on
            ? (int.tryParse(_lastPattern[w.id] ?? '') ?? 1)
            : 0;
        await api.post(
          '/api/nodes/${w.nodeId}/action',
          data: {'cap': w.cap, 'action': 'setEffect', 'params': params},
        );
      }
    } catch (e) {
      _fail(w, e);
    }
  }

  Future<void> _commit(MonWidget w, double v) async {
    setState(
      () => _local[w.id] = _Local(
        on: w.kind == 'slider' ? v > 0 : true,
        value: v,
      ),
    );
    final api = ref.read(apiServiceProvider);
    try {
      if (w.kind == 'slider') {
        await api.post(
          '/api/nodes/${w.nodeId}/command',
          data: {'pin': w.pin, 'value': v.round()},
        );
      } else {
        final params = w.params..['brightness'] = v.round();
        if ((params['pattern'] as num?) == null || params['pattern'] == 0) {
          params['pattern'] = int.tryParse(_lastPattern[w.id] ?? '') ?? 1;
        }
        await api.post(
          '/api/nodes/${w.nodeId}/action',
          data: {'cap': w.cap, 'action': 'setEffect', 'params': params},
        );
      }
    } catch (e) {
      _fail(w, e);
    }
  }

  Future<void> _buzz(MonWidget w, int pattern) async {
    try {
      await ref
          .read(apiServiceProvider)
          .post(
            '/api/nodes/${w.nodeId}/action',
            data: {
              'cap': w.cap,
              'action': 'play',
              'params': {'pattern': pattern, 'repeat': 1},
            },
          );
    } catch (e) {
      _fail(w, e);
    }
  }

  // ── look ──
  Color _tint(MonWidget w, AppColors c) {
    if (w.kind == 'light' && w.color.startsWith('#') && w.color.length == 7) {
      final v = int.tryParse(w.color.substring(1), radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    const t = {
      'thermometer': Color(0xFFF0883E),
      'flame': Color(0xFFF85149),
      'droplet': Color(0xFF4AA3FF),
      'waves': Color(0xFF4AA3FF),
      'cloudrain': Color(0xFF4AA3FF),
      'radar': Color(0xFFA371F7),
      'eye': Color(0xFFA371F7),
      'gauge': Color(0xFF3FB950),
      'leaf': Color(0xFF3FB950),
      'sun': Color(0xFFE3B341),
      'lightbulb': Color(0xFFE3B341),
      'bell': Color(0xFFE3B341),
      'clock': Color(0xFF58A6FF),
    };
    return t[w.symbol] ?? c.accent;
  }

  String _fmt(double v) => (v.abs() >= 100 || v == v.roundToDouble())
      ? v.round().toString()
      : v.toStringAsFixed(1);

  String _boolText(MonWidget w) {
    if (!w.hasValue) return '--';
    if (w.symbol == 'radar' || w.symbol == 'eye')
      return w.on ? 'Detected' : 'Clear';
    return w.on ? 'Active' : 'Inactive';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isLocal = ref.watch(isLocalNetworkProvider);
    ref.listen(
      settingsProvider.select((s) => s.refreshSeconds),
      (_, __) => _startGatewayPolling(),
    );
    final cards = _cards;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: MfaApprovalHost(
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: c.bg,
          drawer: AppDrawer(
            current: DrawerPage.dashboard,
            onLogout: _logout,
            onRefresh: _loadAll,
          ),
          appBar: AppBar(
            backgroundColor: c.card,
            iconTheme: IconThemeData(color: c.text),
            title: Text(
              'Dashboard',
              style: TextStyle(color: c.text, fontWeight: FontWeight.bold),
            ),
            actions: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (isLocal ? c.okStrong : c.bad).withValues(
                      alpha: 0.2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLocal ? Icons.wifi : Icons.cloud,
                        size: 14,
                        color: isLocal ? c.ok : c.bad,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isLocal ? 'LAN' : 'Remote',
                        style: TextStyle(
                          fontSize: 11,
                          color: isLocal ? c.ok : c.bad,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: _customizing ? 'Done' : 'Customise',
                icon: Icon(
                  _customizing
                      ? Icons.check_circle
                      : Icons.dashboard_customize_outlined,
                  color: _customizing ? c.accent : c.muted,
                ),
                onPressed: () => setState(() => _customizing = !_customizing),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(Icons.refresh, color: c.muted),
                onPressed: _loadAll,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadAll,
            child: LayoutBuilder(
              builder: (ctx, box) => _body(ctx, box.maxWidth, cards),
            ),
          ),
        ),
      ),
    );
  }

  // Tile slots a card takes in a row (at most 3, never more than the row has).
  int _slots(_Card c, int k) => c.widgets.length.clamp(1, 3 > k ? k : 3);

  Widget _body(BuildContext context, double width, List<_Card> cards) {
    final c = context.c;
    const sp = 12.0, gap = 10.0;
    final k = ((width - 2 * sp) / 175).floor().clamp(
      2,
      6,
    ); // tile slots per row

    // Pack cards into rows; every row is stretched to the full width and the
    // cards share it in proportion to their tiles, so the rows balance.
    final rows = <List<_Card>>[];
    var used = 0;
    for (final card in cards) {
      final s = _slots(card, k);
      if (rows.isEmpty || used + s > k) {
        rows.add([]);
        used = 0;
      }
      rows.last.add(card);
      used += s;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(sp, 12, sp, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _hero(c),
        const SizedBox(height: 14),
        if (_gateways.isNotEmpty) _tabs(c),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_gateways.isEmpty)
          _empty(
            c,
            Icons.router_outlined,
            'No gateways yet',
            'Add a gateway from the Gateways page. Everything that can be watched or controlled shows up here.',
          )
        else if (cards.isEmpty)
          _empty(
            c,
            Icons.visibility_off_outlined,
            'Nothing to show',
            _inScope.isNotEmpty
                ? 'Everything is hidden. Use Customise to bring tiles back.'
                : 'None of the paired nodes has a module that can be monitored or controlled yet.',
          )
        else ...[
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      Expanded(
                        flex: _slots(row[i], k),
                        child: _cardView(c, row[i], _slots(row[i], k), gap),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_customizing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Drag the grip on a card, or long-press a tile, to rearrange. The arrows move a card and the eye hides or shows a tile. Changes are saved automatically. Pick a symbol for a module in the node settings.',
                style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ],
    );
  }

  int min(int a, int b) => a < b ? a : b;

  Widget _hero(AppColors c) {
    final online = _gateways.where((g) => g['online'] == true).length;
    final nodes = _gateways.fold<int>(
      0,
      (a, g) => a + ((g['nodes'] as num?)?.toInt() ?? 0),
    );
    final onlineNodes = _gateways.fold<int>(
      0,
      (a, g) => a + ((g['onlineNodes'] as num?)?.toInt() ?? 0),
    );
    final h = DateTime.now().hour;
    final hello = h < 5
        ? 'Good night'
        : h < 12
        ? 'Good morning'
        : h < 18
        ? 'Good afternoon'
        : 'Good evening';
    Widget stat(IconData i, String v, String l) => Expanded(
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(i, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  l,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [c.primary, c.accent2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.3),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hello,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Your home, live',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat(
                Icons.router_outlined,
                '$online/${_gateways.length}',
                'Gateways',
              ),
              stat(Icons.memory, '$onlineNodes/$nodes', 'Nodes'),
              stat(Icons.layers_outlined, '${_shown.length}', 'Tiles'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabs(AppColors c) {
    Widget chip(String id, String label, {bool? online, int? count}) {
      final sel = _scope == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: sel,
          showCheckmark: false,
          onSelected: (_) => _setScope(id),
          backgroundColor: c.card,
          selectedColor: c.primary,
          side: BorderSide(color: sel ? c.primary : c.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (online != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online ? c.ok : c.subtle,
                  ),
                ),
                const SizedBox(width: 6),
              ] else ...[
                Icon(
                  Icons.layers_outlined,
                  size: 16,
                  color: sel ? Colors.white : c.muted,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: sel ? Colors.white : c.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    color: sel ? Colors.white70 : c.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('all', 'All gateways', count: _gateways.length),
          for (final g in _gateways)
            chip(
              g['id'] as String,
              g['name'] as String? ?? '',
              online: g['online'] == true,
              count: (g['nodes'] as num?)?.toInt(),
            ),
        ],
      ),
    );
  }

  Widget _empty(AppColors c, IconData icon, String title, String text) =>
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 52, color: c.accent),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4),
            ),
          ],
        ),
      );

  // ── node card ──
  Widget _cardView(AppColors c, _Card card, int cols, double gap) {
    final rows = <List<MonWidget>>[];
    for (var i = 0; i < card.widgets.length; i += cols) {
      rows.add(
        card.widgets.sublist(
          i,
          i + cols > card.widgets.length ? card.widgets.length : i + cols,
        ),
      );
    }
    final body = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: c.card,
        border: Border.all(
          color: card.online ? c.accent.withValues(alpha: 0.4) : c.border,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(c, card, 0),
          const SizedBox(height: 10),
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(child: _tileSlot(c, card, rows[r][i])),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    if (!_customizing) return body;
    return DragTarget<_CardDrag>(
      onWillAcceptWithDetails: (d) => d.data.id != card.id,
      onAcceptWithDetails: (d) => _dropCard(d.data.id, card.id),
      builder: (ctx, cand, _) => Container(
        foregroundDecoration: cand.isNotEmpty
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.accent, width: 2.5),
              )
            : null,
        child: body,
      ),
    );
  }

  Widget _cardHeader(AppColors c, _Card card, double w) {
    final title = Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: card.online ? c.ok : c.subtle,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
    final sub = [
      if (_scope == 'all') card.gatewayName,
      if (!card.online) 'Offline',
    ].join(' · ');
    return Row(
      children: [
        if (_customizing)
          Draggable<_CardDrag>(
            data: _CardDrag(card.id),
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(blurRadius: 18, color: Colors.black38),
                  ],
                ),
                child: Text(
                  card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            childWhenDragging: Icon(Icons.drag_indicator, color: c.subtle),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.drag_indicator, color: c.muted),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 1),
                  child: Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        if (_customizing) ...[
          _tiny(c, Icons.chevron_left, () => _nudge(card, -1)),
          _tiny(c, Icons.chevron_right, () => _nudge(card, 1)),
        ],
      ],
    );
  }

  Widget _tiny(AppColors c, IconData i, VoidCallback f) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: f,
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Icon(i, size: 20, color: c.muted),
    ),
  );

  Widget _tileSlot(AppColors c, _Card card, MonWidget t) {
    final tile = _tile(c, t);
    if (!_customizing) return tile;
    return DragTarget<_TileDrag>(
      onWillAcceptWithDetails: (d) =>
          d.data.node == card.id && d.data.id != t.id,
      onAcceptWithDetails: (d) => _dropTile(card, d.data.id, t.id),
      builder: (ctx, cand, _) => LongPressDraggable<_TileDrag>(
        data: _TileDrag(t.id, card.id),
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.92,
            child: SizedBox(width: 160, child: _tile(c, t)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: cand.isNotEmpty ? c.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: tile,
        ),
      ),
    );
  }

  // ── tile ──
  Widget _tile(AppColors c, MonWidget w) {
    final tint = _tint(w, c);
    final on = _isOn(w);
    final enabled = w.online && !_customizing;

    Widget trailing = (w.history && !_customizing && w.kind == 'gauge')
        ? Icon(Icons.show_chart, size: 20, color: c.muted)
        : const SizedBox.shrink();
    if (_customizing) {
      trailing = InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleHidden(w),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            w.hidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
            color: c.text,
          ),
        ),
      );
    } else if (w.kind == 'switch' || w.kind == 'light') {
      trailing = Transform.scale(
        scale: 0.85,
        child: Switch(
          value: on,
          activeTrackColor: tint,
          activeThumbColor: Colors.white,
          inactiveTrackColor: c.border,
          inactiveThumbColor: Colors.white,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          onChanged: enabled ? (_) => _toggle(w) : null,
        ),
      );
    } else if (w.kind == 'bool') {
      trailing = Transform.scale(
        scale: 0.85,
        child: Switch(
          value: on,
          activeTrackColor: tint,
          activeThumbColor: Colors.white,
          inactiveTrackColor: c.border,
          inactiveThumbColor: Colors.white,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          onChanged: null,
        ),
      );
    }

    Widget bodyW;
    switch (w.kind) {
      case 'gauge':
        final frac = w.hasValue && w.max > w.min
            ? ((w.value - w.min) / (w.max - w.min)).clamp(0.0, 1.0)
            : 0.0;
        bodyW = Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: const Duration(milliseconds: 600),
                    builder: (_, v, __) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      color: tint,
                      backgroundColor: c.border.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      w.hasValue ? _fmt(w.value) : '--',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (w.unit.isNotEmpty)
                      Text(
                        w.unit,
                        style: TextStyle(color: c.muted, fontSize: 10),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      case 'text':
        bodyW = Text(
          w.hasValue ? w.text : '--',
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        );
      case 'bool':
        bodyW = Text(
          _boolText(w),
          style: TextStyle(
            color: c.text,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        );
      case 'switch':
        final l = _local[w.id];
        final unknown = !w.hasValue && !(l != null && l.fresh);
        bodyW = Text(
          unknown ? 'Unknown' : (on ? 'On' : 'Off'),
          style: TextStyle(
            color: c.text,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        );
      case 'slider':
        final v = _level(w).clamp(0, 255).toDouble();
        bodyW = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(v / 255 * 100).round()}%',
              style: TextStyle(
                color: c.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            _slider(c, tint, v, 0, 255, enabled, w),
          ],
        );
      case 'light':
        final v = _level(w).clamp(1, 100).toDouble();
        bodyW = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              on ? (w.pattern.isEmpty ? 'On' : w.pattern) : 'Off',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            _slider(c, tint, v, 1, 100, enabled, w),
          ],
        );
      case 'buzzer':
        bodyW = Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tint,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: enabled ? () => _buzz(w, 1) : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Play'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: enabled ? () => _buzz(w, 0) : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stop'),
              ),
            ),
          ],
        );
      default:
        bodyW = const SizedBox.shrink();
    }

    final tileBody = Opacity(
      opacity: w.hidden ? 0.4 : (w.online ? 1 : 0.55),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: on
              ? Color.alphaBlend(tint.withValues(alpha: 0.14), c.bg)
              : c.bg,
          border: Border.all(
            color: on ? tint.withValues(alpha: 0.5) : c.border,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: on ? tint : tint.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: on
                            ? [
                                BoxShadow(
                                  color: tint.withValues(alpha: 0.5),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        symbolIcon(w.symbol),
                        size: 21,
                        color: on ? Colors.white : tint,
                      ),
                    ),
                    SizedBox(height: 32, child: FittedBox(child: trailing)),
                  ],
                ),
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: bodyW),
                ),
                Text(
                  w.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (w.module != w.label &&
                    !w.label.toLowerCase().contains(
                      w.module.toLowerCase().split(" ").first,
                    ))
                  Text(
                    w.module,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
              ],
            ),
            if (_errs[w.id] != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.bad.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errs[w.id]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.bad, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (!w.history || _customizing) return tileBody;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HistoryScreen(
            nodeId: w.nodeId,
            cap: w.cap,
            channel: w.channel,
            label: w.label,
            subtitle: '${w.nodeName} · ${w.gatewayName}',
            unit: w.unit,
            symbol: w.symbol,
            tint: tint,
            binary: w.kind == 'bool',
          ),
        ),
      ),
      child: tileBody,
    );
  }

  Widget _slider(
    AppColors c,
    Color tint,
    double v,
    double mn,
    double mx,
    bool enabled,
    MonWidget w,
  ) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 5,
        activeTrackColor: tint,
        thumbColor: Colors.white,
        inactiveTrackColor: c.border,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: v.clamp(mn, mx),
        min: mn,
        max: mx,
        onChanged: enabled
            ? (x) => setState(
                () => _local[w.id] = _Local(
                  on: w.kind == 'slider' ? x > 0 : _isOn(w),
                  value: x,
                ),
              )
            : null,
        onChangeEnd: enabled ? (x) => _commit(w, x) : null,
      ),
    );
  }
}
