import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Accessibility settings provider
final accessibilitySettingsProvider = StateNotifierProvider<AccessibilitySettingsNotifier, AccessibilitySettings>((ref) {
  return AccessibilitySettingsNotifier();
});

class AccessibilitySettings {
  final bool screenReaderEnabled;
  final bool reduceMotion;
  final bool largeText;
  final bool boldText;
  final bool highContrast;
  final bool announceNavigation;
  final bool verboseAnnouncements;
  final double textScaleFactor;
  
  AccessibilitySettings({
    this.screenReaderEnabled = false,
    this.reduceMotion = false,
    this.largeText = false,
    this.boldText = false,
    this.highContrast = false,
    this.announceNavigation = true,
    this.verboseAnnouncements = false,
    this.textScaleFactor = 1.0,
  });
  
  AccessibilitySettings copyWith({
    bool? screenReaderEnabled,
    bool? reduceMotion,
    bool? largeText,
    bool? boldText,
    bool? highContrast,
    bool? announceNavigation,
    bool? verboseAnnouncements,
    double? textScaleFactor,
  }) {
    return AccessibilitySettings(
      screenReaderEnabled: screenReaderEnabled ?? this.screenReaderEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      largeText: largeText ?? this.largeText,
      boldText: boldText ?? this.boldText,
      highContrast: highContrast ?? this.highContrast,
      announceNavigation: announceNavigation ?? this.announceNavigation,
      verboseAnnouncements: verboseAnnouncements ?? this.verboseAnnouncements,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
    );
  }
}

class AccessibilitySettingsNotifier extends StateNotifier<AccessibilitySettings> {
  AccessibilitySettingsNotifier() : super(AccessibilitySettings()) {
    _checkSystemSettings();
  }
  
  void _checkSystemSettings() {
    // Check system accessibility settings
    final window = WidgetsBinding.instance.window;
    
    state = state.copyWith(
      screenReaderEnabled: window.accessibilityFeatures.accessibleNavigation,
      reduceMotion: window.accessibilityFeatures.reduceMotion,
      boldText: window.accessibilityFeatures.boldText,
      textScaleFactor: window.textScaleFactor,
    );
  }
  
  void toggleScreenReader() {
    state = state.copyWith(screenReaderEnabled: !state.screenReaderEnabled);
  }
  
  void toggleReduceMotion() {
    state = state.copyWith(reduceMotion: !state.reduceMotion);
  }
  
  void toggleLargeText() {
    state = state.copyWith(largeText: !state.largeText);
  }
  
  void toggleBoldText() {
    state = state.copyWith(boldText: !state.boldText);
  }
  
  void toggleHighContrast() {
    state = state.copyWith(highContrast: !state.highContrast);
  }
  
  void toggleAnnounceNavigation() {
    state = state.copyWith(announceNavigation: !state.announceNavigation);
  }
  
  void toggleVerboseAnnouncements() {
    state = state.copyWith(verboseAnnouncements: !state.verboseAnnouncements);
  }
  
  void setTextScaleFactor(double factor) {
    state = state.copyWith(textScaleFactor: factor.clamp(0.5, 3.0));
  }
}

// Semantic wrapper widget
class SemanticWrapper extends ConsumerWidget {
  final Widget child;
  final String? label;
  final String? hint;
  final String? value;
  final bool? button;
  final bool? header;
  final bool? link;
  final bool? selected;
  final bool? enabled;
  final bool? focusable;
  final bool? focused;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onScrollLeft;
  final VoidCallback? onScrollRight;
  final VoidCallback? onScrollUp;
  final VoidCallback? onScrollDown;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
  final Map<CustomSemanticsAction, VoidCallback>? customActions;
  
  const SemanticWrapper({
    super.key,
    required this.child,
    this.label,
    this.hint,
    this.value,
    this.button,
    this.header,
    this.link,
    this.selected,
    this.enabled,
    this.focusable,
    this.focused,
    this.onTap,
    this.onLongPress,
    this.onScrollLeft,
    this.onScrollRight,
    this.onScrollUp,
    this.onScrollDown,
    this.onIncrease,
    this.onDecrease,
    this.customActions,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilitySettingsProvider);
    
    if (!settings.screenReaderEnabled) {
      return child;
    }
    
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      button: button,
      header: header,
      link: link,
      selected: selected,
      enabled: enabled ?? true,
      focusable: focusable ?? true,
      focused: focused,
      onTap: onTap,
      onLongPress: onLongPress,
      onScrollLeft: onScrollLeft,
      onScrollRight: onScrollRight,
      onScrollUp: onScrollUp,
      onScrollDown: onScrollDown,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      customSemanticsActions: customActions,
      child: child,
    );
  }
}

// Semantic announcer
class SemanticAnnouncer {
  static void announce(String message, {TextDirection textDirection = TextDirection.ltr}) {
    SemanticsService.announce(message, textDirection);
  }
  
  static void announceNavigation(String destination) {
    announce('Navigating to $destination');
  }
  
