import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/main.dart' as app;
import 'package:rss_glassmorphism_reader/providers/theme_settings_provider.dart';
import 'package:rss_glassmorphism_reader/ui/tokens/glass_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> bootApp(
    WidgetTester tester, {
    Map<String, Object> initialValues = const {'localMode': true},
  }) async {
    SharedPreferences.setMockInitialValues(initialValues);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      const ProviderScope(child: app.OmiRssApp()),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final settingsBox = tester.renderObject<RenderBox>(find.text('Settings'));
    expect(settingsBox.localToGlobal(Offset.zero).dx, greaterThan(0));
    await tester.tap(find.text('Settings'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  group('Theme settings', () {
    testWidgets('settings shows all preset cards and mode chips',
        (tester) async {
      await bootApp(tester);
      await openSettings(tester);

      for (final preset in GlassPresets.all) {
        expect(find.text(preset.name), findsOneWidget);
      }
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('selecting a preset persists and rethemes Material surfaces',
        (tester) async {
      await bootApp(tester);
      await openSettings(tester);

      await tester.tap(find.text('Aurora'));
      await tester.pump(const Duration(milliseconds: 400));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themePreset'), 'aurora');

      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp).first,
      );
      expect(
        materialApp.theme!.colorScheme.primary,
        GlassPresets.aurora.light.primary,
      );
      expect(
        materialApp.darkTheme!.colorScheme.primary,
        GlassPresets.aurora.dark.primary,
      );
      expect(
        materialApp.darkTheme!.scaffoldBackgroundColor,
        GlassPresets.aurora.dark.bgBase,
      );
    });

    testWidgets('mode selection persists and drives ThemeMode',
        (tester) async {
      await bootApp(tester);
      await openSettings(tester);

      await tester.tap(find.text('Light'));
      await tester.pump(const Duration(milliseconds: 400));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('themeMode'), AppThemeMode.light.index);

      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp).first,
      );
      expect(materialApp.themeMode, ThemeMode.light);

      await tester.tap(find.text('Dark'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(prefs.getInt('themeMode'), AppThemeMode.dark.index);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp).first).themeMode,
        ThemeMode.dark,
      );
    });

    testWidgets('preset selection retunes the glass shell data',
        (tester) async {
      await bootApp(tester);
      await openSettings(tester);

      await tester.tap(find.text('Ember'));
      await tester.pump(const Duration(milliseconds: 400));

      final element = tester.element(find.byType(MaterialApp).first);
      final scope = ProviderScope.containerOf(element);
      expect(
        scope.read(themePresetProvider).id,
        'ember',
      );
      expect(
        scope.read(effectiveGlassTokensProvider).accent,
        anyOf(equals(GlassPresets.ember.light.accent),
            equals(GlassPresets.ember.dark.accent)),
      );
    });

    testWidgets('app boots with persisted preset and mode', (tester) async {
      await bootApp(tester, initialValues: {
        'localMode': true,
        'themePreset': 'mono',
        'themeMode': 1,
      });
      await tester.pump(const Duration(milliseconds: 300));

      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp).first,
      );
      expect(materialApp.themeMode, ThemeMode.light);
      expect(
        materialApp.theme!.scaffoldBackgroundColor,
        GlassPresets.mono.light.bgBase,
      );
    });
  });
}
