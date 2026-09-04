import 'package:flutter/material.dart';
import 'tokens/glass_tokens.dart';
import 'tokens/glass_presets.dart';

/// Comprehensive glass theme configuration
class GlassThemeData {
  final double blur;
  final double opacity;
  final List<Color> gradientColors;
  final Color borderColor;
  final double borderWidth;
  final Color shadowColor;
  final double shadowBlurRadius;
  final Offset shadowOffset;
  final BorderRadius borderRadius;
  final Duration animationDuration;
  final Curve animationCurve;

  // Hover properties
  final double hoverElevation;
  final double hoverScale;
  final Duration hoverDuration;

  // Click properties
  final double clickScale;
  final Duration clickDuration;

  // Color palette
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final List<Color> backgroundGradient;

  // Full token set for the active preset/mode when built from a preset.
  final GlassColorTokens? colorTokens;

  // Text styles
  final TextStyle headlineMedium;
  final TextStyle titleLarge;
  final TextStyle titleMedium;
  final TextStyle titleSmall;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;

  const GlassThemeData({
    this.primaryColor = GlassCoreColors.primary,
    this.secondaryColor = GlassCoreColors.secondary,
    this.accentColor = GlassCoreColors.accent,
    this.backgroundColor = GlassCoreColors.bgBase,
    this.surfaceColor = GlassCoreColors.glassFill,
    this.backgroundGradient = GlassCoreColors.backgroundGradient,
    this.colorTokens,
    this.headlineMedium = const TextStyle(
      color: Colors.white,
      fontSize: 28,
      fontWeight: FontWeight.bold,
    ),
    this.titleLarge = const TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    this.titleMedium = const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    this.titleSmall = const TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    this.bodyLarge = const TextStyle(
      color: Colors.white,
      fontSize: 16,
      height: 1.5,
    ),
    this.bodyMedium = const TextStyle(
      color: Colors.white70,
      fontSize: 14,
      height: 1.4,
    ),
    this.bodySmall = const TextStyle(
      color: Colors.white60,
      fontSize: 12,
    ),
    this.blur = GlassBlur.md,
    this.opacity = 0.1,
    this.gradientColors = const [
      Color(0x1AFFFFFF),
      Color(0x0DFFFFFF),
    ],
    this.borderColor = GlassCoreColors.glassStroke,
    this.borderWidth = 1.5,
    this.shadowColor = const Color(0x591F268C),
    this.shadowBlurRadius = 32.0,
    this.shadowOffset = const Offset(0, 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.animationDuration = const Duration(milliseconds: 350),
    this.animationCurve = Curves.easeInOutCubic,
    this.hoverElevation = 2.0,
    this.hoverScale = 1.02,
    this.hoverDuration = const Duration(milliseconds: 200),
    this.clickScale = 0.98,
    this.clickDuration = const Duration(milliseconds: 100),
  });

  /// Default glass theme
  static const GlassThemeData defaultTheme = GlassThemeData();
  
  /// Dark theme variant
  static const GlassThemeData darkTheme = GlassThemeData(
    gradientColors: [
      Color(0x1A000000),
      Color(0x0D000000),
    ],
    borderColor: Color(0x2D000000),
    shadowColor: Color(0x99000000),
  );
  
  /// Light theme variant
  static const GlassThemeData lightTheme = GlassThemeData(
    gradientColors: [
      Color(0x26FFFFFF),
      Color(0x1AFFFFFF),
    ],
    borderColor: Color(0x40FFFFFF),
    shadowColor: Color(0x331F268C),
    blur: 15.0,
  );
  
  /// Purple/blue gradient theme
  static const GlassThemeData purpleBlueTheme = GlassThemeData(
    gradientColors: [
      Color(0x33667EEA),
      Color(0x1A764BA2),
    ],
    borderColor: Color(0x40667EEA),
    shadowColor: Color(0x59667EEA),
  );

  /// Builds glass theme data from a preset's token set for one brightness
  /// mode. Used to theme screens reactively from the selected preset.
  factory GlassThemeData.fromTokens(GlassColorTokens tokens) {
    final textHigh = tokens.textHigh;
    final textMedium = tokens.textMedium;
    return GlassThemeData(
      primaryColor: tokens.primary,
      secondaryColor: tokens.secondary,
      accentColor: tokens.accent,
      backgroundColor: tokens.bgBase,
      surfaceColor: tokens.glassFill,
      backgroundGradient: tokens.backgroundGradient,
      headlineMedium: GlassTypeScale.display.copyWith(color: textHigh),
      titleLarge: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ).copyWith(color: textHigh),
      titleMedium: GlassTypeScale.label.copyWith(
        color: textHigh,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GlassTypeScale.label.copyWith(color: textMedium),
      bodyLarge: GlassTypeScale.body.copyWith(
        color: textHigh,
        height: 1.5,
      ),
      bodyMedium: GlassTypeScale.label.copyWith(
        color: textMedium,
        height: 1.4,
      ),
      bodySmall: GlassTypeScale.caption.copyWith(color: tokens.textLow),
      blur: tokens.isDark ? GlassBlur.md : GlassBlur.sm + 5,
      gradientColors: [
        tokens.glassFill,
        tokens.glassFill.withValues(alpha: 0.05),
      ],
      borderColor: tokens.glassStroke,
      shadowColor: tokens.isDark
          ? const Color(0x591F268C)
          : const Color(0x331F268C),
      colorTokens: tokens,
    );
  }
  
  /// Copy with method for customization
  GlassThemeData copyWith({
    double? blur,
    double? opacity,
    List<Color>? gradientColors,
    Color? borderColor,
    double? borderWidth,
    Color? shadowColor,
    double? shadowBlurRadius,
    Offset? shadowOffset,
    BorderRadius? borderRadius,
    Duration? animationDuration,
    Curve? animationCurve,
    double? hoverElevation,
    double? hoverScale,
    Duration? hoverDuration,
    double? clickScale,
    Duration? clickDuration,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    List<Color>? backgroundGradient,
    GlassColorTokens? colorTokens,
    TextStyle? headlineMedium,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
  }) {
    return GlassThemeData(
      blur: blur ?? this.blur,
      opacity: opacity ?? this.opacity,
      gradientColors: gradientColors ?? this.gradientColors,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlurRadius: shadowBlurRadius ?? this.shadowBlurRadius,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      borderRadius: borderRadius ?? this.borderRadius,
      animationDuration: animationDuration ?? this.animationDuration,
      animationCurve: animationCurve ?? this.animationCurve,
      hoverElevation: hoverElevation ?? this.hoverElevation,
      hoverScale: hoverScale ?? this.hoverScale,
      hoverDuration: hoverDuration ?? this.hoverDuration,
      clickScale: clickScale ?? this.clickScale,
      clickDuration: clickDuration ?? this.clickDuration,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      colorTokens: colorTokens ?? this.colorTokens,
      headlineMedium: headlineMedium ?? this.headlineMedium,
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
    );
  }
}

/// Glass theme provider widget
class GlassTheme extends InheritedWidget {
  final GlassThemeData data;
  
