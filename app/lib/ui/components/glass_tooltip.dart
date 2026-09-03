import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';

/// Glass tooltip with auto-positioning
class GlassTooltip extends StatefulWidget {
  final Widget child;
  final String message;
  final double? blur;
  final List<Color>? gradientColors;
  final Duration showDuration;
  final Duration waitDuration;
  final EdgeInsets padding;
  final double verticalOffset;
  final bool preferBelow;
  final GlassThemeData? theme;

  const GlassTooltip({
    super.key,
    required this.child,
    required this.message,
    this.blur,
    this.gradientColors,
    this.showDuration = const Duration(seconds: 2),
    this.waitDuration = const Duration(milliseconds: 500),
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.verticalOffset = 8,
    this.preferBelow = true,
    this.theme,
  });

  @override
  State<GlassTooltip> createState() => _GlassTooltipState();
}

class _GlassTooltipState extends State<GlassTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
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
  }

  @override
  void dispose() {
    _removeTooltip();
    _animationController.dispose();
    super.dispose();
  }

  void _showTooltip() {
    if (_overlayEntry != null) return;
    
    final theme = widget.theme ?? GlassTheme.of(context);
    
    _overlayEntry = OverlayEntry(
      builder: (context) => _TooltipOverlay(
        message: widget.message,
        targetContext: this.context,
        animation: _animationController,
        fadeAnimation: _fadeAnimation,
        scaleAnimation: _scaleAnimation,
        blur: widget.blur ?? theme.blur,
        gradientColors: widget.gradientColors,
        padding: widget.padding,
        verticalOffset: widget.verticalOffset,
        preferBelow: widget.preferBelow,
        theme: theme,
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
    _animationController.forward();
    HapticFeedback.selectionClick();
    
    // Auto-hide after duration
    Future.delayed(widget.showDuration, () {
      if (_isHovering) {
        _removeTooltip();
      }
    });
  }

  void _removeTooltip() {
    if (_overlayEntry == null) return;
    
    _animationController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _handleMouseEnter(PointerEnterEvent event) {
    _isHovering = true;
    Future.delayed(widget.waitDuration, () {
      if (_isHovering) {
        _showTooltip();
      }
    });
  }

  void _handleMouseExit(PointerExitEvent event) {
    _isHovering = false;
    _removeTooltip();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _handleMouseEnter,
      onExit: _handleMouseExit,
      child: GestureDetector(
        onLongPress: () {
          _showTooltip();
        },
        onLongPressEnd: (_) {
          _removeTooltip();
        },
        child: widget.child,
      ),
    );
  }
}

class _TooltipOverlay extends StatelessWidget {
  final String message;
  final BuildContext targetContext;
  final AnimationController animation;
  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;
  final double blur;
  final List<Color>? gradientColors;
  final EdgeInsets padding;
  final double verticalOffset;
  final bool preferBelow;
  final GlassThemeData theme;

  const _TooltipOverlay({
    required this.message,
    required this.targetContext,
    required this.animation,
    required this.fadeAnimation,
    required this.scaleAnimation,
    required this.blur,
    this.gradientColors,
    required this.padding,
    required this.verticalOffset,
    required this.preferBelow,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _TooltipPositionDelegate(
          target: targetContext,
          verticalOffset: verticalOffset,
          preferBelow: preferBelow,
        ),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return FadeTransition(
              opacity: fadeAnimation,
              child: ScaleTransition(
                scale: scaleAnimation,
                child: _buildTooltip(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTooltip() {
    return CustomPaint(
      painter: _TooltipPainter(
        target: targetContext,
        preferBelow: preferBelow,
        color: Colors.white.withOpacity(0.1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors ?? [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TooltipPositionDelegate extends SingleChildLayoutDelegate {
  final BuildContext target;
  final double verticalOffset;
  final bool preferBelow;

  _TooltipPositionDelegate({
    required this.target,
    required this.verticalOffset,
    required this.preferBelow,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final RenderBox targetBox = target.findRenderObject() as RenderBox;
    final targetSize = targetBox.size;
    final targetPosition = targetBox.localToGlobal(Offset.zero);
    
    // Calculate horizontal position (centered on target)
    double x = targetPosition.dx + (targetSize.width - childSize.width) / 2;
    
    // Ensure tooltip stays within screen bounds horizontally
    if (x < 8) {
      x = 8;
    } else if (x + childSize.width > size.width - 8) {
      x = size.width - childSize.width - 8;
    }
    
    // Calculate vertical position
    double y;
    final spaceBelow = size.height - targetPosition.dy - targetSize.height;
    final spaceAbove = targetPosition.dy;
    
    if (preferBelow && spaceBelow >= childSize.height + verticalOffset) {
      // Show below
      y = targetPosition.dy + targetSize.height + verticalOffset;
    } else if (spaceAbove >= childSize.height + verticalOffset) {
      // Show above
      y = targetPosition.dy - childSize.height - verticalOffset;
    } else {
      // Show below anyway (not enough space)
      y = targetPosition.dy + targetSize.height + verticalOffset;
    }
    
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TooltipPositionDelegate oldDelegate) {
    return target != oldDelegate.target ||
        verticalOffset != oldDelegate.verticalOffset ||
        preferBelow != oldDelegate.preferBelow;
  }
}

class _TooltipPainter extends CustomPainter {
  final BuildContext target;
  final bool preferBelow;
  final Color color;

  _TooltipPainter({
    required this.target,
    required this.preferBelow,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path();
    final radius = const Radius.circular(8);
    
    // Draw tooltip body
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      radius,
    ));
    
    // TODO: Add arrow pointing to target
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TooltipPainter oldDelegate) {
    return false;
  }
}

/// Extension for easy tooltip usage
extension GlassTooltipExtension on Widget {
  Widget glassTooltip(
    String message, {
    double? blur,
    List<Color>? gradientColors,
    Duration showDuration = const Duration(seconds: 2),
    Duration waitDuration = const Duration(milliseconds: 500),
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    double verticalOffset = 8,
    bool preferBelow = true,
    GlassThemeData? theme,
  }) {
    return GlassTooltip(
      message: message,
      blur: blur,
      gradientColors: gradientColors,
      showDuration: showDuration,
      waitDuration: waitDuration,
      padding: padding,
      verticalOffset: verticalOffset,
      preferBelow: preferBelow,
      theme: theme,
      child: this,
    );
  }
}