
import 'device_info.dart' as device;
import 'api_service.dart';

enum LoginOutcome { success, mfaRequired, failed }

/// What the password step produced. With two-step verification on there is no
/// session yet: the caller must complete [mfaToken] with one of [methods].
class LoginResult {
  final LoginOutcome outcome;
  final String? mfaToken;
  final bool totp;
  final bool email;
  final bool recovery;
  final String? emailTo;
  final String? error;
  const LoginResult(this.outcome,
      {this.mfaToken, this.totp = false, this.email = false, this.recovery = false, this.emailTo, this.error});
}

class AuthService {
  final ApiService _api;

  AuthService(this._api);

  Future<Map<String, dynamic>> _deviceBody(String email, String password) async {
    final d = await device.deviceDetails();
    return {'email': email, 'password': password, 'deviceKey': await device.deviceKey(), 'deviceLabel': d.label};
  }

  Future<LoginResult> loginStep(String email, String password) async {
    try {
      final response = await _api.post('/api/auth/login', data: await _deviceBody(email, password));
      final data = response.data as Map;
      if (data['mfaRequired'] == true) {
        final m = (data['methods'] as Map?) ?? {};
        return LoginResult(LoginOutcome.mfaRequired,
            mfaToken: data['mfaToken'] as String?,
            totp: m['totp'] == true,
            email: m['email'] == true,
            recovery: m['recovery'] == true,
            emailTo: data['emailTo'] as String?);
      }
      final token = data['token'] as String?;
      if (token != null) {
        await _api.saveToken(token);
        await _api.saveCredentials(email, password);
        return const LoginResult(LoginOutcome.success);
      }
      return const LoginResult(LoginOutcome.failed);
    } catch (e) {
      return LoginResult(LoginOutcome.failed, error: _serverError(e));
    }
  }

  /// Back-compat for callers that only need success / failure.
  Future<bool> login(String email, String password) async =>
      (await loginStep(email, password)).outcome == LoginOutcome.success;

  /// Email a sign-in code. Returns {sentTo, expiresIn, challengeId} or an error string.
  Future<Map<String, dynamic>> mfaSendEmail(String mfaToken) async {
    try {
      final r = await _api.post('/api/auth/mfa/challenge', data: {'mfaToken': mfaToken, 'method': 'email'});
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      return {'error': _serverError(e) ?? 'Could not send the email'};
    }
  }

  /// Finish sign-in with an authenticator / emailed code or a recovery code.
  /// Returns an error message, or null on success.
  Future<String?> mfaVerify({
    required String mfaToken,
    required String method, // totp | email | recovery
    String? challengeId,
    String? code,
  }) async {
    try {
      final r = await _api.post('/api/auth/mfa/verify', data: {
        'mfaToken': mfaToken,
        'method': method,
        if (challengeId != null) 'challengeId': challengeId,
        if (method == 'recovery') 'recoveryCode': code else 'code': code,
      });
      final token = (r.data as Map)['token'] as String?;
      if (token == null) return 'Verification failed';
      await _api.saveToken(token);
      return null;
    } catch (e) {
      return _serverError(e) ?? 'Verification failed';
    }
  }

  String? _serverError(Object e) {
    try {
      // ignore: avoid_dynamic_calls
      final d = (e as dynamic).response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
    } catch (_) {}
    return null;
  }

  Future<bool> register(String firstName, String lastName, String email, String password) async {
    try {
      final response = await _api.post('/api/auth/register', data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
        'password_confirm': password,
      });
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    await _api.clearCredentials();
  }

  Future<bool> isAuthenticated() async {
    await _api.loadToken();
    return _api.hasToken;
  }

  Future<bool> verifyToken() async {
    if (!_api.hasToken || _api.baseUrl == null) return false;
    try {
      await _api.get('/api/auth/me');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Silent re-login with saved credentials. It cannot work when two-step
  /// verification is on (no token is returned) — the user signs in again.
  Future<bool> trySilentLogin() async {
    await _api.loadCredentials();
    if (!_api.hasCredentials || _api.baseUrl == null) return false;
    final response = await _api.post('/api/auth/login',
        data: await _deviceBody(_api.savedEmail ?? '', _api.savedPassword ?? ''));
    final token = (response.data as Map)['token'] as String?;
    if (token != null) {
      await _api.saveToken(token);
      return true;
    }
    return false;
  }
}
