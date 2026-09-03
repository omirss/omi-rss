import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Gesture settings provider
final gestureSettingsProvider = StateNotifierProvider<GestureSettingsNotifier, GestureSettings>((ref) {
  return GestureSettingsNotifier();
});

class GestureSettings {
  final bool enableSwipeNavigation;
  final bool enablePinchToZoom;
  final bool enableDoubleTapToStar;
  final double swipeSensitivity;
  final bool hapticFeedback;

  GestureSettings({
    this.enableSwipeNavigation = true,
    this.enablePinchToZoom = true,
    this.enableDoubleTapToStar = true,
    this.swipeSensitivity = 1.0,
    this.hapticFeedback = true,
  });

  GestureSettings copyWith({
    bool? enableSwipeNavigation,
    bool? enablePinchToZoom,
    bool? enableDoubleTapToStar,
    double? swipeSensitivity,
    bool? hapticFeedback,
  }) {
    return GestureSettings(
      enableSwipeNavigation: enableSwipeNavigation ?? this.enableSwipeNavigation,
      enablePinchToZoom: enablePinchToZoom ?? this.enablePinchToZoom,
      enableDoubleTapToStar: enableDoubleTapToStar ?? this.enableDoubleTapToStar,
      swipeSensitivity: swipeSensitivity ?? this.swipeSensitivity,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
    );
  }
}

class GestureSettingsNotifier extends StateNotifier<GestureSettings> {
  GestureSettingsNotifier() : super(GestureSettings());

  void toggleSwipeNavigation() {
    state = state.copyWith(enableSwipeNavigation: !state.enableSwipeNavigation);
  }

  void togglePinchToZoom() {
    state = state.copyWith(enablePinchToZoom: !state.enablePinchToZoom);
  }

  void toggleDoubleTapToStar() {
    state = state.copyWith(enableDoubleTapToStar: !state.enableDoubleTapToStar);
  }

  void setSwipeSensitivity(double sensitivity) {
    state = state.copyWith(swipeSensitivity: sensitivity.clamp(0.5, 2.0));
  }

  void toggleHapticFeedback() {
    state = state.copyWith(hapticFeedback: !state.hapticFeedback);
  }
}

class GestureDetectorWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final VoidCallback? onDoubleTap;
  final Function(double)? onPinch;
  final bool enableNavigation;

  const GestureDetectorWrapper({
    super.key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onSwipeUp,
    this.onSwipeDown,
    this.onDoubleTap,
    this.onPinch,
    this.enableNavigation = true,
  });

  @override
  ConsumerState<GestureDetectorWrapper> createState() => _GestureDetectorWrapperState();
}

class _GestureDetectorWrapperState extends ConsumerState<GestureDetectorWrapper> {
  double _startX = 0;
  double _startY = 0;
  double _lastScale = 1.0;
  double _currentScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(gestureSettingsProvider);
    
    if (!widget.enableNavigation) {
      return widget.child;
    }

    return GestureDetector(
      onDoubleTap: settings.enableDoubleTapToStar ? widget.onDoubleTap : null,
      onScaleStart: settings.enablePinchToZoom ? _onScaleStart : null,
      onScaleUpdate: settings.enablePinchToZoom ? _onScaleUpdate : null,
      onScaleEnd: settings.enablePinchToZoom ? _onScaleEnd : null,
      onHorizontalDragStart: settings.enableSwipeNavigation ? _onHorizontalDragStart : null,
      onHorizontalDragUpdate: settings.enableSwipeNavigation ? _onHorizontalDragUpdate : null,
      onHorizontalDragEnd: settings.enableSwipeNavigation ? _onHorizontalDragEnd : null,
      onVerticalDragStart: settings.enableSwipeNavigation ? _onVerticalDragStart : null,
      onVerticalDragUpdate: settings.enableSwipeNavigation ? _onVerticalDragUpdate : null,
      onVerticalDragEnd: settings.enableSwipeNavigation ? _onVerticalDragEnd : null,
      child: widget.child,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastScale = _currentScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _currentScale = _lastScale * details.scale;
    widget.onPinch?.call(_currentScale);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _lastScale = _currentScale;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _startX = details.globalPosition.dx;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    // Visual feedback during drag could be added here
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final settings = ref.read(gestureSettingsProvider);
    final sensitivity = settings.swipeSensitivity;
    final velocity = details.primaryVelocity ?? 0;
    final minVelocity = 200 * sensitivity;

    if (velocity > minVelocity) {
      // Swipe right
      widget.onSwipeRight?.call();
      if (settings.hapticFeedback) {
        // HapticFeedback.lightImpact();
      }
    } else if (velocity < -minVelocity) {
      // Swipe left
      widget.onSwipeLeft?.call();
      if (settings.hapticFeedback) {
        // HapticFeedback.lightImpact();
      }
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _startY = details.globalPosition.dy;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // Visual feedback during drag could be added here
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final settings = ref.read(gestureSettingsProvider);
    final sensitivity = settings.swipeSensitivity;
    final velocity = details.primaryVelocity ?? 0;
    final minVelocity = 200 * sensitivity;

    if (velocity > minVelocity) {
      // Swipe down
      widget.onSwipeDown?.call();
      if (settings.hapticFeedback) {
        // HapticFeedback.lightImpact();
      }
    } else if (velocity < -minVelocity) {
      // Swipe up
      widget.onSwipeUp?.call();
      if (settings.hapticFeedback) {
        // HapticFeedback.lightImpact();
      }
    }
  }
}

// Article navigation gesture wrapper
class ArticleGestureWrapper extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onPreviousArticle;
  final VoidCallback? onNextArticle;
  final VoidCallback? onToggleStar;
  final VoidCallback? onClose;

  const ArticleGestureWrapper({
    super.key,
    required this.child,
    this.onPreviousArticle,
    this.onNextArticle,
    this.onToggleStar,
    this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetectorWrapper(
      onSwipeRight: onPreviousArticle,
      onSwipeLeft: onNextArticle,
      onSwipeDown: onClose,
      onDoubleTap: onToggleStar,
      child: child,
    );
  }
}

// Feed list gesture wrapper
class FeedListGestureWrapper extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onRefresh;
  final VoidCallback? onMarkAllAsRead;

  const FeedListGestureWrapper({
    super.key,
    required this.child,
    this.onRefresh,
    this.onMarkAllAsRead,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetectorWrapper(
      onSwipeDown: onRefresh,
      onSwipeUp: onMarkAllAsRead,
      child: child,
    );
  }
}