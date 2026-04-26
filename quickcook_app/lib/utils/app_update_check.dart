import 'package:flutter/material.dart';

import '../services/api_service.dart';

const String _currentAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
);

int _compareVersion(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va > vb) return 1;
    if (va < vb) return -1;
  }
  return 0;
}

Future<void> promptAppUpdateIfNeeded(BuildContext context) async {
  try {
    final info = await ApiService.fetchAppVersionInfo();
    final latest = info['latest_version']?.toString() ?? _currentAppVersion;
    final minimum =
        info['minimum_supported_version']?.toString() ?? _currentAppVersion;
    final force = info['force_update'] == true;
    final message = info['message']?.toString() ?? 'A new version is available.';

    final isOutdated = _compareVersion(_currentAppVersion, latest) < 0;
    final unsupported = _compareVersion(_currentAppVersion, minimum) < 0;
    if (!isOutdated && !unsupported) return;

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !(force || unsupported),
      builder: (_) => AlertDialog(
        title: Text(unsupported ? 'Update required' : 'Update available'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } catch (_) {}
}
