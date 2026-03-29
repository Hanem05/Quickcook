import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class PerformanceReporter {
  static const int _slowApiMs = 1500;

  static Future<void> reportScreen(String name, int durationMs) async {
    if (durationMs < 40) return;
    await _post(kind: 'screen', name: name, durationMs: durationMs);
  }

  static Future<void> onApiCall(String endpointLabel, int durationMs) async {
    if (durationMs >= _slowApiMs) {
      debugPrint(
        '[Performance] slow API: $endpointLabel ${durationMs}ms',
      );
      await _post(
        kind: 'api',
        name: endpointLabel,
        durationMs: durationMs,
        meta: const {'slow': true},
      );
    }
  }

  static Future<void> _post({
    required String kind,
    required String name,
    required int durationMs,
    Map<String, dynamic>? meta,
  }) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) return;

    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}/metrics'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'kind': kind,
          'name': name,
          'duration_ms': durationMs,
          if (meta != null) 'meta': meta,
        }),
      );
    } catch (_) {}
  }
}
