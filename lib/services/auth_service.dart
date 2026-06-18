import 'api_service.dart';

class AuthService {
  final ApiService _api;

  AuthService(this._api);

  Future<bool> login(String email, String password) async {
    try {
      final response = await _api.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      });
      final token = response.data['token'] as String?;
      if (token != null) {
        await _api.saveToken(token);
        await _api.saveCredentials(email, password);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
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

  Future<bool> trySilentLogin() async {
    await _api.loadCredentials();
    if (!_api.hasCredentials || _api.baseUrl == null) return false;
    final response = await _api.post('/api/auth/login', data: {
      'email': _api.savedEmail,
      'password': _api.savedPassword,
    });
    final token = response.data['token'] as String?;
    if (token != null) {
      await _api.saveToken(token);
      return true;
    }
    return false;
  }
}
