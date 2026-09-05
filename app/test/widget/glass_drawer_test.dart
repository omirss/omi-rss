import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/ui/glass_theme.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_button.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_drawer.dart';
import 'package:rss_glassmorphism_reader/ui/tokens/glass_presets.dart';
import 'package:rss_glassmorphism_reader/ui/tokens/glass_tokens.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required GlassColorTokens tokens,
    required void Function(BuildContext) onOpenDrawer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: GlassThemeData.fromTokens(tokens),
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: GlassButton(
                  icon: Icons.menu,
                  variant: GlassButtonVariant.icon,
                  onPressed: () => onOpenDrawer(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('drawer route inherits the calling page glass theme',
      (tester) async {
    final lightTokens = GlassPresets.glassLight.light;
    var routeBrightness = Brightness.dark;

    await pumpHost(
      tester,
      tokens: lightTokens,
      onOpenDrawer: (context) => showGlassDrawer(
        context: context,
        items: const [
          GlassDrawerItem(id: 'feeds', title: 'Feeds'),
        ],
        footer: Builder(
          builder: (footerContext) {
            routeBrightness = GlassTheme.colorsOf(footerContext).brightness;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));

    expect(routeBrightness, Brightness.light,
        reason:
            'content built inside the drawer route must resolve the caller '
            'theme, not the default dark fallback');
  });

  testWidgets('drawer badge chip renders the count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: GlassThemeData.fromTokens(GlassPresets.glass.dark),
          child: const Scaffold(
            body: Center(child: GlassDrawerBadge(count: '30')),
          ),
        ),
      ),
    );

    expect(find.text('30'), findsOneWidget);
    final text = tester.widget<Text>(find.text('30'));
    expect(text.style?.color, GlassPresets.glass.dark.accent);
  });

  testWidgets('badgeWidget slot renders live badge content', (tester) async {
    await pumpHost(
      tester,
      tokens: GlassPresets.glass.dark,
      onOpenDrawer: (context) => showGlassDrawer(
        context: context,
        items: const [
          GlassDrawerItem(
            id: 'all-feeds',
            title: 'All Feeds',
            badgeWidget: GlassDrawerBadge(count: '7'),
          ),
        ],
      ),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('All Feeds'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });
}
