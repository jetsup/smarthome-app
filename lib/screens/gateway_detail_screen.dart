import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../models/node.dart';
import 'gateway_settings_screen.dart';
import 'node_detail_screen.dart';
import '../services/api_errors.dart';
import '../services/catalog.dart';
import '../theme/app_colors.dart';
import '../widgets/capability_editor.dart';
import '../widgets/node_code_scanner.dart';

class GatewayDetailScreen extends ConsumerStatefulWidget {
  final String gatewayId;
  const GatewayDetailScreen({super.key, required this.gatewayId});

  @override
  ConsumerState<GatewayDetailScreen> createState() =>
      _GatewayDetailScreenState();
}

class _GatewayDetailScreenState extends ConsumerState<GatewayDetailScreen> {
  Timer? _pollTimer;
  List<Map<String, dynamic>> _discovered = [];
  bool _scanning = false;
  final Set<int> _provisioningIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  Future<void> _load() async {
    await ref.read(gatewaysProvider.notifier).fetchOne(widget.gatewayId);
    await ref.read(nodesProvider(widget.gatewayId).notifier).fetchNodes();
    await _fetchDiscovered();
  }

  Future<void> _poll() async {
    final notifier = ref.read(nodesProvider(widget.gatewayId).notifier);
    await notifier.fetchNodes();
    final nodes = ref.read(nodesProvider(widget.gatewayId));
    final notifications = ref.read(notificationServiceProvider);

    final prefs = ref.read(settingsProvider);
    for (final n in nodes) {
      notifications.reportOnline(
        'node:${widget.gatewayId}:${n.deviceId}',
        n.isOnline,
        'Device ${n.deviceId} (${n.typeLabel})',
        kind: 'Node',
        notifyOffline: prefs.notifyOffline,
        notifyOnline: prefs.notifyOnline,
      );
    }

    final gw = ref
        .read(gatewaysProvider)
        .where((g) => g.id == widget.gatewayId)
        .firstOrNull;
    if (gw != null) {
      _pollGw(gw);
    }

    await _fetchDiscovered();
  }

  void _pollGw(gateway) {
    final prefs = ref.read(settingsProvider);
    ref.read(notificationServiceProvider).reportOnline(
      'gw:${widget.gatewayId}',
      gateway.online,
      gateway.name,
      kind: 'Gateway',
      notifyOffline: prefs.notifyOffline,
      notifyOnline: prefs.notifyOnline,
    );
  }

