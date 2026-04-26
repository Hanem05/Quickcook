import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

class AppLogger {
  static Future<void> logApiError({
    required String endpoint,
    required Object error,
    int? statusCode,
    Map<String, dynamic>? extra,
  }) async {
    debugPrint('[API ERROR] $endpoint $statusCode $error');
    await _pushClientError(
      endpoint: endpoint,
      error: error.toString(),
      statusCode: statusCode,
      extra: extra,
    );
  }

  static Future<void> logCrash(
    Object error,
    StackTrace stackTrace, {
    String source = 'flutter',
  }) async {
    debugPrint('[CRASH][$source] $error\n$stackTrace');
    await _pushClientError(
      endpoint: source,
      error: '$error',
      extra: {'stack': stackTrace.toString()},
    );
  }

  static Future<void> _pushClientError({
    required String endpoint,
    required String error,
    int? statusCode,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final token = await ApiService.getToken();
      if (token == null || token.isEmpty) return;
      await http.post(
        Uri.parse('${ApiService.baseUrl}/metrics'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'kind': 'client_error',
          'name': endpoint,
          'duration_ms': 0,
          'meta': {
            'error': error,
            if (statusCode != null) 'status_code': statusCode,
            if (extra != null) ...extra,
          },
        }),
      );
    } catch (_) {}
  }
}
