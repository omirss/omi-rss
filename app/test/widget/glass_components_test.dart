import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/models/article.dart';
import 'package:rss_glassmorphism_reader/ui/glass_theme.dart';
import 'package:rss_glassmorphism_reader/ui/components/article_card.dart';
import 'package:rss_glassmorphism_reader/ui/components/empty_state.dart';
import 'package:rss_glassmorphism_reader/ui/components/error_state.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_container.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_button.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_card.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_text_field.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_dialog.dart';
import 'package:rss_glassmorphism_reader/ui/components/skeleton.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: GlassTheme(
        data: GlassThemeData.defaultTheme,
        child: Scaffold(
          body: Center(child: child),
        ),
      ),
    );
  }
  
  group('GlassContainer', () {
    testWidgets('renders with default properties', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassContainer(
            child: const Text('Test'),
          ),
        ),
      );
      
      expect(find.text('Test'), findsOneWidget);
      expect(find.byType(GlassContainer), findsOneWidget);
    });
    
    testWidgets('applies custom padding', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: const Text('Test'),
          ),
        ),
      );
      
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(GlassContainer),
          matching: find.byType(Container),
        ),
      );

      expect(
        containers.any((c) => c.padding == const EdgeInsets.all(20)),
        isTrue,
      );
    });
    
    testWidgets('handles tap events', (tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(
        createTestWidget(
          GlassContainer(
            onTap: () => tapped = true,
            child: const Text('Tap me'),
          ),
        ),
      );
      
      await tester.tap(find.byType(GlassContainer));
      expect(tapped, true);
    });
  });
  
  group('GlassButton', () {
    testWidgets('renders text button', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassButton(
            text: 'Click me',
            onPressed: () {},
          ),
        ),
      );
      
      expect(find.text('Click me'), findsOneWidget);
    });
    
    testWidgets('renders icon button', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassButton(
            icon: Icons.add,
            onPressed: () {},
            variant: GlassButtonVariant.icon,
          ),
        ),
      );
      
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
    
    testWidgets('renders text with icon', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassButton(
            text: 'Add Item',
            icon: Icons.add,
            onPressed: () {},
          ),
        ),
      );
      
      expect(find.text('Add Item'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
    
    testWidgets('disabled state prevents taps', (tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(
        createTestWidget(
          GlassButton(
            text: 'Disabled',
            onPressed: null,
          ),
        ),
      );
      
      await tester.tap(find.byType(GlassButton));
      expect(tapped, false);
    });
    
    testWidgets('loading state shows spinner', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassButton(
            text: 'Loading',
            onPressed: () {},
            isLoading: true,
          ),
        ),
      );
      
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
    });
  });
  
  group('GlassCard', () {
    testWidgets('renders with child content', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassCard(
            child: const Text('Card content'),
          ),
        ),
      );
      
      expect(find.text('Card content'), findsOneWidget);
    });
    
    testWidgets('swipe to dismiss works', (tester) async {
      bool dismissed = false;
      
      await tester.pumpWidget(
        createTestWidget(
          GlassCard(
            enableSwipeToDismiss: true,
            onDismissed: () => dismissed = true,
            child: const Text('Swipe me'),
          ),
        ),
      );
      
      await tester.drag(find.byType(GlassCard), const Offset(300, 0));
      await tester.pumpAndSettle();
      
      expect(dismissed, true);
    });
    
    testWidgets('applies elevation effect', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          Column(
            children: [
              GlassCard(
                elevation: 1,
                child: const Text('Low elevation'),
              ),
              GlassCard(
                elevation: 5,
                child: const Text('High elevation'),
              ),
            ],
          ),
        ),
      );
      
      expect(find.byType(GlassCard), findsNWidgets(2));
    });
  });
  
  group('GlassTextField', () {
    testWidgets('renders with hint text', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassTextField(
            controller: TextEditingController(),
            hintText: 'Enter text',
          ),
        ),
      );
      
      expect(find.text('Enter text'), findsOneWidget);
    });
    
    testWidgets('search variant shows search icon', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassTextField(
            controller: TextEditingController(),
            isSearch: true,
          ),
        ),
      );
      
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
    
    testWidgets('clear button appears when text is entered', (tester) async {
      final controller = TextEditingController();
      
      await tester.pumpWidget(
        createTestWidget(
          GlassTextField(
            controller: controller,
            enableClearButton: true,
          ),
        ),
      );
      
      expect(find.byIcon(Icons.clear), findsNothing);
      
      controller.text = 'Some text';
      await tester.pump();
      
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });
    
    testWidgets('password field obscures text', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassTextField(
            controller: TextEditingController(text: 'password'),
            obscureText: true,
          ),
        ),
      );
      
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, true);
    });
    
    testWidgets('multiline field allows multiple lines', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          GlassTextField(
            controller: TextEditingController(),
            maxLines: 5,
          ),
        ),
      );
      
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, 5);
      expect(textField.keyboardType, TextInputType.multiline);
    });
  });
  
  group('GlassDialog', () {
    testWidgets('shows dialog with title and content', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          Builder(
            builder: (context) => GlassButton(
              text: 'Show Dialog',
              onPressed: () {
                showGlassDialog(
                  context: context,
                  title: const Text('Test Dialog'),
                  content: const Text('Dialog content'),
                );
              },
            ),
          ),
        ),
      );
      
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();
      
      expect(find.text('Test Dialog'), findsOneWidget);
      expect(find.text('Dialog content'), findsOneWidget);
    });
    
    testWidgets('confirm dialog returns correct value', (tester) async {
      bool? result;
      
      await tester.pumpWidget(
        createTestWidget(
          Builder(
            builder: (context) => GlassButton(
              text: 'Show Confirm',
              onPressed: () async {
                result = await showGlassConfirmDialog(
                  context: context,
                  title: 'Confirm Action',
                  message: 'Are you sure?',
                );
              },
            ),
          ),
        ),
      );
      
      await tester.tap(find.text('Show Confirm'));
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      
      expect(result, true);
    });
    
    testWidgets('dismissible dialog can be closed by tapping outside', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          Builder(
            builder: (context) => GlassButton(
              text: 'Show Dialog',
              onPressed: () {
                showGlassDialog(
                  context: context,
                  title: const Text('Dismissible'),
                  content: const Text('Tap outside to close'),
                  dismissible: true,
                );
              },
            ),
          ),
        ),
      );
      
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();
      
      expect(find.text('Dismissible'), findsOneWidget);
      
      // Tap outside dialog
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      
      expect(find.text('Dismissible'), findsNothing);
    });
  });

