import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/themes/high_contrast_theme.dart';

// Theme mode provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, AppThemeMode>((ref) {
  return ThemeModeNotifier();
});

enum AppThemeMode {
  system,
  light,
  dark,
  highContrastLight,
  highContrastDark,
  ultraHighContrastDark,
}

class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  static const String _storageKey = 'theme_mode';
  
  ThemeModeNotifier() : super(AppThemeMode.system) {
    _loadThemeMode();
  }
  
  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_storageKey);
    if (modeIndex != null && modeIndex < AppThemeMode.values.length) {
      state = AppThemeMode.values[modeIndex];
    }
  }
  
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, mode.index);
  }
}

// Current theme provider
final currentThemeProvider = Provider<ThemeData>((ref) {
  final themeMode = ref.watch(themeModeProvider);
  final brightness = WidgetsBinding.instance.window.platformBrightness;
  
  switch (themeMode) {
    case AppThemeMode.system:
      return brightness == Brightness.dark 
        ? _buildDarkTheme() 
        : _buildLightTheme();
    case AppThemeMode.light:
      return _buildLightTheme();
    case AppThemeMode.dark:
      return _buildDarkTheme();
    case AppThemeMode.highContrastLight:
      return HighContrastThemes.lightTheme();
    case AppThemeMode.highContrastDark:
      return HighContrastThemes.darkTheme();
    case AppThemeMode.ultraHighContrastDark:
      return HighContrastThemes.ultraDarkTheme();
  }
});

// Standard light theme
ThemeData _buildLightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    primaryColor: const Color(0xFF2196F3),
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.black87,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: Colors.white.withOpacity(0.9),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}

// Standard dark theme
ThemeData _buildDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    primaryColor: const Color(0xFF2196F3),
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: Colors.black.withOpacity(0.3),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}

// Theme customization provider
final themeCustomizationProvider = StateNotifierProvider<ThemeCustomizationNotifier, ThemeCustomization>((ref) {
  return ThemeCustomizationNotifier();
});

class ThemeCustomization {
  final Color? primaryColor;
  final Color? accentColor;
  final double fontSize;
  final String fontFamily;
  final bool useSystemFont;
  final bool reducedTransparency;
  final bool increasedContrast;
  
  ThemeCustomization({
    this.primaryColor,
    this.accentColor,
    this.fontSize = 1.0,
    this.fontFamily = 'Inter',
    this.useSystemFont = false,
    this.reducedTransparency = false,
    this.increasedContrast = false,
  });
  
  ThemeCustomization copyWith({
    Color? primaryColor,
    Color? accentColor,
    double? fontSize,
    String? fontFamily,
    bool? useSystemFont,
    bool? reducedTransparency,
    bool? increasedContrast,
  }) {
    return ThemeCustomization(
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      useSystemFont: useSystemFont ?? this.useSystemFont,
      reducedTransparency: reducedTransparency ?? this.reducedTransparency,
      increasedContrast: increasedContrast ?? this.increasedContrast,
    );
  }
}

class ThemeCustomizationNotifier extends StateNotifier<ThemeCustomization> {
  ThemeCustomizationNotifier() : super(ThemeCustomization());
  
  void setPrimaryColor(Color color) {
    state = state.copyWith(primaryColor: color);
  }
  
  void setAccentColor(Color color) {
    state = state.copyWith(accentColor: color);
  }
  
  void setFontSize(double size) {
    state = state.copyWith(fontSize: size.clamp(0.5, 2.0));
  }
  
  void setFontFamily(String family) {
    state = state.copyWith(fontFamily: family);
  }
  
  void toggleSystemFont() {
    state = state.copyWith(useSystemFont: !state.useSystemFont);
  }
  
  void toggleReducedTransparency() {
    state = state.copyWith(reducedTransparency: !state.reducedTransparency);
  }
  
  void toggleIncreasedContrast() {
    state = state.copyWith(increasedContrast: !state.increasedContrast);
  }
}

// Color scheme presets
class ColorSchemePresets {
  static const Map<String, ColorScheme> presets = {
    'Blue': ColorScheme(
      primary: Color(0xFF2196F3),
      secondary: Color(0xFF03A9F4),
      surface: Color(0xFFF5F5F5),
      background: Color(0xFFF5F5F5),
      error: Color(0xFFE91E63),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.black87,
      onBackground: Colors.black87,
      onError: Colors.white,
      brightness: Brightness.light,
    ),
    'Green': ColorScheme(
      primary: Color(0xFF4CAF50),
      secondary: Color(0xFF8BC34A),
      surface: Color(0xFFF5F5F5),
      background: Color(0xFFF5F5F5),
      error: Color(0xFFE91E63),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.black87,
      onBackground: Colors.black87,
      onError: Colors.white,
      brightness: Brightness.light,
    ),
    'Purple': ColorScheme(
      primary: Color(0xFF9C27B0),
      secondary: Color(0xFF7B1FA2),
      surface: Color(0xFFF5F5F5),
      background: Color(0xFFF5F5F5),
      error: Color(0xFFE91E63),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.black87,
      onBackground: Colors.black87,
      onError: Colors.white,
      brightness: Brightness.light,
    ),
    'Orange': ColorScheme(
      primary: Color(0xFFFF9800),
      secondary: Color(0xFFFFC107),
      surface: Color(0xFFF5F5F5),
      background: Color(0xFFF5F5F5),
      error: Color(0xFFE91E63),
      onPrimary: Colors.white,
      onSecondary: Colors.black87,
      onSurface: Colors.black87,
      onBackground: Colors.black87,
      onError: Colors.white,
      brightness: Brightness.light,
    ),
  };
}