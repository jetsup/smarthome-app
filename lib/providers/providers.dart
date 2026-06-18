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

enum SplashState { discovering, found, notFound, authenticated, error }

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

  Future<bool> sendCommand(String nodeId, int value) async {
    final api = _ref.read(apiServiceProvider);
    try {
      await api.post('/api/nodes/$nodeId/command', data: {'value': value});
      return true;
    } catch (_) {
      return false;
    }
  }
}