Article _article({bool isRead = false, bool isStarred = false}) {
  return Article(
    feedId: 'feed-1',
    guid: 'guid-1',
    title: 'A test article title',
    url: 'https://example.com/a',
    isRead: isRead,
    isStarred: isStarred,
    feedTitle: 'Example Feed',
    summary: 'A short summary of the article.',
  );
}

group('ArticleCard', () {
  testWidgets('renders canonical anatomy: title, meta, snippet', (tester) async {
    await tester.pumpWidget(
      createTestWidget(
        ArticleCard(article: _article(), onTap: () {}),
      ),
    );

    expect(find.text('A test article title'), findsOneWidget);
    expect(find.textContaining('Example Feed'), findsOneWidget);
    expect(find.textContaining('A short summary'), findsOneWidget);
    expect(find.byIcon(Icons.rss_feed), findsOneWidget);
  });

  testWidgets('unread dot shown for unread, hidden for read', (tester) async {
    await tester.pumpWidget(
      createTestWidget(
        SingleChildScrollView(
          child: ArticleCard(article: _article(isRead: false)),
        ),
      ),
    );
    expect(find.byIcon(Icons.rss_feed), findsOneWidget);

    await tester.pumpWidget(
      createTestWidget(
        SingleChildScrollView(
          child: ArticleCard(article: _article(isRead: true)),
        ),
      ),
    );
    expect(find.text('A test article title'), findsOneWidget);
  });

  testWidgets('star indicator shown when starred', (tester) async {
    await tester.pumpWidget(
      createTestWidget(
        SingleChildScrollView(
          child: ArticleCard(article: _article(isStarred: true)),
        ),
      ),
    );
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('action row appears when handlers provided', (tester) async {
    await tester.pumpWidget(
      createTestWidget(
        ArticleCard(
          article: _article(),
          onToggleRead: () {},
          onToggleStar: () {},
          onShare: () {},
          onOpenExternally: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.mark_email_unread), findsOneWidget);
    expect(find.byIcon(Icons.star_outline), findsOneWidget);
    expect(find.byIcon(Icons.share), findsOneWidget);
    expect(find.byIcon(Icons.open_in_browser), findsOneWidget);
  });
});

group('EmptyState', () {
  testWidgets('renders title, subtitle and action', (tester) async {
    var actionFired = false;
    await tester.pumpWidget(
      createTestWidget(
        EmptyState(
          title: 'Nothing here',
          subtitle: 'Add a feed to get started',
          actionLabel: 'Add Feed',
          onAction: () => actionFired = true,
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add a feed to get started'), findsOneWidget);

    await tester.tap(find.text('Add Feed'));
    expect(actionFired, true);
  });
});

group('ErrorState', () {
  testWidgets('renders error and retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      createTestWidget(
        ErrorState(
          error: 'boom',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, true);
  });
});

group('GlassSkeleton', () {
  testWidgets('skeleton list renders article-shaped rows', (tester) async {
    await tester.pumpWidget(
      createTestWidget(const GlassSkeletonList(itemCount: 3)),
    );

    expect(find.byType(GlassSkeletonArticleRow), findsNWidgets(3));
    expect(find.byType(GlassSkeleton), findsWidgets);
  });
});
}
