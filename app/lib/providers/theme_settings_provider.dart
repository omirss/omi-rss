import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/tokens/glass_tokens.dart';
import '../ui/tokens/glass_presets.dart';

enum AppThemeMode { system, light, dark }

class ThemeSettings {
  final String presetId;
  final AppThemeMode mode;

  const ThemeSettings({
    this.presetId = GlassPresets.defaultPresetId,
    this.mode = AppThemeMode.system,
  });

  ThemeSettings copyWith({String? presetId, AppThemeMode? mode}) {
    return ThemeSettings(
      presetId: presetId ?? this.presetId,
      mode: mode ?? this.mode,
    );
  }
}

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  static const String presetKey = 'themePreset';
  static const String modeKey = 'themeMode';

  ThemeSettingsNotifier() : super(const ThemeSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final presetId = prefs.getString(presetKey);
    final modeIndex = prefs.getInt(modeKey);
    final mode = modeIndex != null && modeIndex < AppThemeMode.values.length
        ? AppThemeMode.values[modeIndex]
        : AppThemeMode.system;
    state = ThemeSettings(
      presetId: presetId ?? GlassPresets.defaultPreset.id,
      mode: mode,
    );
  }

  Future<void> setPreset(String presetId) async {
    state = state.copyWith(presetId: presetId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(presetKey, presetId);
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(modeKey, mode.index);
  }
}

final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  return ThemeSettingsNotifier();
});

/// The selected preset.
final themePresetProvider = Provider<GlassThemePreset>((ref) {
  final settings = ref.watch(themeSettingsProvider);
  return GlassPresets.byId(settings.presetId);
});

/// Material theme mode for MaterialApp.
final materialThemeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(themeSettingsProvider);
  switch (settings.mode) {
    case AppThemeMode.system:
      return ThemeMode.system;
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
  }
});

/// Resolves the effective brightness, following the platform brightness when
/// mode is system. Callers with a BuildContext should prefer
/// [effectiveGlassTokensProvider], which reads MediaQuery directly.
final effectiveBrightnessProvider = Provider<Brightness>((ref) {
  final settings = ref.watch(themeSettingsProvider);
  switch (settings.mode) {
    case AppThemeMode.system:
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    case AppThemeMode.light:
      return Brightness.light;
    case AppThemeMode.dark:
      return Brightness.dark;
  }
});

/// The color tokens currently in effect, resolved from preset + mode. In
/// system mode the platform brightness picks the preset's light/dark pair.
final effectiveGlassTokensProvider = Provider<GlassColorTokens>((ref) {
  final preset = ref.watch(themePresetProvider);
  final brightness = ref.watch(effectiveBrightnessProvider);
  return preset.resolve(brightness);
});

/// Material light/dark pair for MaterialApp; Flutter follows the system
/// brightness via themeMode and picks the matching pair.
final materialThemesProvider =
    Provider<({ThemeData light, ThemeData dark})>((ref) {
  final preset = ref.watch(themePresetProvider);
  return (
    light: buildGlassMaterialTheme(preset.light),
    dark: buildGlassMaterialTheme(preset.dark),
  );
});
