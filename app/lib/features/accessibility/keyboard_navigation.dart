import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Keyboard shortcuts provider
final keyboardShortcutsProvider = StateNotifierProvider<KeyboardShortcutsNotifier, KeyboardShortcuts>((ref) {
  return KeyboardShortcutsNotifier();
});

class KeyboardShortcuts {
  final Map<ShortcutActivator, VoidCallback> shortcuts;
  final bool enabled;
  
  KeyboardShortcuts({
    Map<ShortcutActivator, VoidCallback>? shortcuts,
    this.enabled = true,
  }) : shortcuts = shortcuts ?? {};
  
  KeyboardShortcuts copyWith({
    Map<ShortcutActivator, VoidCallback>? shortcuts,
    bool? enabled,
  }) {
    return KeyboardShortcuts(
      shortcuts: shortcuts ?? this.shortcuts,
      enabled: enabled ?? this.enabled,
    );
  }
}

class KeyboardShortcutsNotifier extends StateNotifier<KeyboardShortcuts> {
  KeyboardShortcutsNotifier() : super(KeyboardShortcuts());
  
  void registerShortcut(ShortcutActivator activator, VoidCallback callback) {
    final shortcuts = Map<ShortcutActivator, VoidCallback>.from(state.shortcuts);
    shortcuts[activator] = callback;
    state = state.copyWith(shortcuts: shortcuts);
  }
  
  void unregisterShortcut(ShortcutActivator activator) {
    final shortcuts = Map<ShortcutActivator, VoidCallback>.from(state.shortcuts);
    shortcuts.remove(activator);
    state = state.copyWith(shortcuts: shortcuts);
  }
  
  void clearShortcuts() {
    state = state.copyWith(shortcuts: {});
  }
  
  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
  }
}

// Keyboard navigation widget
class KeyboardNavigationWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final Map<ShortcutActivator, VoidCallback>? shortcuts;
  final bool autofocus;
  
  const KeyboardNavigationWrapper({
    super.key,
    required this.child,
    this.shortcuts,
    this.autofocus = true,
  });
  
  @override
  ConsumerState<KeyboardNavigationWrapper> createState() => _KeyboardNavigationWrapperState();
}

class _KeyboardNavigationWrapperState extends ConsumerState<KeyboardNavigationWrapper> {
  late FocusNode _focusNode;
  
  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    
    // Register shortcuts if provided
    if (widget.shortcuts != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final entry in widget.shortcuts!.entries) {
          ref.read(keyboardShortcutsProvider.notifier).registerShortcut(
            entry.key,
            entry.value,
          );
        }
      });
    }
  }
  
  @override
  void dispose() {
    _focusNode.dispose();
    
    // Unregister shortcuts
    if (widget.shortcuts != null) {
      for (final activator in widget.shortcuts!.keys) {
        ref.read(keyboardShortcutsProvider.notifier).unregisterShortcut(activator);
      }
    }
    
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final keyboardShortcuts = ref.watch(keyboardShortcutsProvider);
    
    if (!keyboardShortcuts.enabled) {
      return widget.child;
    }
    
    return Shortcuts(
      shortcuts: keyboardShortcuts.shortcuts.map(
        (key, value) => MapEntry(key, CallbackIntent(value)),
      ),
      child: Actions(
        actions: {
          CallbackIntent: CallbackAction<CallbackIntent>(
            onInvoke: (intent) => intent.callback(),
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          child: widget.child,
        ),
      ),
    );
  }
}

// Callback intent for shortcuts
class CallbackIntent extends Intent {
  final VoidCallback callback;
  
  const CallbackIntent(this.callback);
}

// Common keyboard shortcuts
class CommonShortcuts {
  // Navigation
  static const nextItem = SingleActivator(LogicalKeyboardKey.arrowDown);
  static const previousItem = SingleActivator(LogicalKeyboardKey.arrowUp);
  static const nextPage = SingleActivator(LogicalKeyboardKey.pageDown);
  static const previousPage = SingleActivator(LogicalKeyboardKey.pageUp);
  static const home = SingleActivator(LogicalKeyboardKey.home);
  static const end = SingleActivator(LogicalKeyboardKey.end);
  
  // Actions
  static const select = SingleActivator(LogicalKeyboardKey.enter);
  static const back = SingleActivator(LogicalKeyboardKey.escape);
  static const refresh = SingleActivator(LogicalKeyboardKey.f5);
  static const search = SingleActivator(LogicalKeyboardKey.keyF, control: true);
  static const newItem = SingleActivator(LogicalKeyboardKey.keyN, control: true);
  
  // Article actions
  static const toggleRead = SingleActivator(LogicalKeyboardKey.keyR);
  static const toggleStar = SingleActivator(LogicalKeyboardKey.keyS);
  static const openInBrowser = SingleActivator(LogicalKeyboardKey.keyO);
  static const share = SingleActivator(LogicalKeyboardKey.keyS, control: true);
  
