import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';

/// Glass button variants
enum GlassButtonVariant {
  elevated,
  outlined,
  text,
  icon,
  fab,
}

/// Glass button with multiple variants and loading states
class GlassButton extends StatefulWidget {
  final String? text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double? width;
  final double? height;
  final GlassButtonVariant variant;
  final Color? textColor;
  final double? fontSize;
  final EdgeInsets? padding;
  final GlassThemeData? theme;
  final Widget? child;
  
  const GlassButton({
    super.key,
    this.text,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.width,
    this.height = 56,
    this.variant = GlassButtonVariant.elevated,
    this.textColor,
    this.fontSize = 16,
    this.padding,
    this.theme,
    this.child,
  }) : assert(text != null || icon != null || child != null, 
       'Either text, icon, or child must be provided');

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late AnimationController _pressController;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _scaleAnimation;
  
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    
    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _pressController,
      curve: Curves.easeInOut,
    ));
    
    if (widget.isLoading) {
      _shimmerController.repeat();
    }
  }
  
  @override
  void didUpdateWidget(GlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isLoading && !oldWidget.isLoading) {
      _shimmerController.repeat();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _shimmerController.stop();
      _shimmerController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    final isDisabled = widget.onPressed == null || widget.isLoading;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: isDisabled ? null : (_) => _handleTapDown(),
        onTapUp: isDisabled ? null : (_) => _handleTapUp(),
        onTapCancel: () => _handleTapCancel(),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: _buildButton(theme, isDisabled),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildButton(GlassThemeData theme, bool isDisabled) {
    switch (widget.variant) {
      case GlassButtonVariant.elevated:
        return _buildElevatedButton(theme, isDisabled);
      case GlassButtonVariant.outlined:
        return _buildOutlinedButton(theme, isDisabled);
      case GlassButtonVariant.text:
        return _buildTextButton(theme, isDisabled);
      case GlassButtonVariant.icon:
        return _buildIconButton(theme, isDisabled);
      case GlassButtonVariant.fab:
        return _buildFabButton(theme, isDisabled);
    }
  }
  
  Widget _buildElevatedButton(GlassThemeData theme, bool isDisabled) {
    return Container(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          // Glass background
          ClipRRect(
            borderRadius: theme.borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: theme.blur,
                sigmaY: theme.blur,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDisabled
                        ? [
                            Colors.grey.withOpacity(0.2),
                            Colors.grey.withOpacity(0.1),
                          ]
                        : _isHovered
                            ? [
                                theme.gradientColors[0].withOpacity(0.3),
                                theme.gradientColors[1].withOpacity(0.2),
                              ]
                            : theme.gradientColors,
                  ),
                  borderRadius: theme.borderRadius,
                  border: Border.all(
                    color: isDisabled
                        ? Colors.grey.withOpacity(0.3)
                        : theme.borderColor,
                    width: theme.borderWidth,
                  ),
                  boxShadow: isDisabled
                      ? []
                      : [
                          BoxShadow(
                            color: theme.shadowColor.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
              ),
            ),
          ),
          // Shimmer effect when loading
          if (widget.isLoading)
            AnimatedBuilder(
              animation: _shimmerAnimation,
              builder: (context, child) {
                return ClipRRect(
                  borderRadius: theme.borderRadius,
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.3),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                        transform: GradientRotation(_shimmerAnimation.value),
                      ).createShader(rect);
                    },
                    child: Container(
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
          // Button content
          Center(
            child: Padding(
              padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: _buildContent(theme, isDisabled),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOutlinedButton(GlassThemeData theme, bool isDisabled) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: theme.borderRadius,
        border: Border.all(
          color: isDisabled
              ? Colors.grey.withOpacity(0.3)
              : _isHovered
                  ? theme.borderColor.withOpacity(0.5)
                  : theme.borderColor,
          width: 2,
        ),
      ),
      child: Center(
        child: Padding(
          padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _buildContent(theme, isDisabled),
        ),
      ),
    );
  }
  
  Widget _buildTextButton(GlassThemeData theme, bool isDisabled) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: theme.borderRadius,
        color: _isHovered ? Colors.white.withOpacity(0.1) : Colors.transparent,
      ),
      child: Center(
        child: Padding(
          padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildContent(theme, isDisabled),
        ),
      ),
    );
  }
  
  Widget _buildIconButton(GlassThemeData theme, bool isDisabled) {
    return Container(
      width: widget.width ?? 48,
      height: widget.height ?? 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDisabled
              ? [
                  Colors.grey.withOpacity(0.2),
                  Colors.grey.withOpacity(0.1),
                ]
              : theme.gradientColors,
        ),
        border: Border.all(
          color: isDisabled
              ? Colors.grey.withOpacity(0.3)
              : theme.borderColor,
          width: theme.borderWidth,
        ),
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: theme.blur,
            sigmaY: theme.blur,
          ),
          child: Center(
            child: _buildContent(theme, isDisabled),
          ),
        ),
      ),
    );
  }
  
  Widget _buildFabButton(GlassThemeData theme, bool isDisabled) {
    return Container(
      width: widget.width ?? 56,
      height: widget.height ?? 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: isDisabled
            ? []
            : [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: theme.blur * 1.5,
            sigmaY: theme.blur * 1.5,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDisabled
                    ? [
                        Colors.grey.withOpacity(0.3),
                        Colors.grey.withOpacity(0.2),
                      ]
                    : [
                        theme.gradientColors[0].withOpacity(0.4),
                        theme.gradientColors[1].withOpacity(0.3),
                      ],
              ),
              border: Border.all(
                color: isDisabled
                    ? Colors.grey.withOpacity(0.3)
                    : theme.borderColor.withOpacity(0.5),
                width: theme.borderWidth,
              ),
            ),
            child: Center(
              child: _buildContent(theme, isDisabled),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildContent(GlassThemeData theme, bool isDisabled) {
    if (widget.isLoading) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          color: widget.textColor ?? Colors.white,
          strokeWidth: 2,
        ),
      );
    }
    
    if (widget.child != null) {
      return widget.child!;
    }
    
    final color = widget.textColor ?? 
        (isDisabled ? Colors.grey : Colors.white);
    
    if (widget.icon != null && widget.text != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            widget.text!,
            style: TextStyle(
              color: color,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    } else if (widget.icon != null) {
      return Icon(
        widget.icon,
        color: color,
        size: widget.variant == GlassButtonVariant.fab ? 28 : 24,
      );
    } else {
      return Text(
        widget.text!,
        style: TextStyle(
          color: color,
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w600,
        ),
      );
    }
  }
  
  void _handleTapDown() {
    setState(() => _isPressed = true);
    _pressController.forward();
    HapticFeedback.lightImpact();
  }
  
  void _handleTapUp() {
    setState(() => _isPressed = false);
    _pressController.reverse();
    widget.onPressed?.call();
  }
  
  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pressController.dispose();
    super.dispose();
  }
}