import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the Laravel API base URL for emulator, physical device, and web.
class ApiHostConfig {
  static const _prefHostKey = 'api_host';
  static const _prefPortKey = 'api_port';

  static String _current = '';
  static bool isPhysicalAndroid = false;

  static String get current {
    if (_current.isNotEmpty) return _current;
    return _resolveSyncFallback();
  }

  static bool get requiresManualHost =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      isPhysicalAndroid &&
      _savedHost.isEmpty;

  static String _savedHost = '';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _savedHost = prefs.getString(_prefHostKey)?.trim() ?? '';
    _current = await _resolve();
  }

  static Future<void> saveHost(String host, {String port = '8001'}) async {
    final trimmed = host.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_prefHostKey);
      _savedHost = '';
    } else {
      await prefs.setString(_prefHostKey, trimmed);
      await prefs.setString(_prefPortKey, port.trim().isEmpty ? '8001' : port.trim());
      _savedHost = trimmed;
    }
    _current = await _resolve();
  }

  static Future<String?> loadSavedHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefHostKey)?.trim();
  }

  static Future<String> _resolve() async {
    const baseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (baseUrlEnv.isNotEmpty) return baseUrlEnv;

    const hostEnv = String.fromEnvironment('API_HOST', defaultValue: '');
    final port = _portFromEnvironment();

    if (kIsWeb) {
      isPhysicalAndroid = false;
      return _url('127.0.0.1', port);
    }

    if (hostEnv.trim().isNotEmpty) {
      isPhysicalAndroid = false;
      return _url(hostEnv.trim(), port);
    }

    final prefs = await SharedPreferences.getInstance();
    final savedHost = prefs.getString(_prefHostKey)?.trim() ?? '';
    _savedHost = savedHost;
    final savedPort = prefs.getString(_prefPortKey)?.trim();
    final effectivePort =
        (savedPort != null && savedPort.isNotEmpty) ? savedPort : port;

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      isPhysicalAndroid = info.isPhysicalDevice;
      if (!info.isPhysicalDevice) {
        return _url('10.0.2.2', effectivePort);
      }
      if (savedHost.isNotEmpty) {
        return _url(savedHost, effectivePort);
      }
      // Physical phone without saved host — caller must collect IP on login.
      return '';
    }

    isPhysicalAndroid = false;
    return _url('127.0.0.1', effectivePort);
  }

  static String _portFromEnvironment() {
    const portEnv = String.fromEnvironment('API_PORT', defaultValue: '8001');
    final trimmed = portEnv.trim();
    return trimmed.isEmpty ? '8001' : trimmed;
  }

  static String _url(String host, String port) => 'http://$host:$port/api';

  static String _resolveSyncFallback() {
    if (kIsWeb) return _url('127.0.0.1', _portFromEnvironment());
    if (Platform.isAndroid && !isPhysicalAndroid) {
      return _url('10.0.2.2', _portFromEnvironment());
    }
    if (_savedHost.isNotEmpty) {
      return _url(_savedHost, _portFromEnvironment());
    }
    return _url('127.0.0.1', _portFromEnvironment());
  }
}
