import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/config/app_info.dart';
import 'package:rss_glassmorphism_reader/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> bootApp(
    WidgetTester tester, {
    Map<String, Object> initialValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialValues);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      const ProviderScope(child: app.OmiRssApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('RSS Reader Integration Tests', () {
    testWidgets('app boots to the login screen', (tester) async {
      await bootApp(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Omi RSS Reader'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Continue without account'), findsOneWidget);
    });

    testWidgets('local mode opens the home shell', (tester) async {
      await bootApp(tester, initialValues: {'localMode': true});
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('RSS Reader'), findsOneWidget);
      expect(find.text('Add Feed'), findsOneWidget);
      expect(find.text('Refresh All'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('drawer opens and closes from the home shell', (tester) async {
      await bootApp(tester, initialValues: {'localMode': true});
      await tester.pump(const Duration(milliseconds: 300));

      final menuButton = find.byIcon(Icons.menu);
      expect(menuButton, findsOneWidget);
      await tester.tap(menuButton);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Saved Articles'), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      expect(find.text('$appName $appVersion'), findsOneWidget,
          reason: 'drawer footer must show the version line');

      await tester.tapAt(const Offset(20, 300));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Saved Articles'), findsNothing);
    });

    testWidgets('add feed dialog opens and cancels', (tester) async {
      await bootApp(tester, initialValues: {'localMode': true});
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Add Feed'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Add RSS Feed'), findsOneWidget);
      expect(find.text('Enter the URL of an RSS, Atom, or JSON feed'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add RSS Feed'), findsNothing);
    });
  });
}