  Future<void> _fetchDiscovered() async {
    final api = ref.read(apiServiceProvider);
    try {
      final response = await api.get(
        '/api/gateways/${widget.gatewayId}/discovered',
      );
      _discovered = (response.data as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _scan() async {
    final api = ref.read(apiServiceProvider);
    setState(() => _scanning = true);
    try {
      await api.post('/api/gateways/${widget.gatewayId}/scan');
      await Future.delayed(const Duration(seconds: 3));
      await _fetchDiscovered();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Scan complete')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _provision(
    int deviceId,
    String name,
    List<Map<String, dynamic>> caps, {
    String code = '',
    String adoptCode = '',
  }) async {
    final api = ref.read(apiServiceProvider);
    setState(() => _provisioningIds.add(deviceId));
    void say(String m) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }

    try {
      final r = await api.post(
        '/api/gateways/${widget.gatewayId}/provision',
        data: {
          'deviceId': deviceId,
          'name': name,
          'capabilitiesConfig': caps,
          if (code.isNotEmpty) 'code': code,
          if (adoptCode.isNotEmpty) 'adoptCode': adoptCode,
        },
      );
      final status =
          (r.data is Map ? (r.data as Map)['status'] : null) as String?;
      if (status == 'registered_but_offline') {
        say(
          'The gateway is offline, so the node could not be reached. Bring the gateway online and try again.',
        );
        return;
      }
      say('Sending settings to node $deviceId…');
      // Keep the node "in progress" until it reports in (or give up after ~45 s).
      for (var i = 0; i < 22 && mounted; i++) {
        await Future.delayed(const Duration(seconds: 2));
        await ref.read(nodesProvider(widget.gatewayId).notifier).fetchNodes();
        final linked = ref
            .read(nodesProvider(widget.gatewayId))
            .any((n) => n.deviceId == deviceId);
        if (linked) {
          say('Node $deviceId connected');
          return;
        }
      }
      say(
        'Node $deviceId did not report in. Check that it is powered and within range of the gateway, then try again.',
      );
    } catch (e) {
      say('Could not add the node: ${apiError(e, 'request failed')}');
    } finally {
      if (mounted) setState(() => _provisioningIds.remove(deviceId));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gateways = ref.watch(gatewaysProvider);
    final gw = gateways.where((g) => g.id == widget.gatewayId).firstOrNull;
    final nodes = ref.watch(nodesProvider(widget.gatewayId));

    final linkedDeviceIds = nodes.map((n) => n.deviceId).toSet();
    final unlinked = _discovered.where((d) {
      final did = d['deviceId'] as int? ?? 0;
      // A node the hub still has saved but that was reset shows up again here.
      final known = d['known'] == true;
      return (!linkedDeviceIds.contains(did) || known) &&
          !_provisioningIds.contains(did);
    }).toList();

    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.card,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.c.muted),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          gw?.name ?? 'Gateway',
          style: TextStyle(color: context.c.text),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: context.c.muted),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      GatewaySettingsScreen(gatewayId: widget.gatewayId),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: context.c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: context.c.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusDot(gw?.online ?? false),
                        const SizedBox(width: 8),
                        Text(
                          gw?.online == true ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: gw?.online == true
                                ? context.c.ok
                                : context.c.bad,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'ID: ${gw?.id ?? ''}',
                          style: TextStyle(
                            color: context.c.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statBox('Nodes', '${nodes.length}'),
                        const SizedBox(width: 12),
                        _statBox(
                          'Online',
                          '${nodes.where((n) => n.isOnline).length}',
                        ),
                        const SizedBox(width: 12),
                        _statBox('Discovered', '${unlinked.length}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Linked nodes section
            Row(
              children: [
                Text(
                  'Nodes',
                  style: TextStyle(
                    color: context.c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.c.accent,
                          ),
                        )
                      : Icon(
                          Icons.wifi_find,
                          color: context.c.accent,
                          size: 18,
                        ),
                  label: Text(
                    _scanning ? 'Scanning…' : 'Scan',
                    style: TextStyle(color: context.c.accent, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (nodes.isEmpty && unlinked.isEmpty)
              Card(
                color: context.c.card,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No nodes. Scan for nearby devices.',
                      style: TextStyle(color: context.c.muted),
                    ),
                  ),
                ),
              )
            else ...[
              ...nodes.map((n) => _NodeCard(n, widget.gatewayId)),
              if (unlinked.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Discovered',
                  style: TextStyle(
                    color: context.c.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ...unlinked.map(
                  (d) => _DiscoveredCard(d, _provisioningIds, () {
                    final did = d['deviceId'] as int;
                    if (d['known'] == true) {
                      _provision(did, '', const []); // saved settings are reused
                    } else {
                      _showProvisionDialog(did, paired: d['paired'] == true);
                    }
                  }),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showProvisionDialog(int deviceId, {bool paired = false}) async {
    CapCatalog catalog;
    try {
      catalog = await ref.read(capCatalogProvider.future);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load the module list. Try again.'),
          ),
        );
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProvisionDialog(
        catalog: catalog,
        deviceId: deviceId,
        paired: paired,
        onProvision: (name, caps, code, adoptCode) {
          Navigator.of(ctx).pop();
          _provision(deviceId, name, adoptCode.isNotEmpty ? const [] : caps,
              code: code, adoptCode: adoptCode);
        },
      ),
    );
  }

  Widget _statusDot(bool online) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: online ? context.c.ok : context.c.subtle,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.c.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.c.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: context.c.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label, style: TextStyle(color: context.c.muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Set<int> provisioningIds;
  final VoidCallback onConnect;

  const _DiscoveredCard(this.data, this.provisioningIds, this.onConnect);

  @override
  Widget build(BuildContext context) {
    final did = data['deviceId'] as int? ?? 0;
    final provisioning = provisioningIds.contains(did);
    return Card(
      color: context.c.card,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: provisioning ? context.c.accent : context.c.border,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          'Device $did',
          style: TextStyle(color: context.c.text, fontSize: 14),
        ),
        subtitle: data['known'] == true
            ? Text(
                'Was reset, saved as “${data['knownName'] ?? ''}”. Re-pair to restore it.',
                style: TextStyle(color: context.c.muted, fontSize: 12),
              )
            : const Row(children: [_DiscBadge()]),
        trailing: provisioning
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.c.accent,
                ),
              )
            : TextButton(
                onPressed: onConnect,
                child: Text(
                  data['known'] == true ? 'Re-pair' : 'Connect',
                  style: TextStyle(color: context.c.accent, fontSize: 13),
                ),
              ),
      ),
    );
  }
}

class _DiscBadge extends StatelessWidget {
  const _DiscBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.c.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Discovered',
        style: TextStyle(
          fontSize: 10,
          color: context.c.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProvisionDialog extends StatefulWidget {
  final CapCatalog catalog;
  final int deviceId;
  final bool paired; // already paired to a gateway: its code is needed
  final void Function(String name, List<Map<String, dynamic>> caps, String code, String adoptCode) onProvision;

  const _ProvisionDialog({
    required this.catalog,
    required this.deviceId,
    required this.paired,
    required this.onProvision,
  });

  @override
  State<_ProvisionDialog> createState() => _ProvisionDialogState();
}

class _ProvisionDialogState extends State<_ProvisionDialog> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _adoptCtrl = TextEditingController();
  late final List<CapEntry> _caps = [
    CapEntry(widget.catalog.of('digitalOutput') ?? widget.catalog.types.first),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: context.c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.c.border),
      ),
      title: Text(
        'Provision Device ${widget.deviceId}',
        style: TextStyle(color: context.c.text, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.paired) ...[
                _fieldLabel('Pairing code'),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: _darkField(
                      child: TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 16,
                        style: TextStyle(color: context.c.text, fontSize: 14, letterSpacing: 2),
                        decoration: _inputDec('8 letters and digits').copyWith(counterText: ''),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Scan QR code',
                    icon: Icon(Icons.qr_code_scanner, color: context.c.accent),
                    onPressed: () async {
                      final code = await scanNodeCode(context);
                      if (code != null && mounted) setState(() => _codeCtrl.text = code);
                    },
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  'This node is already paired to a gateway. Enter its code, or scan the QR code from its Settings screen, to move it here.',
                  style: TextStyle(color: context.c.muted, fontSize: 11),
                ),
                const SizedBox(height: 16),
              ],
              _fieldLabel('Take over a previous node (optional)'),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: _darkField(
                    child: TextField(
                      controller: _adoptCtrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 16,
                      style: TextStyle(color: context.c.text, fontSize: 14, letterSpacing: 2),
                      decoration: _inputDec('Code of the node it replaces').copyWith(counterText: ''),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Scan QR code',
                  icon: Icon(Icons.qr_code_scanner, color: context.c.accent),
                  onPressed: () async {
                    final code = await scanNodeCode(context);
                    if (code != null && mounted) setState(() => _adoptCtrl.text = code);
                  },
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                'Copies that node’s name, modules, display and rules. Its modules are used instead of the ones below.',
                style: TextStyle(color: context.c.muted, fontSize: 11),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Node Name'),
              const SizedBox(height: 4),
              _darkField(
                child: TextField(
                  controller: _nameCtrl,
                  style: TextStyle(color: context.c.text, fontSize: 14),
                  decoration: _inputDec('e.g. Living Room Sensor'),
                ),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Capabilities'),
              const SizedBox(height: 4),
              CapabilityEditor(catalog: widget.catalog, entries: _caps),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: context.c.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: context.c.okStrong),
          onPressed: () {
            final caps = _caps.map((c) => c.toMap()).toList();
            widget.onProvision(_nameCtrl.text, caps, _codeCtrl.text.trim(), _adoptCtrl.text.trim());
          },
          child: const Text('Confirm', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: context.c.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _darkField({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.c.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: context.c.subtle, fontSize: 12),
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      isDense: true,
    );
  }
}

class _NodeCard extends StatelessWidget {
  final SmartNode node;
  final String gatewayId;
  const _NodeCard(this.node, this.gatewayId);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.c.card,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.c.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          node.displayName,
          style: TextStyle(color: context.c.text, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            _badge(
              context,
              node.isOnline ? 'Online' : 'Offline',
              node.isOnline,
            ),
            const SizedBox(width: 8),
            Text(
              node.typeLabel,
              style: TextStyle(color: context.c.muted, fontSize: 11),
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: context.c.subtle),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  NodeDetailScreen(node: node, gatewayId: gatewayId),
            ),
          );
        },
      ),
    );
  }

  Widget _badge(BuildContext context, String label, bool online) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: online
            ? context.c.okStrong.withValues(alpha: 0.2)
            : context.c.subtle.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: online ? context.c.ok : context.c.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
