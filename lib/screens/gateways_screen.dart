import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import 'login_screen.dart';
import 'gateway_detail_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/mfa_approval_host.dart';
import 'add_gateway_screen.dart';
import 'walkthrough_screen.dart';
import '../theme/app_colors.dart';

class GatewaysScreen extends ConsumerStatefulWidget {
  const GatewaysScreen({super.key});

  @override
  ConsumerState<GatewaysScreen> createState() => _GatewaysScreenState();
}

class _GatewaysScreenState extends ConsumerState<GatewaysScreen> {
  Timer? _pollTimer;
  final Map<String, bool> _previousOnline = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _maybeShowWalkthrough();
    });
    _startPolling();
  }

  // First launch after sign-in: show the tour once.
  Future<void> _maybeShowWalkthrough() async {
    if (await walkthroughSeen() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WalkthroughScreen()),
    );
    await markWalkthroughSeen();
  }

  Future<void> _addGateway() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddGatewayScreen()),
    );
    _load();
  }

  // Auto-refresh interval comes from Settings (0 = manual only).
  void _startPolling() {
    _pollTimer?.cancel();
    final secs = ref.read(settingsProvider).refreshSeconds;
    if (secs > 0) _pollTimer = Timer.periodic(Duration(seconds: secs), (_) => _poll());
  }

  Future<void> _load() async {
    ref.read(gatewaysProvider.notifier).fetchAll();
    _checkConnectivity();
  }

  Future<void> _poll() async {
    final notifier = ref.read(gatewaysProvider.notifier);
    await notifier.fetchAll();
    final current = ref.read(gatewaysProvider);
    final notifications = ref.read(notificationServiceProvider);

    for (final gw in current) {
      final prevOnline = _previousOnline[gw.id] ?? true;
      final prefs = ref.read(settingsProvider);
      if (prevOnline && !gw.online) {
        if (prefs.notifyOffline) {
          notifications.showOfflineNotification(
            'Gateway Offline',
            '${gw.name} is no longer connected.',
          );
        }
      } else if (!prevOnline && gw.online) {
        if (prefs.notifyOnline) {
          notifications.showOnlineNotification(
            'Gateway Online',
            '${gw.name} is back online.',
          );
        }
      }
      _previousOnline[gw.id] = gw.online;
    }
  }

  void _checkConnectivity() {
    final api = ref.read(apiServiceProvider);
    final baseUrl = api.baseUrl;
    if (baseUrl != null) {
      final host = Uri.parse(baseUrl).host;
      ref.read(connectivityServiceProvider).checkLocalConnectivity(host);
    }

    final scaffold = ScaffoldMessenger.of(context);
    ref.read(connectivityServiceProvider).startMonitoring((isLocal) {
      ref.read(isLocalNetworkProvider.notifier).state = isLocal;
      if (!isLocal) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Left local network — using remote connection')),
        );
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    try { ref.read(connectivityServiceProvider).stopMonitoring(); } catch (_) {}
    super.dispose();
  }

  Future<void> _logout() async {
    _pollTimer?.cancel();
    await ref.read(authServiceProvider).logout();
    ref.read(apiServiceProvider).clearToken();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gateways = ref.watch(gatewaysProvider);
    final isLocal = ref.watch(isLocalNetworkProvider);
    ref.listen(settingsProvider.select((s) => s.refreshSeconds), (_, __) => _startPolling());

    return MfaApprovalHost(
      child: Scaffold(
      backgroundColor: context.c.bg,
      drawer: AppDrawer(onLogout: _logout, onRefresh: _load),
      appBar: AppBar(
        backgroundColor: context.c.card,
        iconTheme: IconThemeData(color: context.c.text),
        title: Text('SmartHomes',
            style: TextStyle(color: context.c.text, fontWeight: FontWeight.bold)),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isLocal
                    ? context.c.okStrong.withValues(alpha: 0.2)
                    : context.c.bad.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isLocal ? Icons.wifi : Icons.cloud, size: 14,
                      color: isLocal ? context.c.ok : context.c.bad),
                  const SizedBox(width: 4),
                  Text(isLocal ? 'LAN' : 'Remote',
                      style: TextStyle(fontSize: 11,
                          color: isLocal ? context.c.ok : context.c.bad)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh, color: context.c.muted),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGateway,
        backgroundColor: context.c.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add gateway'),
      ),
      body: gateways.isEmpty
          ? _EmptyState(onAdd: _addGateway, onRefresh: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: gateways.length,
                itemBuilder: (_, i) => _GatewayCard(gateways[i]),
              ),
            ),
    ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  const _EmptyState({required this.onAdd, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.router_outlined, size: 72, color: context.c.border),
          const SizedBox(height: 16),
          Text('No gateways yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.c.text, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Power on a gateway, switch Bluetooth on and tap “Add gateway” — the app finds it and links it to your hub.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.muted, height: 1.4),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Find my gateway'),
            ),
          ),
          const SizedBox(height: 12),
          Text('Already added one? Pull down to refresh.',
              textAlign: TextAlign.center, style: TextStyle(color: context.c.faint, fontSize: 12)),
        ],
      ),
    );
  }
}

class _GatewayCard extends ConsumerWidget {
  final dynamic gateway;
  const _GatewayCard(this.gateway);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: context.c.card,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.c.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(gateway.name,
            style: TextStyle(color: context.c.text, fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${gateway.id}', style: TextStyle(color: context.c.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                _badge(context, gateway.online ? 'Online' : 'Offline', gateway.online),
                const SizedBox(width: 8),
                Text('${gateway.nodeCount} nodes (${gateway.onlineNodes} online)',
                    style: TextStyle(color: context.c.muted, fontSize: 11)),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: context.c.subtle),
        onTap: () {
          ref.read(selectedGatewayProvider.notifier).state = gateway;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GatewayDetailScreen(gatewayId: gateway.id)),
          );
        },
      ),
    );
  }

  Widget _badge(BuildContext context, String label, bool online) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: online
            ? context.c.okStrong.withValues(alpha: 0.2)
            : context.c.subtle.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11,
              color: online ? context.c.ok : context.c.muted,
              fontWeight: FontWeight.w600)),
    );
  }
}
