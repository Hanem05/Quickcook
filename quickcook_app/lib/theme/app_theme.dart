import 'package:flutter/material.dart';

class AppTheme {
  static const Color _seed = Color(0xFF2E7D6E);

  /// Explicit dark palette so Flutter Web / Material 3 doesn’t look “washed” or light-on-light.
  static ColorScheme get _darkScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: _seed,
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFF0D4A42),
        onPrimaryContainer: Color(0xFFB8F0E8),
        secondary: Color(0xFF5EEAD4),
        onSecondary: Color(0xFF042F2A),
        tertiary: Color(0xFF94A3B8),
        onTertiary: Color(0xFF0F172A),
        error: Color(0xFFF87171),
        onError: Color(0xFF1F0000),
        surface: Color(0xFF0F0F12),
        onSurface: Color(0xFFE4E4E7),
        onSurfaceVariant: Color(0xFFA1A1AA),
        outline: Color(0xFF3F3F46),
        outlineVariant: Color(0xFF27272A),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFE4E4E7),
        onInverseSurface: Color(0xFF18181B),
        inversePrimary: Color(0xFF115E59),
        surfaceTint: _seed,
        surfaceContainerHighest: Color(0xFF27272A),
        surfaceContainerHigh: Color(0xFF1F1F23),
        surfaceContainer: Color(0xFF1A1A1E),
        surfaceContainerLow: Color(0xFF141418),
        surfaceContainerLowest: Color(0xFF0A0A0C),
        surfaceBright: Color(0xFF2A2A30),
        surfaceDim: Color(0xFF0C0C0E),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF4F6F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1C1E),
          ),
          iconTheme: IconThemeData(color: Color(0xFF1C1C1E)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: _seed,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Color(0xFFE4E4E7),
            disabledForegroundColor: Color(0xFF71717A),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      );

  static ThemeData get dark {
    final cs = _darkScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return cs.surfaceContainerHighest;
            }
            return _seed;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return cs.onSurface.withOpacity(0.38);
            }
            return Colors.white;
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 18),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant),
    );
  }
}
