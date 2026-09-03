import 'package:flutter/material.dart';

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
  
  const GlassThemeData({
    this.blur = 20.0,
    this.opacity = 0.1,
    this.gradientColors = const [
      Color(0x1AFFFFFF),
      Color(0x0DFFFFFF),
    ],
    this.borderColor = const Color(0x2DFFFFFF),
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
  
  @override
  bool updateShouldNotify(GlassTheme oldWidget) => data != oldWidget.data;
}

/// Color palette for glassmorphism effects
class GlassColors {
  // Primary gradients
  static const List<Color> primaryGradient = [Color(0xFF667eea), Color(0xFF764ba2)];
  static const List<Color> secondaryGradient = [Color(0xFFf093fb), Color(0xFFf5576c)];
  static const List<Color> accentGradient = [Color(0xFF4facfe), Color(0xFF00f2fe)];
  
  // Aurora colors
  static const List<Color> auroraColors = [
    Color(0xFF00d2ff),
    Color(0xFF3a7bd5),
    Color(0xFF7f00ff),
    Color(0xFFe100ff),
  ];
  
  // Glass whites with different opacities
  static const Color glassWhite10 = Color(0x1AFFFFFF);
  static const Color glassWhite20 = Color(0x33FFFFFF);
  static const Color glassWhite30 = Color(0x4DFFFFFF);
  static const Color glassWhite40 = Color(0x66FFFFFF);
  
  // Glass borders
  static const Color glassBorder = Color(0x2DFFFFFF);
  static const Color glassBorderStrong = Color(0x40FFFFFF);
  
  // Shadow colors
  static const Color shadowPrimary = Color(0x591F268C);
  static const Color shadowDark = Color(0x99000000);
  static const Color shadowLight = Color(0x331F268C);
}