import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'login_screen.dart';
import 'gateway_detail_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
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
      if (prevOnline && !gw.online) {
        notifications.showOfflineNotification(
          'Gateway Offline',
          '${gw.name} is no longer connected.',
        );
      } else if (!prevOnline && gw.online) {
        notifications.showOnlineNotification(
          'Gateway Online',
          '${gw.name} is back online.',
        );
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

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        title: const Text('SmartHomes', style: TextStyle(color: Color(0xFFc9d1d9), fontWeight: FontWeight.bold)),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isLocal
                    ? const Color(0xFF238636).withValues(alpha: 0.2)
                    : const Color(0xFFf85149).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isLocal ? Icons.wifi : Icons.cloud, size: 14,
                      color: isLocal ? const Color(0xFF3fb950) : const Color(0xFFf85149)),
                  const SizedBox(width: 4),
                  Text(isLocal ? 'LAN' : 'Remote',
                      style: TextStyle(fontSize: 11,
                          color: isLocal ? const Color(0xFF3fb950) : const Color(0xFFf85149))),
                ],
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF8b949e)), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout, color: Color(0xFF8b949e)), onPressed: _logout),
        ],
      ),
      body: gateways.isEmpty
          ? const Center(child: Text('No gateways', style: TextStyle(color: Color(0xFF8b949e))))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: gateways.length,
                itemBuilder: (_, i) => _GatewayCard(gateways[i]),
              ),
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
      color: const Color(0xFF161b22),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF30363d)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(gateway.name,
            style: const TextStyle(color: Color(0xFFc9d1d9), fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${gateway.id}', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                _badge(gateway.online ? 'Online' : 'Offline', gateway.online),
                const SizedBox(width: 8),
                Text('${gateway.nodeCount} nodes (${gateway.onlineNodes} online)',
                    style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF484f58)),
        onTap: () {
          ref.read(selectedGatewayProvider.notifier).state = gateway;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GatewayDetailScreen(gatewayId: gateway.id)),
          );
        },
      ),
    );
  }

  Widget _badge(String label, bool online) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: online
            ? const Color(0xFF238636).withValues(alpha: 0.2)
            : const Color(0xFF484f58).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11,
              color: online ? const Color(0xFF3fb950) : const Color(0xFF8b949e),
              fontWeight: FontWeight.w600)),
    );
  }
}
