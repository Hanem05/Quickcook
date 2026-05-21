import 'package:flutter/material.dart';

/// QuickCook brand palette — dusty sapphire & arctic mist (not standard Material blue).
abstract final class AppColors {
  static const Color brand = Color(0xFF3D5A9E);
  static const Color brandLight = Color(0xFF7EB8F0);
  static const Color brandDark = Color(0xFF243B6E);
  static const Color accent = Color(0xFF4EB8D4);

  static const Color bgSoft = Color(0xFFF0F4FB);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFDDE5F2);
  static const Color textMain = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);
  static const Color darkSlate = Color(0xFF1A2338);
  static const Color sidebarRail = Color(0xFF222D47);

  static const Color dangerRed = Color(0xFFEF4444);
  static const Color successEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFE8A838);

  static const Color surfaceDark = Color(0xFF0E1219);
  static const Color surfaceDarkLowest = Color(0xFF0A0E16);
  static const Color surfaceDarkHigh = Color(0xFF161D2B);
  static const Color surfaceDarkContainer = Color(0xFF1C2538);
  static const Color onSurfaceDark = Color(0xFFE8EDF7);
  static const Color onSurfaceVariantDark = Color(0xFFA8B4CC);
  static const Color outlineDark = Color(0xFF4A5A78);
  static const Color outlineVariantDark = Color(0xFF2E3A52);

  static ColorScheme get lightScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: brand,
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFD6E4FF),
        onPrimaryContainer: brandDark,
        secondary: brandLight,
        onSecondary: brandDark,
        tertiary: Color(0xFF8FA8D8),
        onTertiary: Color(0xFF1A2744),
        error: Color(0xFFDC2626),
        onError: Color(0xFFFFFFFF),
        surface: bgSoft,
        onSurface: textMain,
        onSurfaceVariant: textMuted,
        outline: Color(0xFF94A3B8),
        outlineVariant: borderLight,
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: textMain,
        onInverseSurface: Color(0xFFF8FAFC),
        inversePrimary: brandLight,
        surfaceTint: brand,
        surfaceContainerHighest: Color(0xFFE2E8F4),
        surfaceContainerHigh: Color(0xFFE8EEF8),
        surfaceContainer: Color(0xFFF4F7FC),
        surfaceContainerLow: Color(0xFFF8FAFD),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceBright: Color(0xFFFFFFFF),
        surfaceDim: Color(0xFFE8EEF8),
      );

  static ColorScheme get darkScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: brandLight,
        onPrimary: brandDark,
        primaryContainer: Color(0xFF2A4070),
        onPrimaryContainer: Color(0xFFC8DCFF),
        secondary: accent,
        onSecondary: Color(0xFF0A2A35),
        tertiary: Color(0xFF8FA8D8),
        onTertiary: Color(0xFF0F172A),
        error: Color(0xFFF87171),
        onError: Color(0xFF1F0000),
        surface: surfaceDark,
        onSurface: onSurfaceDark,
        onSurfaceVariant: onSurfaceVariantDark,
        outline: outlineDark,
        outlineVariant: outlineVariantDark,
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: onSurfaceDark,
        onInverseSurface: surfaceDark,
        inversePrimary: brandDark,
        surfaceTint: brandLight,
        surfaceContainerHighest: Color(0xFF2A3548),
        surfaceContainerHigh: surfaceDarkContainer,
        surfaceContainer: Color(0xFF182030),
        surfaceContainerLow: Color(0xFF121A28),
        surfaceContainerLowest: Color(0xFF0A0E16),
        surfaceBright: Color(0xFF2E3A52),
        surfaceDim: Color(0xFF0A0E16),
      );
}
