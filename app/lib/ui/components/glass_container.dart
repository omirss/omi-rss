import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';

/// Base glass container with blur effects and animations
class GlassContainer extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double? blur;
  final double? opacity;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final List<Color>? gradientColors;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableHover;
  final bool enableMagneticHover;
  final double magneticRange;
  final GlassThemeData? theme;
  
  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.blur,
    this.opacity,
    this.borderRadius,
    this.padding,
    this.margin,
    this.gradientColors,
    this.onTap,
    this.onLongPress,
    this.enableHover = true,
    this.enableMagneticHover = false,
    this.magneticRange = 50.0,
    this.theme,
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _elevationController;
  late AnimationController _rippleController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  late Animation<double> _rippleAnimation;
  
  bool _isHovered = false;
  bool _isPressed = false;
  Offset _localPosition = Offset.zero;
  Offset _magneticOffset = Offset.zero;
  
  // Ripple effect
  final List<_RippleAnimation> _ripples = [];

  @override
  void initState() {
    super.initState();
    
    // Scale animation controller
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    
    // Elevation animation controller
    _elevationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // Ripple animation controller
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    // Setup animations
    _setupAnimations();
  }
  
  void _setupAnimations() {
    final theme = widget.theme ?? GlassTheme.of(context);
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: theme.hoverScale,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: theme.animationCurve,
    ));
    
    _elevationAnimation = Tween<double>(
      begin: 0.0,
      end: theme.hoverElevation * 4,
    ).animate(CurvedAnimation(
      parent: _elevationController,
      curve: theme.animationCurve,
    ));
    
    _rippleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _rippleController,
      curve: Curves.easeOut,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    
    return MouseRegion(
      onEnter: widget.enableHover ? (_) => _onHover(true) : null,
      onExit: widget.enableHover ? (_) => _onHover(false) : null,
      onHover: widget.enableMagneticHover ? _onMouseMove : null,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (details) => _onTapDown(details),
        onTapUp: (_) => _onTapUp(),
        onTapCancel: () => _onTapCancel(),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _scaleController,
            _elevationController,
            _rippleController,
          ]),
          builder: (context, child) {
            return Transform.translate(
              offset: _magneticOffset,
              child: Transform.scale(
                scale: _isPressed 
                    ? theme.clickScale 
                    : _scaleAnimation.value,
                child: Container(
                  width: widget.width,
                  height: widget.height,
                  margin: widget.margin,
                  child: Stack(
                    children: [
                      // Main glass container
                      ClipRRect(
                        borderRadius: widget.borderRadius ?? theme.borderRadius,
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
                                colors: widget.gradientColors ?? theme.gradientColors,
                              ),
                              borderRadius: widget.borderRadius ?? theme.borderRadius,
                              border: Border.all(
                                color: theme.borderColor,
                                width: theme.borderWidth,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.shadowColor.withOpacity(0.37),
                                  blurRadius: theme.shadowBlurRadius + _elevationAnimation.value,
                                  offset: Offset(
                                    theme.shadowOffset.dx,
                                    theme.shadowOffset.dy + _elevationAnimation.value,
                                  ),
                                ),
                                // Inner shadow for depth
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.1),
                                  blurRadius: 1,
                                  offset: const Offset(0, -1),
                                  spreadRadius: -1,
                                ),
                              ],
                            ),
                            padding: widget.padding,
                            child: widget.child,
                          ),
                        ),
                      ),
                      // Ripple effects
                      ..._ripples.map((ripple) => _buildRipple(ripple)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildRipple(_RippleAnimation ripple) {
    return Positioned(
      left: ripple.position.dx - ripple.radius,
      top: ripple.position.dy - ripple.radius,
      child: AnimatedBuilder(
        animation: ripple.controller,
        builder: (context, child) {
          return Container(
            width: ripple.radius * 2,
            height: ripple.radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(
                0.3 * (1 - ripple.controller.value),
              ),
            ),
          );
        },
      ),
    );
  }
  
  void _onHover(bool isHovered) {
    setState(() {
      _isHovered = isHovered;
      if (_isHovered) {
        _scaleController.forward();
        _elevationController.forward();
        HapticFeedback.selectionClick();
      } else {
        _scaleController.reverse();
        _elevationController.reverse();
        _magneticOffset = Offset.zero;
      }
    });
  }
  
  void _onMouseMove(PointerHoverEvent event) {
    if (!widget.enableMagneticHover) return;
    
    final RenderBox box = context.findRenderObject() as RenderBox;
    final center = box.size.center(Offset.zero);
    final localPosition = box.globalToLocal(event.position);
    final distance = (localPosition - center).distance;
    
    if (distance < widget.magneticRange) {
      final direction = (localPosition - center) / distance;
      final strength = 1 - (distance / widget.magneticRange);
      setState(() {
        _magneticOffset = direction * strength * 10;
      });
    } else {
      setState(() {
        _magneticOffset = Offset.zero;
      });
    }
  }
  
  void _onTapDown(TapDownDetails details) {
    setState(() {
      _isPressed = true;
      _localPosition = details.localPosition;
    });
    
    // Create ripple effect
    final ripple = _RippleAnimation(
      position: details.localPosition,
      radius: 100,
      controller: AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );
    
    _ripples.add(ripple);
    ripple.controller.forward().then((_) {
      _ripples.remove(ripple);
      ripple.controller.dispose();
    });
    
    HapticFeedback.lightImpact();
  }
  
  void _onTapUp() {
    setState(() {
      _isPressed = false;
    });
  }
  
  void _onTapCancel() {
    setState(() {
      _isPressed = false;
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _elevationController.dispose();
    _rippleController.dispose();
    for (final ripple in _ripples) {
      ripple.controller.dispose();
    }
    super.dispose();
  }
}

class _RippleAnimation {
  final Offset position;
  final double radius;
  final AnimationController controller;
  
  _RippleAnimation({
    required this.position,
    required this.radius,
    required this.controller,
  });
}