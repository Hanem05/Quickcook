import 'package:flutter/material.dart';

enum AppMessageType { success, error, info }

class AppMessage {
  static void show(
    BuildContext context, {
    required String text,
    AppMessageType type = AppMessageType.info,
  }) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg, icon) = _resolveStyle(cs, type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: fg,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static (Color, Color, IconData) _resolveStyle(ColorScheme cs, AppMessageType type) {
    switch (type) {
      case AppMessageType.success:
        return (cs.inverseSurface, cs.onInverseSurface, Icons.check_circle_outline_rounded);
      case AppMessageType.error:
        return (Colors.redAccent, Colors.white, Icons.error_outline_rounded);
      case AppMessageType.info:
        return (cs.surfaceContainerHighest, cs.onSurface, Icons.info_outline_rounded);
    }
  }
}
