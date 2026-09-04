import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/providers/theme_settings_provider.dart';
import 'package:rss_glassmorphism_reader/ui/tokens/glass_presets.dart';
import 'package:rss_glassmorphism_reader/ui/tokens/glass_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlassPresets', () {
    test('defines five user-facing presets', () {
      expect(GlassPresets.all.length, 5);
      expect(
        GlassPresets.all.map((p) => p.id).toSet().length,
        5,
      );
    });

    test('every preset has distinct light and dark pairs', () {
      for (final preset in GlassPresets.all) {
        expect(preset.dark.isDark, isTrue);
        expect(preset.light.isDark, isFalse);
        expect(preset.dark.bgBase, isNot(preset.light.bgBase));
        expect(preset.resolve(Brightness.dark), same(preset.dark));
        expect(preset.resolve(Brightness.light), same(preset.light));
      }
    });

    test('unknown id falls back to the default preset', () {
      expect(GlassPresets.byId('nope').id, GlassPresets.defaultPresetId);
      expect(GlassPresets.byId(null).id, GlassPresets.defaultPresetId);
    });

    test('default preset preserves the glass identity', () {
      expect(GlassPresets.glass.dark.primary, GlassCoreColors.primary);
      expect(GlassPresets.glass.dark.accent, GlassCoreColors.accent);
      expect(
        GlassPresets.glass.dark.backgroundGradient,
        GlassCoreColors.backgroundGradient,
      );
    });

    test('type scale has five steps', () {
      expect(GlassTypeScale.display.fontSize, 28);
      expect(GlassTypeScale.title.fontSize, 20);
      expect(GlassTypeScale.body.fontSize, 16);
      expect(GlassTypeScale.label.fontSize, 14);
      expect(GlassTypeScale.caption.fontSize, 12);
    });

    test('material theme is built from tokens', () {
      final theme = buildGlassMaterialTheme(GlassPresets.ember.dark);
      expect(
        theme.scaffoldBackgroundColor,
        GlassPresets.ember.dark.bgBase,
      );
      expect(
        theme.colorScheme.primary,
        GlassPresets.ember.dark.primary,
      );
    });
  });

  group('ThemeSettingsNotifier', () {
    test('persists preset and mode via SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeSettingsProvider.notifier).setPreset('aurora');
      await container.read(themeSettingsProvider.notifier).setMode(AppThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themePreset'), 'aurora');
      expect(prefs.getInt('themeMode'), AppThemeMode.dark.index);
      expect(container.read(themePresetProvider).id, 'aurora');
      expect(container.read(materialThemeModeProvider), ThemeMode.dark);
    });

    test('restores persisted settings', () async {
      SharedPreferences.setMockInitialValues({
        'themePreset': 'ember',
        'themeMode': AppThemeMode.light.index,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(themeSettingsProvider.notifier);
      await pumpEventQueue();
      expect(container.read(themePresetProvider).id, 'ember');
      expect(container.read(materialThemeModeProvider), ThemeMode.light);
    });

    test('falls back to defaults for unknown stored values', () async {
      SharedPreferences.setMockInitialValues({
        'themePreset': 'gone',
        'themeMode': 99,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(themeSettingsProvider.notifier);
      await pumpEventQueue();
      expect(container.read(themePresetProvider).id, 'glass');
      expect(container.read(materialThemeModeProvider), ThemeMode.system);
    });
  });
}
