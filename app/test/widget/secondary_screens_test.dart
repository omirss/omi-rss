import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/providers/theme_settings_provider.dart';
import 'package:rss_glassmorphism_reader/ui/screens/glass_screen.dart';
import 'package:rss_glassmorphism_reader/ui/tokens/glass_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Map<String, Object> initialValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialValues);
    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: const MediaQueryData(),
          child: MaterialApp(
            home: GlassScreen(
              title: 'Test Screen',
              body: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('GlassScreen background', () {
    testWidgets('renders the Glass light tokens under system light',
        (tester) async {
      await pumpScreen(tester);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, GlassPresets.glass.light.bgBase);
    });

    testWidgets('renders the Glass dark tokens in dark mode',
        (tester) async {
      await pumpScreen(tester, initialValues: {'themeMode': 2});

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, GlassPresets.glass.dark.bgBase);
    });

    testWidgets('follows light mode with the light bgBase token',
        (tester) async {
      await pumpScreen(tester, initialValues: {'themeMode': 1});

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, GlassPresets.glass.light.bgBase);
    });

    testWidgets('follows the selected preset', (tester) async {
      await pumpScreen(tester, initialValues: {'themePreset': 'ember'});

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, GlassPresets.ember.light.bgBase);
    });

    testWidgets('paints a gradient behind the app bar', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(DecoratedBox), findsAtLeastNWidgets(1));
      expect(find.text('Test Screen'), findsOneWidget);
    });
  });
}
