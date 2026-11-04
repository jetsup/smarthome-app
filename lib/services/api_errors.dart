import 'package:dio/dio.dart';

/// The `error` message the hub sent, or [fallback].
String apiError(Object e, [String fallback = 'Something went wrong']) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['error'] is String) return d['error'] as String;
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach the hub';
    }
  }
  return fallback;
}