  const GlassTheme({
    super.key,
    required this.data,
    required super.child,
  });
  
  static GlassThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<GlassTheme>();
    return theme?.data ?? GlassThemeData.defaultTheme;
  }
  
  static GlassThemeData? maybeOf(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<GlassTheme>();
    return theme?.data;
  }

  /// Resolves the active preset's color tokens, falling back to the default
  /// Glass dark palette when no themed shell is present.
  static GlassColorTokens colorsOf(BuildContext context) {
    final data = maybeOf(context)?.colorTokens;
    return data ?? GlassPresets.glass.dark;
  }

  static GlassColorTokens get colors => GlassPresets.glass.dark;
  
  static Color get primaryColor => GlassColors.primary;
  static Color get secondaryColor => GlassColors.secondary;
  static Color get accentColor => GlassColors.accent;
  static Color get backgroundColor => GlassColors.background;
  static Color get surfaceColor => GlassColors.surface;
  static List<Color> get backgroundGradient => GlassColors.backgroundGradient;
  
  @override
  bool updateShouldNotify(GlassTheme oldWidget) => data != oldWidget.data;
}

/// Color palette for glassmorphism effects.
///
/// These are the dark-mode tokens of the default Glass preset; screens
/// migrate to GlassThemeData.fromTokens with the active preset over time.
class GlassColors {
  // Core colors
  static const Color primary = GlassCoreColors.primary;
  static const Color secondary = GlassCoreColors.secondary;
  static const Color accent = GlassCoreColors.accent;
  static const Color background = GlassCoreColors.bgBase;
  static const Color surface = GlassCoreColors.glassFill;

  // App background gradient
  static const List<Color> backgroundGradient =
      GlassCoreColors.backgroundGradient;

  // Primary gradients
  static const List<Color> primaryGradient =
      GlassCoreColors.primaryGradient;
  static const List<Color> secondaryGradient = [Color(0xFFf093fb), Color(0xFFf5576c)];
  static const List<Color> accentGradient =
      GlassCoreColors.accentGradient;
  
  // Aurora colors
  static const List<Color> auroraColors =
      GlassCoreColors.auroraColors;
  
  // Glass whites with different opacities
  static const Color glassWhite10 = Color(0x1AFFFFFF);
  static const Color glassWhite20 = Color(0x33FFFFFF);
  static const Color glassWhite30 = Color(0x4DFFFFFF);
  static const Color glassWhite40 = Color(0x66FFFFFF);
  
  // Glass borders
  static const Color glassBorder = GlassCoreColors.glassStroke;
  static const Color glassBorderStrong = Color(0x40FFFFFF);
  
  // Shadow colors
  static const Color shadowPrimary = Color(0x591F268C);
  static const Color shadowDark = Color(0x99000000);
  static const Color shadowLight = Color(0x331F268C);
}
