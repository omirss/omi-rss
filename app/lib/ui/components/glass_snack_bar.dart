import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';
import 'glass_button.dart';

/// Glass snackbar types
enum GlassSnackBarType {
  info(Icons.info_outline, Color(0xFF2196F3)),
  success(Icons.check_circle_outline, Color(0xFF4CAF50)),
  warning(Icons.warning_amber_outlined, Color(0xFFFF9800)),
  error(Icons.error_outline, Color(0xFFF44336));

  final IconData icon;
  final Color color;

  const GlassSnackBarType(this.icon, this.color);
}

/// Glass snackbar with queue management
class GlassSnackBar extends StatefulWidget {
  final String message;
  final GlassSnackBarType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismissed;
  final double? blur;
  final List<Color>? gradientColors;
  final GlassThemeData? theme;

  const GlassSnackBar({
    super.key,
    required this.message,
    this.type = GlassSnackBarType.info,
    this.duration = const Duration(seconds: 4),
    this.actionLabel,
    this.onAction,
    this.onDismissed,
    this.blur,
    this.gradientColors,
    this.theme,
  });

  @override
  State<GlassSnackBar> createState() => _GlassSnackBarState();
}

class _GlassSnackBarState extends State<GlassSnackBar>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _progressController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  Timer? _dismissTimer;
  double _dragOffset = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    
    // Main animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    
    // Progress animation controller
    _progressController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    // Setup animations
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    // Start animations
    _animationController.forward();
    _progressController.forward();
    
    // Start auto-dismiss timer
    _startDismissTimer();
    
    HapticFeedback.lightImpact();
  }

  void _startDismissTimer() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(widget.duration, () {
      if (mounted && !_isDragging) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      widget.onDismissed?.call();
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta.dx;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });

    // Dismiss if dragged far enough
    if (_dragOffset.abs() > 100) {
      _dismiss();
      HapticFeedback.mediumImpact();
    } else {
      // Snap back
      setState(() {
        _dragOffset = 0;
      });
      // Restart timer
      _startDismissTimer();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animationController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    
    return AnimatedBuilder(
      animation: Listenable.merge([_animationController, _progressController]),
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: GestureDetector(
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                child: Transform.translate(
                  offset: Offset(_dragOffset, 0),
                  child: _buildSnackBar(theme),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSnackBar(GlassThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: widget.blur ?? theme.blur,
            sigmaY: widget.blur ?? theme.blur,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.gradientColors ?? [
                  widget.type.color.withOpacity(0.2),
                  widget.type.color.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.type.color.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.type.color.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Progress indicator
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, child) {
                      return LinearProgressIndicator(
                        value: 1 - _progressController.value,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.type.color.withOpacity(0.3),
                        ),
                        minHeight: 2,
                      );
                    },
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.type.icon,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null) ...[
                        const SizedBox(width: 12),
                        GlassButton(
                          text: widget.actionLabel!,
                          onPressed: () {
                            widget.onAction?.call();
                            _dismiss();
                          },
                          variant: GlassButtonVariant.text,
                          height: 32,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass snackbar manager for queue management
class GlassSnackBarManager extends StatefulWidget {
  final Widget child;

  const GlassSnackBarManager({
    super.key,
    required this.child,
  });

  static GlassSnackBarManagerState? of(BuildContext context) {
    return context.findAncestorStateOfType<GlassSnackBarManagerState>();
  }

  @override
  State<GlassSnackBarManager> createState() => GlassSnackBarManagerState();
}

class GlassSnackBarManagerState extends State<GlassSnackBarManager> {
  final Queue<_SnackBarEntry> _queue = Queue<_SnackBarEntry>();
  _SnackBarEntry? _currentSnackBar;
  
  void showSnackBar({
    required String message,
    GlassSnackBarType type = GlassSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
    double? blur,
    List<Color>? gradientColors,
    GlassThemeData? theme,
  }) {
    final entry = _SnackBarEntry(
      message: message,
      type: type,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      blur: blur,
      gradientColors: gradientColors,
      theme: theme,
    );

    setState(() {
      _queue.add(entry);
    });

    if (_currentSnackBar == null) {
      _showNext();
    }
  }

  void _showNext() {
    if (_queue.isEmpty) {
      setState(() {
        _currentSnackBar = null;
      });
      return;
    }

    setState(() {
      _currentSnackBar = _queue.removeFirst();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentSnackBar != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: GlassSnackBar(
              key: ValueKey(_currentSnackBar.hashCode),
              message: _currentSnackBar!.message,
              type: _currentSnackBar!.type,
              duration: _currentSnackBar!.duration,
              actionLabel: _currentSnackBar!.actionLabel,
              onAction: _currentSnackBar!.onAction,
              onDismissed: _showNext,
              blur: _currentSnackBar!.blur,
              gradientColors: _currentSnackBar!.gradientColors,
              theme: _currentSnackBar!.theme,
            ),
          ),
      ],
    );
  }
}

class _SnackBarEntry {
  final String message;
  final GlassSnackBarType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double? blur;
  final List<Color>? gradientColors;
  final GlassThemeData? theme;

  _SnackBarEntry({
    required this.message,
    required this.type,
    required this.duration,
    this.actionLabel,
    this.onAction,
    this.blur,
    this.gradientColors,
    this.theme,
  });
}

/// Extension for easy snackbar showing
extension GlassSnackBarExtension on BuildContext {
  void showGlassSnackBar(
    String message, {
    GlassSnackBarType type = GlassSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    GlassSnackBarManager.of(this)?.showSnackBar(
      message: message,
      type: type,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void showSuccessSnackBar(String message) {
    showGlassSnackBar(message, type: GlassSnackBarType.success);
  }

  void showErrorSnackBar(String message) {
    showGlassSnackBar(message, type: GlassSnackBarType.error);
  }

  void showWarningSnackBar(String message) {
    showGlassSnackBar(message, type: GlassSnackBarType.warning);
  }
}