  static void announceAction(String action) {
    announce(action);
  }
  
  static void announceError(String error) {
    announce('Error: $error');
  }
  
  static void announceSuccess(String message) {
    announce('Success: $message');
  }
}

// Accessible list item widget
class AccessibleListItem extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final String? semanticLabel;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;
  final int? index;
  final int? totalCount;
  
  const AccessibleListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.semanticLabel,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.index,
    this.totalCount,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilitySettingsProvider);
    
    String label = semanticLabel ?? title;
    
    if (settings.verboseAnnouncements) {
      if (subtitle != null) {
        label += ', $subtitle';
      }
      if (index != null && totalCount != null) {
        label += ', Item ${index! + 1} of $totalCount';
      }
      if (selected) {
        label += ', Selected';
      }
      if (!enabled) {
        label += ', Disabled';
      }
    }
    
    return SemanticWrapper(
      label: label,
      hint: onTap != null ? 'Double tap to activate' : null,
      selected: selected,
      enabled: enabled,
      button: onTap != null,
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: trailing,
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        selected: selected,
        enabled: enabled,
      ),
    );
  }
}

// Accessible button widget
class AccessibleButton extends ConsumerWidget {
  final String text;
  final String? semanticLabel;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool loading;
  final ButtonStyle? style;
  
  const AccessibleButton({
    super.key,
    required this.text,
    this.semanticLabel,
    this.icon,
    this.onPressed,
    this.enabled = true,
    this.loading = false,
    this.style,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilitySettingsProvider);
    
    String label = semanticLabel ?? text;
    
    if (settings.verboseAnnouncements) {
      if (loading) {
        label += ', Loading';
      }
      if (!enabled) {
        label += ', Disabled';
      }
      label += ', Button';
    }
    
    final child = loading
      ? const CircularProgressIndicator()
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon),
              const SizedBox(width: 8),
            ],
            Text(text),
          ],
        );
    
    return SemanticWrapper(
      label: label,
      hint: enabled ? 'Double tap to activate' : null,
      button: true,
      enabled: enabled && !loading,
      onTap: enabled && !loading ? onPressed : null,
      child: ElevatedButton(
        onPressed: enabled && !loading ? onPressed : null,
        style: style,
        child: child,
      ),
    );
  }
}

// Accessible text field widget
class AccessibleTextField extends ConsumerWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? semanticLabel;
  final String? errorText;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  
  const AccessibleTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.semanticLabel,
    this.errorText,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.onEditingComplete,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilitySettingsProvider);
    
    String label = semanticLabel ?? labelText ?? '';
    
    if (settings.verboseAnnouncements) {
      if (hintText != null) {
        label += ', Hint: $hintText';
      }
      if (errorText != null) {
        label += ', Error: $errorText';
      }
      if (obscureText) {
        label += ', Password field';
      }
      if (!enabled) {
        label += ', Disabled';
      }
      label += ', Text field';
    }
    
    return SemanticWrapper(
      label: label,
      hint: 'Double tap to edit',
      value: controller?.text,
      enabled: enabled,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          errorText: errorText,
        ),
        enabled: enabled,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        onEditingComplete: onEditingComplete,
      ),
    );
  }
}

// Focus management utilities
class FocusManagement {
  static void requestFocus(BuildContext context, FocusNode node) {
    FocusScope.of(context).requestFocus(node);
  }
  
  static void nextFocus(BuildContext context) {
    FocusScope.of(context).nextFocus();
  }
  
  static void previousFocus(BuildContext context) {
    FocusScope.of(context).previousFocus();
  }
  
  static void unfocus(BuildContext context) {
    FocusScope.of(context).unfocus();
  }
}

// Screen reader utilities
class ScreenReaderUtils {
  static String formatArticleForScreenReader({
    required String title,
    required String? author,
    required DateTime? publishedDate,
    required int? readingTime,
    required bool isRead,
    required bool isStarred,
  }) {
    final parts = <String>[title];
    
    if (author != null) {
      parts.add('by $author');
    }
    
    if (publishedDate != null) {
      parts.add('published ${_formatDate(publishedDate)}');
    }
    
    if (readingTime != null) {
      parts.add('$readingTime minute read');
    }
    
    if (isStarred) {
      parts.add('starred');
    }
    
    if (isRead) {
      parts.add('read');
    } else {
      parts.add('unread');
    }
    
    return parts.join(', ');
  }
  
  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return 'on ${date.day}/${date.month}/${date.year}';
    }
  }
  
  static String formatFeedForScreenReader({
    required String title,
    required int unreadCount,
    required int totalCount,
    required DateTime? lastUpdated,
  }) {
    final parts = <String>[title];
    
    if (unreadCount > 0) {
      parts.add('$unreadCount unread articles');
    }
    
    parts.add('$totalCount total articles');
    
    if (lastUpdated != null) {
      parts.add('last updated ${_formatDate(lastUpdated)}');
    }
    
    return parts.join(', ');
  }
}