import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnLocalNetwork = false;
  String? _lastLocalGatewayIp;

  bool get isOnLocalNetwork => _isOnLocalNetwork;

  Stream<bool> get onLocalNetworkChanged => _onLocalController.stream;
  final StreamController<bool> _onLocalController = StreamController<bool>.broadcast();

  Future<bool> checkLocalConnectivity(String gatewayIp) async {
    _lastLocalGatewayIp = gatewayIp;
    try {
      final result = await InternetAddress.lookup(gatewayIp)
          .timeout(const Duration(seconds: 3));
      if (result.isNotEmpty) {
        _isOnLocalNetwork = true;
        if (!_onLocalController.isClosed) _onLocalController.add(true);
        return true;
      }
    } catch (_) {}
    _isOnLocalNetwork = false;
    if (!_onLocalController.isClosed) _onLocalController.add(false);
    return false;
  }

  void startMonitoring(void Function(bool isLocal) onChanged) {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (result) {
        if (result.contains(ConnectivityResult.wifi)) {
          if (_lastLocalGatewayIp != null) {
            checkLocalConnectivity(_lastLocalGatewayIp!);
          }
        } else {
          _isOnLocalNetwork = false;
          onChanged(false);
        }
      },
      onError: (_) {},
    );
  }

  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopMonitoring();
    _onLocalController.close();
  }
}
