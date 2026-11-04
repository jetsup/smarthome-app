import 'api_service.dart';
import 'device_info.dart' as device;

/// A request waiting for the user. A sign-in request makes the user type the
/// number shown on the website; "turn on" requests show the number to type there.
class MfaRequest {
  final String id;
  final String code; // only for purpose == enable
  final String purpose; // login | enable
  final bool needsNumber;
  final int expiresIn;
  final String device; // where the request came from ("Chrome on Linux", ...)
  final String ip;
  const MfaRequest(this.id, this.code, this.purpose, this.needsNumber, this.expiresIn, this.device, this.ip);

  factory MfaRequest.fromJson(Map<String, dynamic> j) => MfaRequest(
        j['id'] as String? ?? '',
        j['code'] as String? ?? '',
        j['purpose'] as String? ?? 'login',
        j['needsNumber'] == true,
        j['expiresIn'] as int? ?? 0,
        j['device'] as String? ?? 'a browser',
        j['ip'] as String? ?? '',
      );

  bool get isLogin => purpose == 'login';
}

class ApproveResult {
  final bool ok;
  final String? error;
  final int? attemptsLeft;
  final bool blocked;
  const ApproveResult(this.ok, {this.error, this.attemptsLeft, this.blocked = false});
}

/// This phone's side of two-step verification.
class MfaService {
  final ApiService _api;
  bool _registered = false;

  MfaService(this._api);

  Future<String> deviceKey() => device.deviceKey();

  Future<Map<String, String>> _headers() async => {'X-Device-Key': await deviceKey()};

  /// Make this phone eligible to approve sign-ins. Safe to call repeatedly.
  Future<bool> register() async {
    if (_registered) return true;
    try {
      final d = await device.deviceDetails();
      await _api.post('/api/mfa/devices', data: {
        'deviceKey': await deviceKey(),
        'name': d.name,
        'model': d.model,
        'manufacturer': d.manufacturer,
        'os': d.os,
      });
      _registered = true;
    } catch (_) {}
    return _registered;
  }

  Future<List<MfaRequest>> pending() async {
    try {
      final r = await _api.get('/api/mfa/pending', headers: await _headers());
      return (r.data as List).map((j) => MfaRequest.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deny(String id) async {
    try {
      await _api.post('/api/mfa/challenges/$id/deny', data: {}, headers: await _headers());
    } catch (_) {}
  }

  /// Type the number shown on the website, then Approve.
  Future<ApproveResult> approve(String id, String code) async {
    try {
      await _api.post('/api/mfa/challenges/$id/approve', data: {'code': code}, headers: await _headers());
      return const ApproveResult(true);
    } catch (e) {
      try {
        // ignore: avoid_dynamic_calls
        final r = (e as dynamic).response;
        final d = r?.data;
        return ApproveResult(false,
            error: d is Map ? d['error'] as String? : null,
            attemptsLeft: d is Map ? d['attemptsLeft'] as int? : null,
            blocked: r?.statusCode == 403 || r?.statusCode == 410);
      } catch (_) {
        return const ApproveResult(false, error: 'Could not reach the hub');
      }
    }
  }
}
