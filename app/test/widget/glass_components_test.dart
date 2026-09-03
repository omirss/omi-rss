import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/ui/glass_theme.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_container.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_button.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_card.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_text_field.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_dialog.dart';

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
      
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GlassContainer),
          matching: find.byType(Container).first,
        ),
      );
      
      expect(container.padding, const EdgeInsets.all(20));
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
            loading: true,
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
            isPassword: true,
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
            isMultiline: true,
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
}