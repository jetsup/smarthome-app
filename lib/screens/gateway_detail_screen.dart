import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/node.dart';
import 'gateway_settings_screen.dart';
import 'node_detail_screen.dart';
import '../services/api_errors.dart';
import '../theme/app_colors.dart';

class GatewayDetailScreen extends ConsumerStatefulWidget {
  final String gatewayId;
  const GatewayDetailScreen({super.key, required this.gatewayId});

  @override
  ConsumerState<GatewayDetailScreen> createState() => _GatewayDetailScreenState();
}

class _GatewayDetailScreenState extends ConsumerState<GatewayDetailScreen> {
  Timer? _pollTimer;
  final Map<int, bool> _previousOnline = {};
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

    for (final n in nodes) {
      final prev = _previousOnline[n.deviceId] ?? true;
      if (prev && !n.isOnline) {
        notifications.showOfflineNotification(
          'Node Offline',
          'Device ${n.deviceId} (${n.typeLabel}) is no longer connected.',
        );
      } else if (!prev && n.isOnline) {
        notifications.showOnlineNotification(
          'Node Online',
          'Device ${n.deviceId} (${n.typeLabel}) is back online.',
        );
      }
      _previousOnline[n.deviceId] = n.isOnline;
    }

    final gw = ref.read(gatewaysProvider).where((g) => g.id == widget.gatewayId).firstOrNull;
    if (gw != null) {
      _pollGw(gw);
    }

