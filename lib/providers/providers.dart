import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gateway.dart';
import '../models/node.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/discovery_service.dart';
import '../services/notification_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityService());

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(apiServiceProvider)));

final discoveryServiceProvider = Provider<DiscoveryService>((ref) => DiscoveryService());

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

final gatewaysProvider = StateNotifierProvider<GatewaysNotifier, List<Gateway>>((ref) => GatewaysNotifier(ref));

final selectedGatewayProvider = StateProvider<Gateway?>((ref) => null);

final nodesProvider = StateNotifierProvider.family<NodesNotifier, List<SmartNode>, String>((ref, gatewayId) => NodesNotifier(ref, gatewayId));

final isLocalNetworkProvider = StateProvider<bool>((ref) => false);

final isAuthenticatedProvider = StateProvider<bool>((ref) => false);

final discoveryResultsProvider = StateProvider<List<Gateway>>((ref) => []);

final splashStateProvider = StateProvider<SplashState>((ref) => SplashState.discovering);

enum SplashState { permission, discovering, found, notFound, authenticated, error }

class GatewaysNotifier extends StateNotifier<List<Gateway>> {
  final Ref _ref;

  GatewaysNotifier(this._ref) : super([]);

  Future<void> fetchAll() async {
    final api = _ref.read(apiServiceProvider);
    try {
      final response = await api.get('/api/gateways');
      state = (response.data as List)
          .map((j) => Gateway.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  Future<Gateway?> fetchOne(String id) async {
    final api = _ref.read(apiServiceProvider);
    try {
      final response = await api.get('/api/gateways/$id');
      final gw = Gateway.fromJson(response.data as Map<String, dynamic>);
      final list = state.where((g) => g.id != id).toList();
      list.add(gw);
      state = list;
      return gw;
    } catch (_) {
      return null;
    }
  }
}

class NodesNotifier extends StateNotifier<List<SmartNode>> {
  final Ref _ref;
  final String gatewayId;

  NodesNotifier(this._ref, this.gatewayId) : super([]);

  Future<void> fetchNodes() async {
    final api = _ref.read(apiServiceProvider);
    try {
      final response = await api.get('/api/gateways/$gatewayId/nodes');
      state = (response.data as List)
          .map((j) => SmartNode.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  Future<void> fetchNodeDetail(String nodeId) async {
    final api = _ref.read(apiServiceProvider);
    try {
      final response = await api.get('/api/nodes/$nodeId');
      final updated = SmartNode.fromJson(response.data as Map<String, dynamic>);
      final list = state.where((n) => n.nodeId != nodeId).toList();
      list.add(updated);
      state = list;
    } catch (_) {}
  }

  Future<bool> sendCommand(String nodeId, int value, {int? pin}) async {
    final api = _ref.read(apiServiceProvider);
    try {
      final payload = <String, dynamic>{'value': value};
      if (pin != null) payload['pin'] = pin;
      await api.post('/api/nodes/$nodeId/command', data: payload);
      return true;
    } catch (_) {
      return false;
    }
  }
}
