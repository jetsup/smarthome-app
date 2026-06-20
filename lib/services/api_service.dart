import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  final Dio _dio;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  String? _baseUrl;
  String? _token;
  String? _email;
  String? _password;
  bool _refreshing = false;

  ApiService() : _dio = Dio() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        if (_baseUrl != null) {
          options.baseUrl = _baseUrl!;
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && !_refreshing) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final retryOptions = error.requestOptions;
            retryOptions.headers['Authorization'] = 'Bearer $_token';
            try {
              final response = await _dio.fetch(retryOptions);
              handler.resolve(response);
              return;
            } catch (_) {}
          } else {
            await clearToken();
            await clearCredentials();
          }
        }
        handler.next(error);
      },
    ));
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 8);
  }

  String? get baseUrl => _baseUrl;
  bool get hasBaseUrl => _baseUrl != null;
  bool get hasToken => _token != null;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Future<void> loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
    } catch (_) {}
  }

  Future<void> saveToken(String token) async {
    _token = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } catch (_) {}
  }

  Future<void> clearToken() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (_) {}
  }

  Future<void> saveCredentials(String email, String password) async {
    _email = email;
    _password = password;
    try {
      await _secure.write(key: 'auth_email', value: email);
      await _secure.write(key: 'auth_password', value: password);
    } catch (_) {
      // Secure storage may be unavailable on some devices
    }
  }

  Future<void> loadCredentials() async {
    try {
      _email = await _secure.read(key: 'auth_email');
      _password = await _secure.read(key: 'auth_password');
    } catch (_) {}
  }

  Future<void> clearCredentials() async {
    _email = null;
    _password = null;
    try {
      await _secure.delete(key: 'auth_email');
      await _secure.delete(key: 'auth_password');
    } catch (_) {}
  }

  bool get hasCredentials => _email != null && _password != null;
  String? get savedEmail => _email;
  String? get savedPassword => _password;

  Future<bool> _tryRefresh() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      if (_email != null && _password != null && _baseUrl != null) {
        final response = await Dio().post(
          '$_baseUrl/api/auth/login',
          data: {'email': _email, 'password': _password},
          options: Options(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 8)),
        );
        final token = response.data['token'] as String?;
        if (token != null) {
          await saveToken(token);
          return true;
        }
      }
    } catch (_) {}
    _refreshing = false;
    return false;
  }

  Future<void> saveHubUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hub_url', url);
  }

  Future<String?> loadHubUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('hub_url');
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> delete(String path) =>
      _dio.delete(path);
}
