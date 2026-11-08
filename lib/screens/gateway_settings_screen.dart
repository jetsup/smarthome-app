import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';

class _WifiCred {
  final int id;
  final String slug;
  final String ssid;
  final String password;
  _WifiCred({
    required this.id,
    required this.slug,
    required this.ssid,
    required this.password,
  });
  factory _WifiCred.fromJson(Map<String, dynamic> j) => _WifiCred(
    id: j['id'] as int? ?? 0,
    slug: j['slug'] as String? ?? '',
    ssid: j['ssid'] as String? ?? '',
    password: j['password'] as String? ?? '',
  );
}

class GatewaySettingsScreen extends ConsumerStatefulWidget {
  final String gatewayId;
  const GatewaySettingsScreen({super.key, required this.gatewayId});

  @override
  ConsumerState<GatewaySettingsScreen> createState() =>
      _GatewaySettingsScreenState();
}

class _GatewaySettingsScreenState extends ConsumerState<GatewaySettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _savingName = false;
  bool _saving = false;
  bool _showPass = false;
  List<_WifiCred> _credentials = [];
  bool _loadingCreds = false;
  bool _nameLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCredentials());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String get _base => '/api/gateways/${widget.gatewayId}';

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? context.c.badStrong : null,
      ),
    );
  }

  Future<void> _fetchCredentials() async {
    if (!mounted) return;
    setState(() => _loadingCreds = true);
    try {
      final response = await ref.read(apiServiceProvider).get('$_base/wifi');
      final list = (response.data as List?) ?? [];
      _credentials = list
          .map((j) => _WifiCred.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    if (mounted) setState(() => _loadingCreds = false);
  }

  // ── Restart all nodes ──────────────────────────────────────────────────────
  bool _restarting = false;
  Future<void> _restartNodes() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.c.card,
        title: Text('Restart all nodes?', style: TextStyle(color: ctx.c.text)),
        content: Text(
          'Every node on this gateway restarts for a few seconds. Their settings and pairing are kept.',
          style: TextStyle(color: ctx.c.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restart')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _restarting = true);
    try {
      final r = await ref.read(apiServiceProvider).post('$_base/restart-nodes');
      final n = (r.data is Map ? (r.data as Map)['count'] : null) ?? 0;
      _toast(n == 0 ? 'This gateway has no nodes yet.' : 'Restarting $n node${n == 1 ? '' : 's'}…');
    } catch (e) {
      _toast(_errorText(e, 'Could not restart the nodes. Is the gateway online?'), error: true);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  // ── Gateway name ───────────────────────────────────────────────────────────
  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('Give the gateway a name', error: true);
      return;
    }
    setState(() => _savingName = true);
    try {
      await ref.read(apiServiceProvider).put(_base, data: {'name': name});
      await ref.read(gatewaysProvider.notifier).fetchAll();
      _toast('Renamed. The gateway and any paired HMI will show “$name”.');
    } catch (_) {
      _toast('Could not rename the gateway', error: true);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  // ── Saved networks ─────────────────────────────────────────────────────────
  Future<void> _saveWifi({required bool connectNow}) async {
    final ssid = _ssidCtrl.text.trim();
    if (ssid.isEmpty) {
      _toast('Enter the network name', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(apiServiceProvider)
          .post(
            '$_base/wifi',
            data: {
              'ssid': ssid,
              'password': _passCtrl.text,
              'connectNow': connectNow,
            },
          );
      _ssidCtrl.clear();
      _passCtrl.clear();
      await _fetchCredentials();
      _toast(
        connectNow
            ? 'Saved — the gateway is switching to “$ssid”.'
            : 'Saved at the bottom of the list. The gateway uses it when higher ones are not available.',
      );
    } catch (e) {
      _toast(_errorText(e, 'Failed to save the network'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorText(Object e, String fallback) {
    final s = '$e';
    final m = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(s);
    return m?.group(1) ?? fallback;
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final before = List<_WifiCred>.from(_credentials);
    setState(() {
      final item = _credentials.removeAt(oldIndex);
      _credentials.insert(newIndex, item);
    });
    try {
      await ref
          .read(apiServiceProvider)
          .put(
            '$_base/wifi/order',
            data: {'ids': _credentials.map((c) => c.id).toList()},
          );
      _toast('Priority updated — the gateway uses this order at start-up.');
    } catch (_) {
      if (mounted) setState(() => _credentials = before);
      _toast('Could not change the order', error: true);
    }
  }

  Future<void> _deleteCred(_WifiCred cred) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget this network?'),
        content: Text('The gateway will no longer connect to “${cred.ssid}”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Forget', style: TextStyle(color: ctx.c.bad)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete('$_base/wifi/${cred.slug}');
      await _fetchCredentials();
      _toast('Network forgotten');
    } catch (_) {
      _toast('Failed to delete the network', error: true);
    }
  }

  String _maskPass(String pass) =>
      pass.isEmpty ? 'Open network' : '${pass[0]}••••••';

  // ── UI ─────────────────────────────────────────────────────────────────────
  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: context.c.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.c.border),
    ),
    child: child,
  );

  Widget _heading(String title, [String? sub]) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              sub,
              style: TextStyle(color: context.c.muted, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: context.c.muted),
    filled: true,
    fillColor: context.c.bg,
    suffixIcon: suffix,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.c.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.c.accent),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final gateways = ref.watch(gatewaysProvider);
    final gw = gateways.where((g) => g.id == widget.gatewayId).firstOrNull;
    if (gw != null && !_nameLoaded) {
      _nameCtrl.text = gw.name;
      _nameLoaded = true;
    }
    final nameChanged = gw != null && _nameCtrl.text.trim() != gw.name;

    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.card,
        title: Text(
          '${gw?.name ?? 'Gateway'} settings',
          style: TextStyle(color: context.c.text),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Name ──
          _heading(
            'Gateway name',
            'Shown in the app, on the web and on the HMI display.',
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameCtrl,
                  maxLength: 40,
                  style: TextStyle(color: context.c.text),
                  onChanged: (_) => setState(() {}),
                  decoration: _dec('Name'),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_savingName || !nameChanged) ? null : _saveName,
                    child: _savingName
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save name'),
                  ),
                ),
              ],
            ),
          ),

          // ── Nodes ──
          _heading('Nodes', 'Actions for every node on this gateway.'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restarting reboots each node. Pairing and saved settings are kept.',
                  style: TextStyle(color: context.c.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _restarting ? null : _restartNodes,
                    icon: _restarting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.restart_alt),
                    label: const Text('Restart all nodes'),
                  ),
                ),
              ],
            ),
          ),

          // ── Saved networks ──
          _heading(
            'Wi-Fi networks',
            'The gateway remembers these and, at start-up, joins the highest one that is in range. Drag to change the priority.',
          ),
          if (_loadingCreds)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.c.accent,
                ),
              ),
            )
          else if (_credentials.isEmpty)
            _card(
              child: Center(
                child: Text(
                  'No saved networks.',
                  style: TextStyle(color: context.c.muted),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: context.c.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.c.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _credentials.length,
                onReorderItem: _reorder,
                proxyDecorator: (child, i, anim) =>
                    Material(color: context.c.card, elevation: 4, child: child),
                itemBuilder: (context, i) {
                  final cred = _credentials[i];
                  return Container(
                    key: ValueKey(cred.id),
                    decoration: BoxDecoration(
                      border: i == _credentials.length - 1
                          ? null
                          : Border(
                              bottom: BorderSide(color: context.c.divider),
                            ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: i == 0
                            ? context.c.accent
                            : context.c.divider,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: i == 0 ? Colors.white : context.c.text,
                          ),
                        ),
                      ),
                      title: Text(
                        cred.ssid,
                        style: TextStyle(
                          color: context.c.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${i == 0 ? 'Preferred · ' : ''}${_maskPass(cred.password)}',
                        style: TextStyle(color: context.c.muted, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Forget',
                            icon: Icon(
                              Icons.delete_outline,
                              color: context.c.bad,
                              size: 20,
                            ),
                            onPressed: () => _deleteCred(cred),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Icon(
                              Icons.drag_handle,
                              color: context.c.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // ── Add ──
          _heading('Add a network'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _ssidCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(color: context.c.text),
                  decoration: _dec('Network name (SSID)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: !_showPass,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(color: context.c.text),
                  decoration: _dec(
                    'Password',
                    suffix: IconButton(
                      icon: Icon(
                        _showPass ? Icons.visibility_off : Icons.visibility,
                        color: context.c.muted,
                      ),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _saveWifi(connectNow: false),
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
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => _saveWifi(connectNow: true),
                    child: const Text('Save and switch the gateway to it now'),
                  ),
                ),
                Text(
                  'New networks go to the bottom of the list. Drag them up to make them preferred.',
                  style: TextStyle(color: context.c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
