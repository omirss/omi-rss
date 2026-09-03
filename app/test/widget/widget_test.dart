import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/main.dart';

void main() {
  testWidgets('App launches and shows title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RSSGlassmorphismReaderApp());

    // Verify that the title is displayed
    expect(find.text('RSS Glassmorphism Reader'), findsOneWidget);
  });
}