import 'package:flutter/material.dart';

/// Color token set for one preset in one brightness mode.
///
/// Every preset defines a light and a dark instance of this class. All values
/// are const so presets can be referenced from const contexts.
class GlassColorTokens {
  // Identity
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color accentSoft;

  // Text
  final Color textHigh;
  final Color textMedium;
  final Color textLow;

  // Surfaces
  final Color glassFill;
  final Color glassStroke;
  final Color overlay;

  // Semantic
  final Color success;
  final Color warning;
  final Color error;

  // Background
  final Color bgBase;
  final List<Color> backgroundGradient;

  // Legacy gradient hooks used by existing screens
  final List<Color> primaryGradient;
  final List<Color> accentGradient;
  final List<Color> auroraColors;

  final Brightness brightness;

  const GlassColorTokens({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.accentSoft,
    required this.textHigh,
    required this.textMedium,
    required this.textLow,
    required this.glassFill,
    required this.glassStroke,
    required this.overlay,
    required this.success,
    required this.warning,
    required this.error,
    required this.bgBase,
    required this.backgroundGradient,
    required this.primaryGradient,
    required this.accentGradient,
    required this.auroraColors,
    required this.brightness,
  });

  bool get isDark => brightness == Brightness.dark;
}

/// Corner radius scale.
class GlassRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;

  const GlassRadii._();
}

/// Backdrop blur scale.
class GlassBlur {
  static const double sm = 10;
  static const double md = 20;
  static const double lg = 30;

  const GlassBlur._();
}

/// Spacing scale (4pt base grid).
class GlassSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  const GlassSpacing._();
}

/// Five-step type scale. Colors are applied per mode from GlassColorTokens.
class GlassTypeScale {
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  const GlassTypeScale._();
}

/// Shared semantic scales, mode-independent.
class GlassTokens {
  static const GlassRadii radii = GlassRadii._();
  static const GlassBlur blur = GlassBlur._();
  static const GlassSpacing spacing = GlassSpacing._();
  static const GlassTypeScale type = GlassTypeScale._();

  const GlassTokens._();
}

/// Builds a Material [ThemeData] from glass tokens so snackbars, dialogs and
/// other Material surfaces match the active glass preset.
ThemeData buildGlassMaterialTheme(GlassColorTokens tokens) {
  final scheme = ColorScheme(
    brightness: tokens.brightness,
    primary: tokens.primary,
    onPrimary: tokens.isDark ? Colors.white : Colors.white,
    secondary: tokens.secondary,
    onSecondary: Colors.white,
    surface: tokens.bgBase,
    onSurface: tokens.textHigh,
    surfaceContainerHighest: tokens.glassStroke,
    error: tokens.error,
    onError: Colors.white,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: tokens.bgBase,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.isDark ? const Color(0xE61A1F3C) : const Color(0xE6FFFFFF),
      contentTextStyle: TextStyle(color: tokens.textHigh, fontSize: 14),
      actionTextColor: tokens.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassRadii.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.isDark ? const Color(0xF0101430) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassRadii.lg),
        side: BorderSide(color: tokens.glassStroke),
      ),
      titleTextStyle: GlassTypeScale.title.copyWith(color: tokens.textHigh),
      contentTextStyle: GlassTypeScale.body.copyWith(color: tokens.textMedium),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.glassStroke,
      thickness: 1,
    ),
  );
}
