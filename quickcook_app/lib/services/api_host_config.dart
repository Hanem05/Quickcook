import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
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

  /// USB debugging: use 127.0.0.1 + `adb reverse tcp:8001 tcp:8001` (no Wi‑Fi IP).
  static bool get usesUsbLocalhost =>
      kDebugMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      isPhysicalAndroid &&
      _savedHost.isEmpty;

  static bool get requiresManualHost =>
      !kDebugMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      isPhysicalAndroid &&
      _savedHost.isEmpty;

  /// True when the APK was built without `--dart-define=API_BASE_URL` / `API_HOST`.
  static bool get hasBuildTimeApiUrl {
    const base = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (base.trim().isNotEmpty) return true;
    const host = String.fromEnvironment('API_HOST', defaultValue: '');
    return host.trim().isNotEmpty;
  }

  /// Physical Android with no baked-in URL — user must enter server IP on login.
  static bool get needsServerSetup => !hasBuildTimeApiUrl && requiresManualHost;

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

  static Future<String?> loadSavedPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPortKey)?.trim();
  }

  /// Parses `192.168.1.5`, `192.168.1.5:8001`, or `http://host:8001/api`.
  static ({String host, String port}) parseServerInput(
    String raw, {
    String defaultPort = '8001',
  }) {
    var input = raw.trim();
    if (input.isEmpty) {
      return (host: '', port: defaultPort);
    }

    if (!input.contains('://')) {
      final slash = input.indexOf('/');
      if (slash > 0) input = input.substring(0, slash);
      final colon = input.lastIndexOf(':');
      if (colon > 0) {
        final maybePort = input.substring(colon + 1);
        if (int.tryParse(maybePort) != null) {
          return (
            host: input.substring(0, colon).trim(),
            port: maybePort,
          );
        }
      }
      return (host: input, port: defaultPort);
    }

    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty) {
      return (host: input, port: defaultPort);
    }
    final port = uri.hasPort ? uri.port.toString() : defaultPort;
    return (host: uri.host, port: port);
  }

  /// Saves host/port from login UI. Returns false when host is empty.
  static Future<bool> applyServerFromFields(
    String hostInput, {
    String portInput = '8001',
  }) async {
    final portDefault =
        portInput.trim().isEmpty ? '8001' : portInput.trim();
    final parsed = parseServerInput(hostInput, defaultPort: portDefault);
    if (parsed.host.isEmpty) return false;
    await saveHost(parsed.host, port: parsed.port);
    return true;
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
      if (kDebugMode) {
        // USB debug: `adb reverse tcp:8001 tcp:8001` maps phone localhost → PC :8001
        return _url('127.0.0.1', effectivePort);
      }
      // Release APK on Wi‑Fi: enter PC IP on login, or bake API_BASE_URL at build time.
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
    if (kDebugMode && Platform.isAndroid) {
      return _url('127.0.0.1', _portFromEnvironment());
    }
    return _url('127.0.0.1', _portFromEnvironment());
  }
}
