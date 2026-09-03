import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'glass_container.dart';
import '../glass_theme.dart';

/// Elevated glass card with depth and interactive features
class GlassCard extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final int elevation;
  final bool enableHero;
  final String? heroTag;
  final bool enableSwipeToDismiss;
  final VoidCallback? onDismissed;
  final bool enableLongPressMenu;
  final List<PopupMenuItem>? longPressMenuItems;
  final VoidCallback? onTap;
  final GlassThemeData? theme;
  
  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.elevation = 2,
    this.enableHero = false,
    this.heroTag,
    this.enableSwipeToDismiss = false,
    this.onDismissed,
    this.enableLongPressMenu = false,
    this.longPressMenuItems,
    this.onTap,
    this.theme,
  }) : assert(elevation >= 1 && elevation <= 5, 'Elevation must be between 1 and 5');

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with SingleTickerProviderStateMixin {
  late AnimationController _dismissController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDismissing = false;
  
  // For long press menu
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    
    _dismissController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.5, 0.0),
    ).animate(CurvedAnimation(
      parent: _dismissController,
      curve: Curves.easeInOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _dismissController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    final elevationMultiplier = widget.elevation * 0.2;
    
    Widget card = AnimatedBuilder(
      animation: _dismissController,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GlassContainer(
              width: widget.width,
              height: widget.height,
              padding: widget.padding,
              margin: widget.margin,
              blur: theme.blur * (1 + elevationMultiplier),
              opacity: theme.opacity * (1 + elevationMultiplier),
              gradientColors: [
                theme.gradientColors[0].withOpacity(
                  theme.gradientColors[0].opacity * (1 + elevationMultiplier),
                ),
                theme.gradientColors[1].withOpacity(
                  theme.gradientColors[1].opacity * (1 + elevationMultiplier),
                ),
              ],
              onTap: widget.onTap,
              onLongPress: widget.enableLongPressMenu ? _showLongPressMenu : null,
              child: Stack(
                children: [
                  widget.child,
                  // Elevation indicators
                  if (widget.elevation > 1)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.2 * elevationMultiplier),
                              Colors.white.withOpacity(0.1 * elevationMultiplier),
                              Colors.white.withOpacity(0.2 * elevationMultiplier),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    
    // Wrap with Hero if enabled
    if (widget.enableHero && widget.heroTag != null) {
      card = Hero(
        tag: widget.heroTag!,
        child: card,
      );
    }
    
    // Wrap with Dismissible if enabled
    if (widget.enableSwipeToDismiss) {
      card = GestureDetector(
        onTapDown: (details) {
          _tapPosition = details.globalPosition;
        },
        onHorizontalDragUpdate: (details) {
          if (details.primaryDelta! > 0 && !_isDismissing) {
            _handleDismiss();
          }
        },
        child: card,
      );
    }
    
    return card;
  }
  
  void _handleDismiss() {
    setState(() {
      _isDismissing = true;
    });
    
    HapticFeedback.mediumImpact();
    _dismissController.forward().then((_) {
      widget.onDismissed?.call();
    });
  }
  
  void _showLongPressMenu() {
    if (_tapPosition == null || widget.longPressMenuItems == null) return;
    
    HapticFeedback.heavyImpact();
    
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        _tapPosition! & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: widget.longPressMenuItems!,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  @override
  void dispose() {
    _dismissController.dispose();
    super.dispose();
  }
}

/// Predefined card elevation styles
class GlassCardElevation {
  static const int minimal = 1;
  static const int low = 2;
  static const int medium = 3;
  static const int high = 4;
  static const int extreme = 5;
}