    await _fetchDiscovered();
  }

  void _pollGw(gateway) {
    final previousOnline = _previousOnline[widget.gatewayId.hashCode] ?? true;
    if (previousOnline && !gateway.online) {
      ref.read(notificationServiceProvider).showOfflineNotification(
        'Gateway Offline',
        '${gateway.name} is no longer connected.',
      );
    } else if (!previousOnline && gateway.online) {
      ref.read(notificationServiceProvider).showOnlineNotification(
        'Gateway Online',
        '${gateway.name} is back online.',
      );
    }
    _previousOnline[widget.gatewayId.hashCode] = gateway.online;
  }

  Future<void> _fetchDiscovered() async {
    final api = ref.read(apiServiceProvider);
    try {
      final response = await api.get('/api/gateways/${widget.gatewayId}/discovered');
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan complete')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _provision(int deviceId, String name, List<Map<String, dynamic>> caps) async {
    final api = ref.read(apiServiceProvider);
    setState(() => _provisioningIds.add(deviceId));
    void say(String m) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }

    try {
      final r = await api.post('/api/gateways/${widget.gatewayId}/provision', data: {
        'deviceId': deviceId,
        'name': name,
        'capabilitiesConfig': caps,
      });
      final status = (r.data is Map ? (r.data as Map)['status'] : null) as String?;
      if (status == 'registered_but_offline') {
        say('The gateway is offline, so the node could not be reached. Bring the gateway online and try again.');
        return;
      }
      say('Sending settings to node $deviceId…');
      // Keep the node "in progress" until it reports in (or give up after ~45 s).
      for (var i = 0; i < 22 && mounted; i++) {
        await Future.delayed(const Duration(seconds: 2));
        await ref.read(nodesProvider(widget.gatewayId).notifier).fetchNodes();
        final linked = ref.read(nodesProvider(widget.gatewayId)).any((n) => n.deviceId == deviceId);
        if (linked) {
          say('Node $deviceId connected');
          return;
        }
      }
      say('Node $deviceId did not report in. Check that it is powered and within range of the gateway, then try again.');
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
      return !linkedDeviceIds.contains(did) && !_provisioningIds.contains(did);
    }).toList();

    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.card,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.c.muted),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(gw?.name ?? 'Gateway', style: TextStyle(color: context.c.text)),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: context.c.muted),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GatewaySettingsScreen(gatewayId: widget.gatewayId)),
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
                        Text(gw?.online == true ? 'Online' : 'Offline',
                            style: TextStyle(
                                color: gw?.online == true ? context.c.ok : context.c.bad,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('ID: ${gw?.id ?? ''}', style: TextStyle(color: context.c.muted, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statBox('Nodes', '${nodes.length}'),
                        const SizedBox(width: 12),
                        _statBox('Online', '${nodes.where((n) => n.isOnline).length}'),
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
                Text('Nodes', style: TextStyle(color: context.c.text, fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: context.c.accent))
                      : Icon(Icons.wifi_find, color: context.c.accent, size: 18),
                  label: Text(_scanning ? 'Scanning…' : 'Scan', style: TextStyle(color: context.c.accent, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (nodes.isEmpty && unlinked.isEmpty)
              Card(
                color: context.c.card,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No nodes. Scan for nearby devices.', style: TextStyle(color: context.c.muted))),
                ),
              )
            else ...[
              ...nodes.map((n) => _NodeCard(n, widget.gatewayId)),
              if (unlinked.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Discovered', style: TextStyle(color: context.c.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...unlinked.map((d) => _DiscoveredCard(d, _provisioningIds, () {
                  final did = d['deviceId'] as int;
                  _showProvisionDialog(did);
                })),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showProvisionDialog(int deviceId) {
    showDialog(
      context: context,
      builder: (ctx) => _ProvisionDialog(
        deviceId: deviceId,
        onProvision: (name, caps) {
          Navigator.of(ctx).pop();
          _provision(deviceId, name, caps);
        },
      ),
    );
  }

  Widget _statusDot(bool online) {
    return Container(width: 10, height: 10,
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
            Text(value, style: TextStyle(color: context.c.text, fontSize: 20, fontWeight: FontWeight.bold)),
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
        side: BorderSide(color: provisioning ? context.c.accent : context.c.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text('Device $did',
            style: TextStyle(color: context.c.text, fontSize: 14)),
        subtitle: const Row(
          children: [
            _DiscBadge(),
          ],
        ),
        trailing: provisioning
            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.c.accent))
            : TextButton(
                onPressed: onConnect,
                child: Text('Connect', style: TextStyle(color: context.c.accent, fontSize: 13)),
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
      child: Text('Discovered',
          style: TextStyle(fontSize: 10, color: context.c.accent, fontWeight: FontWeight.w600)),
    );
  }
}

class _ProvisionDialog extends StatefulWidget {
  final int deviceId;
  final void Function(String name, List<Map<String, dynamic>> caps) onProvision;

  const _ProvisionDialog({required this.deviceId, required this.onProvision});

  @override
  State<_ProvisionDialog> createState() => _ProvisionDialogState();
}

class _ProvisionDialogState extends State<_ProvisionDialog> {
  final _nameCtrl = TextEditingController();
  final List<_CapFormEntry> _caps = [];

  @override
  void initState() {
    super.initState();
    _caps.add(_CapFormEntry());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _caps) { c.dispose(); }
    super.dispose();
  }

  void _addCap() {
    setState(() => _caps.add(_CapFormEntry()));
  }

  void _removeCap(int i) {
    if (_caps.length > 1) {
      _caps[i].dispose();
      setState(() => _caps.removeAt(i));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: context.c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.c.border),
      ),
      title: Text('Provision Device ${widget.deviceId}',
          style: TextStyle(color: context.c.text, fontSize: 16)),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              ..._caps.asMap().entries.map((e) => _capRow(e.key)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _addCap,
                icon: Icon(Icons.add, color: context.c.accent, size: 18),
                label: Text('Add Capability', style: TextStyle(color: context.c.accent, fontSize: 13)),
              ),
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
            widget.onProvision(_nameCtrl.text, caps);
          },
          child: const Text('Confirm', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _capRow(int i) {
    final c = _caps[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _darkField(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: c.type,
                dropdownColor: context.c.bg,
                style: TextStyle(color: context.c.text, fontSize: 12),
                decoration: _inputDec(''),
                items: const [
                  DropdownMenuItem(value: 'digitalOutput', child: Text('Dig Out')),
                  DropdownMenuItem(value: 'analogOutput', child: Text('An Out')),
                  DropdownMenuItem(value: 'analogInput', child: Text('An In')),
                  DropdownMenuItem(value: 'digitalInput', child: Text('Dig In')),
                  DropdownMenuItem(value: 'relay', child: Text('Relay')),
                  DropdownMenuItem(value: 'i2c', child: Text('I2C')),
                  DropdownMenuItem(value: 'uart', child: Text('UART')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => c.type = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (c.type != 'i2c' && c.type != 'uart')
            SizedBox(
              width: 50,
              child: _darkField(
                child: TextField(
                  controller: c.pinCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.c.text, fontSize: 12),
                  decoration: _inputDec('Pin'),
                ),
              ),
            ),
          if (c.type == 'i2c')
            SizedBox(
              width: 60,
              child: _darkField(
                child: TextField(
                  controller: c.pinCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.c.text, fontSize: 12),
                  decoration: _inputDec('Addr'),
                ),
              ),
            ),
          if (c.type == 'uart')
            SizedBox(
              width: 60,
              child: _darkField(
                child: TextField(
                  controller: c.pinCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.c.text, fontSize: 12),
                  decoration: _inputDec('UART#'),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: _darkField(
              child: TextField(
                controller: c.labelCtrl,
                style: TextStyle(color: context.c.text, fontSize: 12),
                decoration: _inputDec('Label'),
              ),
            ),
          ),
          if (_caps.length > 1)
            SizedBox(
              width: 30,
              child: IconButton(
                icon: Icon(Icons.remove_circle_outline, color: context.c.bad, size: 18),
                onPressed: () => _removeCap(i),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(text, style: TextStyle(color: context.c.text, fontSize: 12, fontWeight: FontWeight.w600));
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

class _CapFormEntry {
  String type;
  final TextEditingController pinCtrl;
  final TextEditingController labelCtrl;

  _CapFormEntry()
    : type = 'digitalOutput',
      pinCtrl = TextEditingController(text: '2'),
      labelCtrl = TextEditingController();

  Map<String, dynamic> toMap() {
    final isIoType = type != 'i2c' && type != 'uart';
    return {
      'type': type,
      'pin': isIoType ? (int.tryParse(pinCtrl.text) ?? 0) : 0,
      'extra': !isIoType ? (int.tryParse(pinCtrl.text) ?? 0) : 0,
      'label': labelCtrl.text,
    };
  }

  void dispose() {
    pinCtrl.dispose();
    labelCtrl.dispose();
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
        title: Text(node.displayName,
            style: TextStyle(color: context.c.text, fontSize: 14)),
        subtitle: Row(
          children: [
            _badge(context, node.isOnline ? 'Online' : 'Offline', node.isOnline),
            const SizedBox(width: 8),
            Text(node.typeLabel, style: TextStyle(color: context.c.muted, fontSize: 11)),
            if (node.value != null) ...[
              const SizedBox(width: 8),
              Text('Value: ${node.value}', style: TextStyle(color: context.c.accent, fontSize: 11)),
            ],
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: context.c.subtle),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NodeDetailScreen(node: node, gatewayId: gatewayId)),
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
      child: Text(label,
          style: TextStyle(fontSize: 10,
              color: online ? context.c.ok : context.c.muted,
              fontWeight: FontWeight.w600)),
    );
  }
}