  // View shortcuts
  static const toggleSidebar = SingleActivator(LogicalKeyboardKey.keyB, control: true);
  static const toggleFullscreen = SingleActivator(LogicalKeyboardKey.f11);
  static const zoomIn = SingleActivator(LogicalKeyboardKey.equal, control: true);
  static const zoomOut = SingleActivator(LogicalKeyboardKey.minus, control: true);
  static const resetZoom = SingleActivator(LogicalKeyboardKey.digit0, control: true);
  
  // Tab navigation
  static const nextTab = SingleActivator(LogicalKeyboardKey.tab, control: true);
  static const previousTab = SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true);
  
  // Help
  static const showHelp = SingleActivator(LogicalKeyboardKey.f1);
  static const showShortcuts = SingleActivator(LogicalKeyboardKey.slash, shift: true);
}

// Focusable list item widget
class FocusableListItem extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;
  final VoidCallback? onUnfocus;
  final bool autofocus;
  final int? index;
  
  const FocusableListItem({
    super.key,
    required this.child,
    this.onSelect,
    this.onFocus,
    this.onUnfocus,
    this.autofocus = false,
    this.index,
  });
  
  @override
  State<FocusableListItem> createState() => _FocusableListItemState();
}

class _FocusableListItemState extends State<FocusableListItem> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  
  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }
  
  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }
  
  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
    
    if (_focusNode.hasFocus) {
      widget.onFocus?.call();
    } else {
      widget.onUnfocus?.call();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        CommonShortcuts.select: const CallbackIntent(_handleSelect),
      },
      child: Actions(
        actions: {
          CallbackIntent: CallbackAction<CallbackIntent>(
            onInvoke: (intent) => intent.callback(),
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                _handleSelect();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: () {
              _focusNode.requestFocus();
              widget.onSelect?.call();
            },
            child: Container(
              decoration: BoxDecoration(
                border: _isFocused
                  ? Border.all(
                      color: Theme.of(context).primaryColor,
                      width: 2,
                    )
                  : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
  
  void _handleSelect() {
    widget.onSelect?.call();
  }
}

// Keyboard navigation helper
class KeyboardNavigationHelper {
  static void navigateToNext(BuildContext context) {
    FocusScope.of(context).nextFocus();
  }
  
  static void navigateToPrevious(BuildContext context) {
    FocusScope.of(context).previousFocus();
  }
  
  static void navigateToFirst(BuildContext context) {
    // Find first focusable widget
    final scope = FocusScope.of(context);
    FocusNode? firstNode;
    
    void findFirst(FocusNode node) {
      if (node.canRequestFocus && firstNode == null) {
        firstNode = node;
      }
      for (final child in node.children) {
        findFirst(child);
      }
    }
    
    findFirst(scope.focusedChild ?? scope);
    firstNode?.requestFocus();
  }
  
  static void navigateToLast(BuildContext context) {
    // Find last focusable widget
    final scope = FocusScope.of(context);
    FocusNode? lastNode;
    
    void findLast(FocusNode node) {
      if (node.canRequestFocus) {
        lastNode = node;
      }
      for (final child in node.children) {
        findLast(child);
      }
    }
    
    findLast(scope.focusedChild ?? scope);
    lastNode?.requestFocus();
  }
}

// Keyboard shortcuts dialog
class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildShortcutSection(
              'Navigation',
              [
                _ShortcutItem('Next item', '↓'),
                _ShortcutItem('Previous item', '↑'),
                _ShortcutItem('Next page', 'Page Down'),
                _ShortcutItem('Previous page', 'Page Up'),
                _ShortcutItem('Go to first', 'Home'),
                _ShortcutItem('Go to last', 'End'),
              ],
            ),
            const SizedBox(height: 16),
            _buildShortcutSection(
              'Actions',
              [
                _ShortcutItem('Select/Open', 'Enter'),
                _ShortcutItem('Go back', 'Esc'),
                _ShortcutItem('Refresh', 'F5'),
                _ShortcutItem('Search', 'Ctrl+F'),
                _ShortcutItem('New item', 'Ctrl+N'),
              ],
            ),
            const SizedBox(height: 16),
            _buildShortcutSection(
              'Article Actions',
              [
                _ShortcutItem('Toggle read', 'R'),
                _ShortcutItem('Toggle star', 'S'),
                _ShortcutItem('Open in browser', 'O'),
                _ShortcutItem('Share', 'Ctrl+S'),
              ],
            ),
            const SizedBox(height: 16),
            _buildShortcutSection(
              'View',
              [
                _ShortcutItem('Toggle sidebar', 'Ctrl+B'),
                _ShortcutItem('Fullscreen', 'F11'),
                _ShortcutItem('Zoom in', 'Ctrl++'),
                _ShortcutItem('Zoom out', 'Ctrl+-'),
                _ShortcutItem('Reset zoom', 'Ctrl+0'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
  
  Widget _buildShortcutSection(String title, List<_ShortcutItem> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...shortcuts.map((shortcut) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(shortcut.action),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.withOpacity(0.5)),
                ),
                child: Text(
                  shortcut.keys,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

class _ShortcutItem {
  final String action;
  final String keys;
  
  const _ShortcutItem(this.action, this.keys);
}