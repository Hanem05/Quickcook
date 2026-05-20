import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A scroll behavior that gives every scrollable in the app the same smooth
/// bouncy feel and accepts trackpad / mouse drag (a common cause of "stiff"
/// scroll on Flutter web).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}

/// Cross-platform fade transition between routes — smoother and more
/// consistent than the default Material zoom transition, especially on web.
class _SmoothPageTransitions extends PageTransitionsTheme {
  const _SmoothPageTransitions()
      : super(builders: const {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
        });
}

class AppTheme {
  // Warm premium accent: copper/amber.
  static const Color _seed = Color(0xFFC2410C);

  /// Shared smoothness defaults applied to both light and dark themes.
  static const PageTransitionsTheme pageTransitions = _SmoothPageTransitions();

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
        onSurfaceVariant: Color(0xFFC9CAD1),
        outline: Color(0xFF5A5B63),
        outlineVariant: Color(0xFF3A3B43),
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
        pageTransitionsTheme: pageTransitions,
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F6F5),
          foregroundColor: Color(0xFF1C1C1E),
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
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
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _seed, width: 1.6),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          iconColor: Color(0xFF4B5563),
          textColor: Color(0xFF1C1C1E),
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
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1C1C1E),
            side: const BorderSide(color: Color(0xFFD4D4D8)),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _seed,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF0F3F2),
          selectedColor: _seed.withValues(alpha: 0.15),
          side: const BorderSide(color: Color(0xFFDDE2E0)),
          labelStyle: const TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF111827),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE4E4E7)),
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
      pageTransitionsTheme: pageTransitions,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
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
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.primary, width: 1.6),
        ),
      ),
      cardTheme: CardThemeData(
        color: cs.surfaceContainerHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
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
              return cs.onSurface.withValues(alpha: 0.38);
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outlineVariant),
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.primary.withValues(alpha: 0.28),
        side: BorderSide(color: cs.outlineVariant),
        labelStyle: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: TextStyle(
          color: cs.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant),
    );
  }
}
