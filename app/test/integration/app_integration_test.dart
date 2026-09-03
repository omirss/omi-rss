import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rss_glassmorphism_reader/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('RSS Reader Integration Tests', () {
    testWidgets('app launches and shows home screen', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Verify app title is visible
      expect(find.text('RSS Reader'), findsOneWidget);
      
      // Verify main layout columns are present
      expect(find.byType(Scaffold), findsOneWidget);
    });
    
    testWidgets('can open and close drawer menu', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Find and tap menu button
      final menuButton = find.byIcon(Icons.menu);
      expect(menuButton, findsOneWidget);
      
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      
      // Verify drawer is open
      expect(find.text('Feeds'), findsWidgets);
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Generate Feed'), findsOneWidget);
      
      // Close drawer by tapping outside
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      
      // Verify drawer is closed
      expect(find.text('Discover'), findsNothing);
    });
    
    testWidgets('can add a new feed', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Find and tap Add Feed button
      final addFeedButton = find.text('Add Feed');
      expect(addFeedButton, findsOneWidget);
      
      await tester.tap(addFeedButton);
      await tester.pumpAndSettle();
      
      // Verify dialog appears
      expect(find.text('Add RSS Feed'), findsOneWidget);
      expect(find.text('Enter the URL of an RSS, Atom, or JSON feed'), findsOneWidget);
      
      // Enter feed URL
      final urlField = find.byType(TextField);
      await tester.enterText(urlField, 'https://example.com/feed.xml');
      await tester.pumpAndSettle();
      
      // Tap Add Feed button in dialog
      final confirmButton = find.text('Add Feed').last;
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
      
      // Verify success message
      expect(find.text('Feed added successfully!'), findsOneWidget);
    });
    
    testWidgets('can search articles', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Find search field
      final searchField = find.byType(TextField).first;
      expect(searchField, findsOneWidget);
      
      // Enter search query
      await tester.enterText(searchField, 'test search');
      await tester.pumpAndSettle();
      
      // Verify search is working (would show filtered results)
      expect(find.text('test search'), findsOneWidget);
    });
    
    testWidgets('can view article options', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Find first article's more button
      final moreButton = find.byIcon(Icons.more_horiz).first;
      await tester.tap(moreButton);
      await tester.pumpAndSettle();
      
      // Verify options dialog appears
      expect(find.text('Article 1 Options'), findsOneWidget);
      expect(find.text('Save for later'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      
      // Test save action
      await tester.tap(find.text('Save for later'));
      await tester.pumpAndSettle();
      
      expect(find.text('Article saved for later'), findsOneWidget);
    });
    
    testWidgets('theme and animations work correctly', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Verify glassmorphism containers are rendered
      expect(find.byType(ClipRRect), findsWidgets);
      expect(find.byType(BackdropFilter), findsWidgets);
      
      // Test hover effects (in web/desktop)
      final firstCategory = find.text('All Feeds');
      await tester.hover(firstCategory);
      await tester.pump(const Duration(milliseconds: 200));
      
      // Animations should be smooth
      await tester.pumpAndSettle();
    });
    
    testWidgets('responsive layout adapts to screen size', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Test with different screen sizes
      tester.view.physicalSize = const Size(400, 800); // Mobile
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();
      
      // Should show mobile layout
      expect(find.byType(Scaffold), findsOneWidget);
      
      // Test tablet size
      tester.view.physicalSize = const Size(800, 1200); // Tablet
      await tester.pumpAndSettle();
      
      // Test desktop size
      tester.view.physicalSize = const Size(1920, 1080); // Desktop
      await tester.pumpAndSettle();
      
      // Should show three-column layout
      expect(find.byType(Row), findsWidgets);
      
      // Reset to default
      tester.view.reset();
    });
    
    testWidgets('error handling shows appropriate messages', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Try to add invalid feed URL
      await tester.tap(find.text('Add Feed'));
      await tester.pumpAndSettle();
      
      final urlField = find.byType(TextField);
      await tester.enterText(urlField, 'not-a-valid-url');
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Add Feed').last);
      await tester.pumpAndSettle();
      
      // Should show error message
      expect(find.textContaining('Invalid'), findsOneWidget);
    });
    
    testWidgets('navigation between sections works', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Navigate to different categories
      await tester.tap(find.text('Technology'));
      await tester.pumpAndSettle();
      
      // Verify category is selected
      expect(find.text('Technology'), findsWidgets);
      
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      
      expect(find.text('News'), findsWidgets);
      
      // Navigate back to all feeds
      await tester.tap(find.text('All Feeds'));
      await tester.pumpAndSettle();
      
      expect(find.text('All Feeds'), findsWidgets);
    });
    
    testWidgets('settings can be accessed and modified', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Open drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      
      // Tap settings
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      
      // Verify settings options would be shown
      expect(find.text('Settings coming soon'), findsOneWidget);
    });
  });
}